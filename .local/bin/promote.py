#!/usr/bin/env python3
"""
Make focused window the anchor (first at root) while preserving the spiral's original start.
- Preserves automatic_scheme/initial_polarity
- Preserves root preselection (direction) if present
- No -F/-B calls (no forced re-split/balance)
- Resizes focused to match old anchor size
"""

import json
import shutil
import subprocess
import sys


def run_cmd(cmd, capture_output=True, check=True):
    """Run a command and return the result."""
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=capture_output, text=True, check=check
        )
        return result.stdout.strip() if capture_output else None
    except subprocess.CalledProcessError as e:
        if check:
            raise
        return None


def need(command):
    """Check if a command exists, exit if not."""
    if not shutil.which(command):
        print(f"Missing: {command}", file=sys.stderr)
        sys.exit(1)


def main():
    # Check dependencies
    need("bspc")
    need("jq")

    # Current desktop/monitor
    desk_name = run_cmd("bspc query -D -d focused --names")
    if not desk_name:
        sys.exit(0)

    mon_id = run_cmd("bspc query -M -m focused")

    # Leaves in current desktop (order = bspwm leaf order)
    leaves_output = run_cmd("bspc query -N -d focused -n .leaf")
    if not leaves_output:
        sys.exit(0)

    leaves = leaves_output.split("\n") if leaves_output else []
    if len(leaves) == 0:
        sys.exit(0)

    focused_id = run_cmd("bspc query -N -n focused")
    old_anchor_id = leaves[0]

    # Save root preselection (if any) to preserve spiral seed
    root_json = run_cmd("bspc query -T -d focused")
    try:
        root_data = json.loads(root_json)
        ps_dir = root_data.get("presel", {}).get("direction", "")
    except (json.JSONDecodeError, KeyError):
        ps_dir = ""

    # Tile focused if floating (keeps tree sane)
    focused_state = run_cmd(f"bspc query -T -n {focused_id}")
    try:
        focused_data = json.loads(focused_state)
        if focused_data.get("state") == "floating":
            run_cmd(f"bspc node {focused_id} -t tiled")
    except (json.JSONDecodeError, KeyError):
        pass

    # Record old anchor size to copy later
    oa_w = oa_h = None
    if old_anchor_id:
        try:
            oa_rect = run_cmd(f"bspc query -T -n {old_anchor_id}")
            oa_data = json.loads(oa_rect)
            oa_w = oa_data.get("rectangle", {}).get("width")
            oa_h = oa_data.get("rectangle", {}).get("height")
        except (json.JSONDecodeError, KeyError):
            oa_w = oa_h = None

    # Create a temp desktop and shuttle all leaves there (preserve our order list)
    tmp = "__reflow__"
    run_cmd(f"bspc monitor {mon_id} -a {tmp}")

    for node_id in leaves:
        run_cmd(f"bspc node {node_id} -d {tmp}")

    # Restore the original preselection on the root (if it existed)
    # NOTE: do this BEFORE re-adding, so future inserts keep the same spiral start.
    if ps_dir and ps_dir != "cancel":
        run_cmd(f"bspc node @/ -p {ps_dir}", check=False)

    # Bring focused back FIRST => becomes new anchor
    run_cmd(f"bspc node {focused_id} -d {desk_name}")

    # Re-add the rest in recorded order
    for node_id in leaves:
        if node_id == focused_id:
            continue

        # Keep tiling consistent
        try:
            node_state = run_cmd(f"bspc query -T -n {node_id}")
            node_data = json.loads(node_state)
            if node_data.get("state") == "floating":
                run_cmd(f"bspc node {node_id} -t tiled")
        except (json.JSONDecodeError, KeyError):
            pass

        run_cmd(f"bspc node {node_id} -d {desk_name}")

    # Remove temp desktop
    run_cmd(f"bspc desktop {tmp} -r")

    # Size-match focused to old anchor (inherit the replaced slot's size)
    if oa_w is not None and oa_h is not None:
        try:
            f_rect = run_cmd(f"bspc query -T -n {focused_id}")
            f_data = json.loads(f_rect)
            fw = f_data.get("rectangle", {}).get("width", 0)
            fh = f_data.get("rectangle", {}).get("height", 0)

            dw = oa_w - fw  # + = grow width, - = shrink
            dh = oa_h - fh  # + = grow height, - = shrink

            # Resize from east/south edges so we don't disturb the left/top anchor
            if dw != 0:
                run_cmd(f"bspc node {focused_id} -z east {dw} 0", check=False)
            if dh != 0:
                run_cmd(f"bspc node {focused_id} -z south 0 {dh}", check=False)
        except (json.JSONDecodeError, KeyError):
            pass

    # Refocus the anchor (quality-of-life)
    run_cmd(f"bspc node -f {focused_id}")


if __name__ == "__main__":
    main()
