#!/usr/bin/env bash
set -euo pipefail

# Pixels of tolerance to account for gaps/borders/padding.
TOL=8

is_horizontal() {
  # stdin: JSON of the root node (bspc query -T -n @/)
  # Returns 0 if split is horizontal (children side-by-side), 1 otherwise.
  # If the root is a leaf, we treat it as fine (nothing to fix).
  local w1 h1 w2 h2
  read -r w1 h1 w2 h2 < <(jq -r '
    if .type == "internal" and (.firstChild|type=="object") and (.secondChild|type=="object") then
      (.firstChild.rectangle.width|tostring) + " " +
      (.firstChild.rectangle.height|tostring) + " " +
      (.secondChild.rectangle.width|tostring) + " " +
      (.secondChild.rectangle.height|tostring)
    else
      "0 0 0 0"
    end
  ')

  # If not internal (single window on the desktop), nothing to enforce.
  if [ "$w1" = "0" ]; then
    return 0
  fi

  # Absolute diffs
  local dh dw
  dh=$(( h1>h2 ? h1-h2 : h2-h1 ))
  dw=$(( w1> w2 ? w1-w2 : w2-w1 ))

  # Horizontal split: heights ~ equal, widths differ
  if [ "$dh" -le "$TOL" ] && [ "$dw" -gt "$TOL" ]; then
    return 0
  fi

  return 1
}

fix_root() {
  # Work on the focused desktop only.
  local root_id
  root_id=$(bspc query -N -d focused -n @/) || return 0

  # If fewer than 2 leaves, nothing to do.
  local leaves
  leaves=$(bspc query -N -d focused -n .leaf | wc -l)
  [ "$leaves" -lt 2 ] && return 0

  local root_json
  root_json=$(bspc query -T -n "$root_id")

  # If splitType is present, prefer it (fast path).
  # Values (when present) are typically "horizontal" or "vertical".
  local split
  split=$(printf '%s\n' "$root_json" | jq -r '.splitType // empty')
  if [ -n "$split" ]; then
    if [ "$split" = "vertical" ]; then
      bspc node "$root_id" -R 90
    fi
    return 0
  fi

  # Fallback: geometry-based detection (robust to version differences).
  if ! printf '%s\n' "$root_json" | is_horizontal; then
    bspc node "$root_id" -R 90
  fi
}

# Initial pass (covers current desktop immediately).
fix_root

# React to events that can change the root split.
# node_add: new window; node_transfer/node_swap: moves & swaps;
# desktop_layout: layout toggles; monitor_geometry: screen changes.
bspc subscribe node_add node_transfer node_swap desktop_layout monitor_geometry | while read -r _; do
  fix_root
done
