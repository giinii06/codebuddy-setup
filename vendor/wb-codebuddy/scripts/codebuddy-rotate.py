#!/usr/bin/env python3
"""Restart CodeBuddy CLI on the next account when a turn ends with a 429.

CodeBuddy caches the apiKeyHelper token for the life of the process, so a
running session cannot pick up a new account. This wrapper owns the process:
it watches the Stop hook events for its own session, kills the CLI when a turn
fails on a rate limit, switches the account, and resumes the conversation.

The switch happens only after the old process is gone. `~/.wb-switch` and the
desktop app assume the invariant "a live CLI process holds the key of
state.json's activeAccountId"; writing state while the old process still runs
would break it and make the desktop ledger drop the event as misattributed.
"""

import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
import uuid
from pathlib import Path

HOME = Path(os.environ.get("WB_SWITCH_HOME") or Path.home())
STORE = HOME / ".wb-switch"
ACCOUNTS = STORE / "accounts.json"
STATE = HOME / ".codebuddy-rotate" / "state.json"
EVENTS = STORE / "hook-events.jsonl"
LOG = STORE / "logs" / "codebuddy-rotate.log"

CLI = os.environ.get("WB_CODEBUDDY_BIN") or "codebuddy"

# Stop events already handled, shared across restarts so a replayed 429 does not
# rotate twice; CHILD lets a signal handler stop the CLI before exiting.
SEEN = set()
CHILD = None

PASSTHROUGH = {"config", "mcp", "agents", "help", "doctor", "update"}
SESSION_FLAGS = {"--session-id", "--resume", "-r"}
FLAGS_WITH_VALUE = {
    "--model",
    "--agent",
    "--permission-mode",
    "--subagent-permission-mode",
    "--settings",
    "--add-dir",
    "--mcp-config",
    "--channels",
    "--tools",
    "--allowedTools",
    "--disallowedTools",
    "--system-prompt",
    "--append-system-prompt",
    "--output-format",
    "--input-format",
    "--json-schema",
    "--fallback-model",
    "--max-turns",
    "--effort",
    "--text-to-image-model",
    "--image-to-image-model",
    "--header",
    "--session-id",
    "--resume",
    "-r",
    "--port",
    "--host",
    "--base-path",
    "--auth",
}

CONTINUATION = "Continue from where you left off. The previous account hit a rate limit."

# The billed `deepseek-v4.1-flash-sg` variant shows the same name as the free one
# in the picker; pin the free id so a session never starts on the billed model.
DEFAULT_MODEL = "deepseek-v4.1-flash"


def log(message):
    try:
        LOG.parent.mkdir(parents=True, exist_ok=True)
        stamp = time.strftime("%Y-%m-%dT%H:%M:%S%z")
        with LOG.open("a", encoding="utf-8") as handle:
            handle.write(f"{stamp} {message}\n")
    except OSError:
        pass


def read_json(path, fallback):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return fallback


def write_state(accounts, index):
    state = read_json(STATE, {})
    if not isinstance(state, dict):
        state = {}
    state["active"] = index
    state["activeAccountId"] = accounts[index].get("id")
    state["updatedAt"] = int(time.time() * 1000)
    STATE.parent.mkdir(parents=True, exist_ok=True)
    temp = STATE.parent / (STATE.name + ".tmp")
    temp.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.chmod(temp, 0o600)
    os.replace(temp, STATE)


def current_account_id():
    state = read_json(STATE, {})
    if not isinstance(state, dict):
        return None
    return state.get("activeAccountId")


def pick_next(accounts, current_id, current_index=0, tried=None):
    """Next usable account after the current one, or None when none is left."""
    if not accounts:
        return None
    start = current_index
    for index, account in enumerate(accounts):
        if account.get("id") == current_id:
            start = index
            break
    for offset in range(1, len(accounts) + 1):
        index = (start + offset) % len(accounts)
        account = accounts[index]
        if account.get("id") == current_id:
            continue
        if tried and account.get("id") in tried:
            continue
        if account.get("needs_relogin") is True:
            continue
        token = account.get("access_token")
        if not isinstance(token, str) or not token.strip():
            continue
        return index, account
    return None


def next_account(tried=None):
    """The account to switch to, without writing anything."""
    accounts = read_json(ACCOUNTS, [])
    if not isinstance(accounts, list) or not accounts:
        return None
    state = read_json(STATE, {})
    current_id = state.get("activeAccountId") if isinstance(state, dict) else None
    current_index = state.get("active") if isinstance(state, dict) else 0
    if not isinstance(current_index, int) or current_index < 0:
        current_index = 0
    picked = pick_next(accounts, current_id, current_index, tried)
    if picked is None:
        return None
    index, account = picked
    return index, account, accounts


