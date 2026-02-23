#!/usr/bin/env bash

set -euo pipefail

active=$(task +ACTIVE count 2>/dev/null || echo 0)
pending=$(task +PENDING -ACTIVE -WAITING count 2>/dev/null || echo 0)
waiting=$(task +WAITING count 2>/dev/null || echo 0)

stale=0
if [[ "$active" -gt 0 ]]; then
  threshold=$(date -u -v-24H +%Y%m%dT%H%M%SZ 2>/dev/null || date -u -d '24 hours ago' +%Y%m%dT%H%M%SZ 2>/dev/null)
  stale=$(task +ACTIVE export 2>/dev/null | jq --arg t "$threshold" '
    [.[] | select(
      ([.annotations[]?.entry // empty] | sort | last // .start // .entry) < $t
    )] | length
  ')
fi

next_desc=$(task +next +PENDING -ACTIVE export 2>/dev/null | jq -r '.[0].description // empty')

focus=()

if [[ "$stale" -gt 0 ]]; then
  focus+=("#[fg=#fb4934]⚠ ${stale} stale")
fi

if [[ "$active" -eq 1 ]]; then
  active_desc=$(task +ACTIVE export 2>/dev/null | jq -r '.[0].description // empty')
  focus+=("#[fg=#b8bb26]${active_desc}")
elif [[ "$active" -gt 1 ]]; then
  focus+=("#[fg=#b8bb26]${active} active")
fi

if [[ -n "$next_desc" && "$next_desc" != "${active_desc:-}" ]]; then
  focus+=("#[fg=#fabd2f]Next: ${next_desc}")
fi

counts=()

if [[ "$pending" -gt 0 ]]; then
  counts+=("#[fg=#83a598]${pending} queued")
fi

day_of_week=$(date +%u)
if [[ "$waiting" -gt 0 && "$day_of_week" -eq 1 ]]; then
  counts+=("#[fg=#fe8019]${waiting} on hold")
fi

if [[ ${#focus[@]} -gt 0 && ${#counts[@]} -gt 0 ]]; then
  echo "${focus[*]} #[fg=#ebdbb2]│ ${counts[*]}"
elif [[ ${#focus[@]} -gt 0 ]]; then
  echo "${focus[*]}"
else
  echo "${counts[*]}"
fi
