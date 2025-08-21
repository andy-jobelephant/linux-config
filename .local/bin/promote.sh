#!/usr/bin/env bash
# Make focused window the anchor (first at root) while preserving the spiral's original start.
# - Preserves automatic_scheme/initial_polarity
# - Preserves root preselection (direction) if present
# - No -F/-B calls (no forced re-split/balance)
# - Resizes focused to match old anchor size

set -euo pipefail

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 1; }; }
need bspc; need jq

# Current desktop/monitor
desk_name="$(bspc query -D -d focused --names)"; [ -n "$desk_name" ] || exit 0
mon_id="$(bspc query -M -m focused)"

# Leaves in current desktop (order = bspwm leaf order)
mapfile -t leaves < <(bspc query -N -d focused -n .leaf)
[ "${#leaves[@]}" -gt 0 ] || exit 0

focused_id="$(bspc query -N -n focused)"
old_anchor_id="${leaves[0]}"

# Save root preselection (if any) to preserve spiral seed
root_json="$(bspc query -T -d focused)"
ps_dir="$(jq -r '.presel.direction // empty' <<<"$root_json")"

# Tile focused if floating (keeps tree sane)
if [ "$(bspc query -T -n "$focused_id" | jq -r '.state // empty')" = "floating" ]; then
  bspc node "$focused_id" -t tiled
fi

# Record old anchor size to copy later
if [ -n "${old_anchor_id:-}" ]; then
  oa_rect="$(bspc query -T -n "$old_anchor_id")"
  oa_w="$(jq -r '.rectangle.width'  <<<"$oa_rect")"
  oa_h="$(jq -r '.rectangle.height' <<<"$oa_rect")"
else
  oa_w=""; oa_h=""
fi

# Create a temp desktop and shuttle all leaves there (preserve our order list)
tmp="__reflow__"
bspc monitor "$mon_id" -a "$tmp"
for id in "${leaves[@]}"; do
  bspc node "$id" -d "$tmp"
done

# Restore the original preselection on the root (if it existed)
# NOTE: do this BEFORE re-adding, so future inserts keep the same spiral start.
if [ -n "$ps_dir" ] && [ "$ps_dir" != "cancel" ]; then
  bspc node @/ -p "$ps_dir" || true
fi

# Bring focused back FIRST => becomes new anchor
bspc node "$focused_id" -d "$desk_name"

# Re-add the rest in recorded order
for id in "${leaves[@]}"; do
  [ "$id" = "$focused_id" ] && continue
  # Keep tiling consistent
  if [ "$(bspc query -T -n "$id" | jq -r '.state // empty')" = "floating" ]; then
    bspc node "$id" -t tiled
  fi
  bspc node "$id" -d "$desk_name"
done

# Remove temp desktop
bspc desktop "$tmp" -r

# Size-match focused to old anchor (inherit the replaced slot’s size)
if [ -n "${oa_w:-}" ] && [ -n "${oa_h:-}" ]; then
  f_rect="$(bspc query -T -n "$focused_id")"
  fw="$(jq -r '.rectangle.width'  <<<"$f_rect")"
  fh="$(jq -r '.rectangle.height' <<<"$f_rect")"

  dw=$(( oa_w - fw ))   # + = grow width, - = shrink
  dh=$(( oa_h - fh ))   # + = grow height, - = shrink

  # Resize from east/south edges so we don't disturb the left/top anchor
  if [ "$dw" -ne 0 ]; then bspc node "$focused_id" -z east  "$dw" 0  || true; fi
  if [ "$dh" -ne 0 ]; then bspc node "$focused_id" -z south 0   "$dh" || true; fi
fi

# Refocus the anchor (quality-of-life)
bspc node -f "$focused_id"