def rotate(tried=None):
    """Switch to the next account. Call only when no CLI process is running."""
    picked = next_account(tried)
    if picked is None:
        log("rotate skipped: no eligible account")
        return None
    index, account, accounts = picked
    write_state(accounts, index)
    name = account.get("nickname") or account.get("email") or account.get("id")
    log(f"rotated to index={index + 1} id={account.get('id')} name={name}")
    if tried is not None:
        tried.add(account.get("id"))
    return account


QUOTA_MARKERS = ("frequency limit", "usage exceeds", "超出频率限制")
RESET_TIME = re.compile(r"(?:will reset at|将在)\s*([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})\s*(UTC[+-][0-9]{1,2})?")


def is_429(text):
    return "429" in text and any(marker in text for marker in QUOTA_MARKERS)


def reset_time(message):
    found = RESET_TIME.search(message or "")
    if not found:
        return None
    return f"{found.group(1)} {found.group(2)}".strip()


REQUEST_ID = re.compile(r"\(([0-9a-f]{32})/")


def request_time(message):
    """Milliseconds at which the 429 request itself was sent.

    The trailing `(requestId/sessionId)` segment carries a UUIDv7 requestId
    whose first 12 hex digits are the request time. Used to tell a fresh 429
    from a stale one replayed after `--resume`.
    """
    found = REQUEST_ID.findall(message)
    if not found:
        return None
    hex_id = found[-1]
    if hex_id[12] != "7":
        return None
    try:
        variant = int(hex_id[16:18], 16)
    except ValueError:
        return None
    if variant >> 6 != 0b10:
        return None
    try:
        at = int(hex_id[:12], 16)
    except ValueError:
        return None
    return at if at >= 1_704_067_200_000 else None


def session_id_from(args):
    for index, arg in enumerate(args):
        if arg in SESSION_FLAGS and index + 1 < len(args):
            return args[index + 1]
        for flag in ("--session-id=", "--resume="):
            if arg.startswith(flag):
                return arg[len(flag):]
    return None


def has_flag(args, names):
    return any(arg in names or any(arg.startswith(name + "=") for name in names) for arg in args)


def ensure_session(args):
    found = session_id_from(args)
    if found:
        return found, args
    if has_flag(args, ("-c", "--continue")):
        return None, args
    session_id = str(uuid.uuid4())
    return session_id, args + ["--session-id", session_id]


def strip_session(args):
    """Drop session flags and positional prompts; keep options and their values."""
    out = []
    index = 0
    while index < len(args):
        arg = args[index]
        if arg in SESSION_FLAGS:
            index += 2
            continue
        if arg.startswith("--session-id=") or arg.startswith("--resume="):
            index += 1
            continue
        if arg in ("-c", "--continue"):
            index += 1
            continue
        if arg in FLAGS_WITH_VALUE:
            out.extend(args[index:index + 2])
            index += 2
            continue
        if arg.startswith("-"):
            out.append(arg)
            index += 1
            continue
        # Positional prompt: the turn already ran, resuming supplies a new one.
        index += 1
    return out


def resume_args(args, session_id):
    base = strip_session(args)
    if session_id:
        return base + ["--resume", session_id, CONTINUATION]
    # `--continue` run: no id to resume, but -c picks the session that just failed.
    return base + ["-c", CONTINUATION]


def is_passthrough(args):
    if any(arg in ("--help", "-h", "--version", "-V", "-v") for arg in args):
        return True
    index = 0
    while index < len(args):
        arg = args[index]
        if arg in FLAGS_WITH_VALUE:
            index += 2
            continue
        if arg.startswith("-"):
            index += 1
            continue
        return arg in PASSTHROUGH
    return False


class Watcher(threading.Thread):
    """Kill the CLI when its own session ends a turn on a rate limit."""

    def __init__(self, session_id, cwd, seen, child_started_ms, tried):
        super().__init__(daemon=True)
        self.session_id = session_id
        self.cwd = cwd
        self.seen = seen
        self.child_started_ms = child_started_ms
        self.tried = tried
        self.stop_flag = threading.Event()
        self.fired = False
        self.exhausted = False
        self.reason = None
        self.offset = 0
        self.buffer = ""

    def run(self):
        self.offset = EVENTS.stat().st_size if EVENTS.exists() else 0
        self.buffer = ""
        while not self.stop_flag.is_set():
            if not EVENTS.exists():
                time.sleep(0.3)
                continue
            if self.poll_once():
                return
            time.sleep(0.2)

    def poll_once(self):
        """Read whatever is new; True when a handled event stopped the watch."""
        try:
            with EVENTS.open("r", encoding="utf-8", errors="replace") as handle:
                handle.seek(self.offset)
                chunk = handle.read()
                self.offset = handle.tell()
        except OSError:
            return False
        if not chunk:
            return False
        self.buffer += chunk
        lines = self.buffer.split("\n")
        self.buffer = lines.pop()
        for line in lines:
            if self.handle(line):
                return True
        return False

    def settle(self, seconds=0.4):
        """Catch a Stop event written just before the CLI exited."""
        deadline = time.time() + seconds
        while time.time() < deadline:
            if self.poll_once():
                return True
            time.sleep(0.05)
        return False

    def belongs_to_us(self, event):
        if self.session_id:
            return event.get("session_id") == self.session_id
        cwd = event.get("cwd")
        return bool(cwd) and os.path.realpath(cwd) == self.cwd

    def handle(self, line):
        try:
            event = json.loads(line)
        except ValueError:
            return False
        if not isinstance(event, dict):
            return False
        if event.get("hook_event_name") != "Stop":
            return False
        if event.get("stop_reason") != "failed":
            return False
        message = event.get("last_assistant_message") or ""
        if not is_429(message):
            return False
        if not self.belongs_to_us(event):
            return False
        generation = event.get("generation_id")
        if generation and generation in self.seen:
            return False
        # A resumed session replays the last assistant message, which may be the
        # 429 of a previous account. Only act on a request sent by this process.
        at = request_time(message)
        if at is not None and at < self.child_started_ms:
            log(f"ignored stale 429 (request {at} < process start {self.child_started_ms})")
            return False
        if generation:
            self.seen.add(generation)
        self.reason = message.strip().splitlines()[0][:160]
        # Nothing left to try: keep the CLI alive so the real 429 stands.
        if next_account(self.tried) is None:
            self.exhausted = True
            self.stop_flag.set()
            log("no usable account left; not switching")
            return True
        self.fired = True
        self.stop_flag.set()
        return True


