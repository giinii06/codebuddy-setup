#!/bin/sh
payload=$(cat)
printf '%s\n' "$payload" >> "$HOME/.wb-switch/hook-events.jsonl"
printf '{}'
