#!/usr/bin/env bash
# Move/swap inside the current monitor; if we're already at that edge, wrap to the adjacent monitor.
# Usage: bspwm-push-or-wrap.sh west|east|north|south
set -euo pipefail

dir="${1:-}"
case "$dir" in west|east|north|south) ;; *) exit 1 ;; esac

# Auto-tile floating windows so geometry is sane
state="$(bspc query -T -n focused | jq -r '.state // empty')"
[ "$state" = "floating" ] && bspc node -t tiled

node_json="$(bspc query -T -n focused)"
mon_json="$(bspc query -T -m focused)"

# Node rect
nx=$(jq -r '.rectangle.x'      <<<"$node_json")
ny=$(jq -r '.rectangle.y'      <<<"$node_json")
nw=$(jq -r '.rectangle.width'  <<<"$node_json")
nh=$(jq -r '.rectangle.height' <<<"$node_json")
mx=$(jq -r '.rectangle.x'      <<<"$mon_json")
my=$(jq -r '.rectangle.y'      <<<"$mon_json")
mw=$(jq -r '.rectangle.width'  <<<"$mon_json")
mh=$(jq -r '.rectangle.height' <<<"$mon_json")

# Tolerance for rounding/layout jitter
eps=2

# Compute booleans
left_edge=0; right_edge=0; top_edge=0; bottom_edge=0
if (( nx <= mx + eps ));                    then left_edge=1;   fi
if (( nx + nw >= mx + mw - eps ));          then right_edge=1;  fi
if (( ny <= my + eps ));                    then top_edge=1;    fi
if (( ny + nh >= my + mh - eps ));          then bottom_edge=1; fi


# dbg "dir=$dir nx=$nx ny=$ny nw=$nw nh=$nh | mx=$mx my=$my mw=$mw mh=$mh | L=$left_edge R=$right_edge T=$top_edge B=$bottom_edge"


at_edge=0
case "$dir" in
  west)  at_edge=$left_edge ;;
  east)  at_edge=$right_edge ;;
  north) at_edge=$top_edge ;;
  south) at_edge=$bottom_edge ;;
esac

if (( at_edge == 1 )); then
  # Wrap to adjacent monitor in that direction (no swapping), then STOP.
  if target="$(bspc query -M -m "$dir" 2>/dev/null)"; then
    [ -n "$target" ] && {
      bspc node -m "$dir"
      bspc node -f focused
      exit 0
    }
  fi
fi

# Not at edge (or no monitor there): swap within this monitor
bspc node -n "$dir" || true
