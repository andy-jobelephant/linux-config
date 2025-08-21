#!/bin/sh
# ~/.local/bin/rofi-hidden-windows.sh

windows="$(bspc query -N -n .hidden | while read -r nid; do
    name=$(xprop -id "$nid" WM_CLASS | awk -F\" '{print $2}')
    title=$(xprop -id "$nid" WM_NAME | awk -F\" '{print $2}')
    echo "$nid $name - $title"
done)"

[ -z "$windows" ] && exit


choice=$(printf "%s\n" "$windows" | rofi -dmenu -p "hidden")

nid=$(echo "$choice" | awk '{print $1}')
[ -n "$nid" ] && bspc node "$nid" -g hidden=off -f