def tty_state():
    try:
        import termios

        if sys.stdin.isatty():
            return termios.tcgetattr(sys.stdin.fileno())
    except (ImportError, OSError):
        pass
    return None


def tty_restore(state):
    """The TUI does not restore the terminal when killed; do it here."""
    if state is None:
        return
    try:
        import termios

        termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, state)
    except (ImportError, OSError):
        pass
    try:
        sys.stdout.write("\x1b[?25h")
        sys.stdout.flush()
    except (OSError, ValueError):
        pass


def run_once(args, session_id, tried):
    """Run the CLI once; returns (exit code, watcher)."""
    global CHILD
    started_ms = int(time.time() * 1000)
    saved_tty = tty_state()
    process = subprocess.Popen([CLI] + args)
    CHILD = process
    watcher = Watcher(session_id, os.path.realpath(os.getcwd()), SEEN, started_ms, tried)
    watcher.start()
    terminated_at = None
    while True:
        try:
            code = process.wait(timeout=0.25)
            break
        except subprocess.TimeoutExpired:
            pass
        except KeyboardInterrupt:
            # Ctrl+C goes to the whole foreground group; the TUI owns it.
            continue
        if not watcher.fired:
            continue
        # The TUI ignores SIGTERM, so escalate after a short grace period.
        if terminated_at is None:
            try:
                process.terminate()
            except ProcessLookupError:
                pass
            terminated_at = time.time()
        elif time.time() - terminated_at > 1.5:
            try:
                process.kill()
            except ProcessLookupError:
                pass
            terminated_at = time.time()
    watcher.stop_flag.set()
    watcher.join(timeout=3)
    if not watcher.fired and not watcher.exhausted:
        watcher.settle()
    if watcher.fired:
        tty_restore(saved_tty)
    return code, watcher


def on_term(signum, _frame):
    """Do not leave the CLI running when the wrapper is told to stop."""
    if CHILD is not None and CHILD.poll() is None:
        try:
            CHILD.terminate()
            CHILD.wait(timeout=0.5)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            try:
                CHILD.kill()
            except ProcessLookupError:
                pass
    sys.exit(128 + signum)


def report_exhausted(message, tried):
    reset = reset_time(message)
    suffix = f", usage resets at {reset}" if reset else ""
    print(
        f"codebuddy-rotate: no usable account left after {len(tried)} tries{suffix}",
        file=sys.stderr,
    )
    log(f"exhausted after {len(tried)} accounts, reset={reset}")


def run(args):
    if not has_flag(args, ("--model",)):
        args = ["--model", DEFAULT_MODEL] + args
    session_id, args = ensure_session(args)
    active = current_account_id()
    tried = {active} if active else set()
    while True:
        code, watcher = run_once(args, session_id, tried)
        if watcher.exhausted:
            report_exhausted(watcher.reason, tried)
            return code
        if not watcher.fired:
            return code
        account = rotate(tried)
        if account is None:
            report_exhausted(watcher.reason, tried)
            return code
        name = account.get("nickname") or account.get("email") or account.get("id")
        log(f"rate limited: {watcher.reason}")
        print(f"codebuddy-rotate: rate limited, switched to {name}", file=sys.stderr)
        args = resume_args(args, session_id)


def main():
    args = sys.argv[1:]
    if is_passthrough(args):
        os.execvp(CLI, [CLI] + args)
    signal.signal(signal.SIGTERM, on_term)
    try:
        sys.exit(run(args))
    except KeyboardInterrupt:
        sys.exit(130)


if __name__ == "__main__":
    main()
