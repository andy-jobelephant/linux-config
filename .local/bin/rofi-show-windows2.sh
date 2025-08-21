#!/usr/bin/env bash
set -euo pipefail

cache_dir="/tmp/bspwm-icons"
mkdir -p "$cache_dir"

# Collect hidden windows
mapfile -t NIDS < <(bspc query -N -n .window.hidden)
(( ${#NIDS[@]} )) || exit 0

# Find desktop file by matching WM_CLASS to StartupWMClass
find_desktop_file() {
    local wm_class="$1"
    local nid="$2"

    [[ -n "$wm_class" ]] || return 1
    local wm_class_lower=$(tr '[:upper:]' '[:lower:]' <<<"$wm_class")

    # Search in both system and user desktop file directories
    for dir in ~/.local/share/applications /usr/share/applications; do
        local pwa_id=$(get_pwa_app_id "$nid" 2>/dev/null || true)
        if [[ -n "$pwa_id" ]]; then
            local desktop_file=$(grep -Rl -- "--app-id=$pwa_id" "$dir"/*.desktop | head -1)
            if [[ -n "$desktop_file" ]]; then
                echo "$desktop_file"
                return
            fi
        fi

        # Try exact match first (case-sensitive)
        local desktop_file=$(grep -l "^StartupWMClass=$wm_class$" "$dir"/*.desktop 2>/dev/null | head -1)
        if [[ -n "$desktop_file" ]]; then
            echo "$desktop_file"
            return
        fi

        # Try case-insensitive match
        desktop_file=$(grep -il "^StartupWMClass=$wm_class_lower$" "$dir"/*.desktop 2>/dev/null | head -1)
        if [[ -n "$desktop_file" ]]; then
            echo "$desktop_file"
            return
        fi

        # Try partial match (contains the class name)
        desktop_file=$(grep -il "StartupWMClass=.*$wm_class_lower" "$dir"/*.desktop 2>/dev/null | head -1)
        if [[ -n "$desktop_file" ]]; then
            echo "$desktop_file"
            return
        fi

        # Try matching by desktop file name (new approach)
        if [[ -f "$dir/$wm_class.desktop" ]]; then
            echo "$dir/$wm_class.desktop"
            return
        fi

        # Try case-insensitive filename match
        if [[ -f "$dir/$wm_class_lower.desktop" ]]; then
            echo "$dir/$wm_class_lower.desktop"
            return
        fi
    done
}

get_pwa_app_id() {
    local nid="$1"

    local class_app_id=$(xprop -id "$nid" WM_CLASS  | awk -F'"' '{print $(NF-3)}')
    if [[ -n "$class_app_id" ]] && [[ "${class_app_id:0:4}" == "crx_" ]]; then
        echo "${class_app_id:4}" | sed 's/^_*//'
        return
    fi

    local pid=$(get_window_pid "$nid" 2>/dev/null || true)
    [[ -n "$pid" ]] || return 1;

    if [[ ! -r "/proc/$pid/cmdline" ]]; then
        return 1
    fi

    local cmdline=$(tr '\0' ' ' </proc/$pid/cmdline 2>/dev/null || true)

    local app_id=$(echo "$cmdline" | sed -n 's/.*--app-id=\([^ ]*\).*/\1/p')

    [[ -n "$app_id" ]] || return 1
    echo "$app_id"
    return
}

# Extract icon from desktop file
get_icon_from_desktop() {
    local desktop_file="$1"
    [[ -f "$desktop_file" ]] || return 1
    local icon=$(grep "^Icon=" "$desktop_file" 2>/dev/null | cut -d= -f2- | head -1)
    [[ -n "$icon" ]] && echo "$icon"
}

get_window_pid() {
    local nid="$1"
    local xprop_output=$(xprop -id "$nid" _NET_WM_PID 2>/dev/null || true)
    local pid=$(echo "$xprop_output" | awk '{print $3}')
    [[ -n "$pid" ]] && [[ "$pid" =~ ^[0-9]+$ ]] && echo "$pid"
}

# Find executable path from PID
get_exe_path() {
    local pid="$1"
    [[ -n "$pid" ]] && [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    readlink "/proc/$pid/exe" 2>/dev/null
}

# Find desktop file by executable path
find_desktop_by_exec() {
    local exe_path="$1"
    [[ -n "$exe_path" ]] || return 1

    local exe_name=$(basename "$exe_path")

    for dir in /usr/share/applications ~/.local/share/applications; do
        # Try exact executable path match
        local desktop_file=$(grep -l "^Exec=.*$exe_path" "$dir"/*.desktop 2>/dev/null | head -1)
        [[ -n "$desktop_file" ]] && echo "$desktop_file" && return

        # Try executable name match
        desktop_file=$(grep -l "^Exec=.*$exe_name" "$dir"/*.desktop 2>/dev/null | head -1)
        [[ -n "$desktop_file" ]] && echo "$desktop_file" && return
    done
}

# Enhanced icon name guessing with better heuristics
guess_icon_name() {
    local class="$1"

    # Handle empty or problematic class names
    if [[ -z "$class" ]] || [[ "$class" == "(unknown)" ]]; then
        echo "application-x-executable"
        return
    fi

    local class_lower=$(tr '[:upper:] ' '[:lower:]-' <<<"$class" | tr -cd '[:alnum:]-._')

    # Final safety check
    if [[ -z "$class_lower" ]]; then
        echo "application-x-executable"
        return
    fi

    # Common application mappings
    case "$class_lower" in
        *firefox*) echo "firefox" ;;
        *chrome*|*chromium*) echo "google-chrome" ;;
        *code*|*vscode*) echo "visual-studio-code" ;;
        *terminal*|*konsole*|*gnome-terminal*|*alacritty*|*kitty*) echo "terminal" ;;
        *file*|*nautilus*|*dolphin*|*thunar*) echo "folder" ;;
        *text*|*editor*|*vim*|*emacs*) echo "text-editor" ;;
        *calc*) echo "calculator" ;;
        *mail*|*thunderbird*) echo "mail-client" ;;
        *music*|*audio*) echo "audio-player" ;;
        *video*|*vlc*|*mpv*) echo "video-player" ;;
        *image*|*gimp*|*photo*) echo "image-viewer" ;;
        *) echo "$class_lower" ;;
    esac
}

# Check if a theme icon exists
icon_exists_in_theme() {
    local icon_name="$1"
    # Skip if it's a full path (those should work)
    [[ "$icon_name" == /* ]] && return 0

    # Check hicolor theme with different sizes
    for dir in ~/.local/share /usr/share; do
        for size in 16x16 22x22 24x24 32x32 48x48 64x64 128x128 256x256 scalable; do
            local theme_dir="$dir/icons/hicolor/$size/apps"
            if [[ -d "$theme_dir" ]]; then
                for ext in png svg xpm; do
                    if [[ -f "$theme_dir/$icon_name.$ext" ]]; then
                        return 0
                    fi
                done
            fi
        done
    done

    # Also check other common theme directories as fallback
    for theme_dir in /usr/share/icons/*/apps /usr/share/icons/*/places /usr/share/icons/*/categories /usr/share/pixmaps; do
        [[ -d "$theme_dir" ]] || continue
        for ext in png svg xpm; do
            if [[ -f "$theme_dir/$icon_name.$ext" ]]; then
                return 0
            fi
        done
    done
    return 1
}

# Multi-layer icon detection
find_window_icon() {
    local nid="$1"
    local class="$2"

    # 1. Try desktop file matching by WM_CLASS
    local desktop_file=$(find_desktop_file "$class" "$nid")
    if [[ -n "$desktop_file" ]]; then
        local desktop_icon=$(get_icon_from_desktop "$desktop_file")
        if [[ -n "$desktop_icon" ]]; then
            # Validate the icon exists before using it
            if icon_exists_in_theme "$desktop_icon"; then
                echo "$desktop_icon"
                return
            fi
        fi
    fi

    # 2. Try process-based detection
    local pid=$(get_window_pid "$nid" 2>/dev/null || true)
    if [[ -n "$pid" ]]; then
        local exe_path=$(get_exe_path "$pid" 2>/dev/null || true)
        if [[ -n "$exe_path" ]]; then
            desktop_file=$(find_desktop_by_exec "$exe_path" 2>/dev/null || true)
            if [[ -n "$desktop_file" ]]; then
                local desktop_icon=$(get_icon_from_desktop "$desktop_file" 2>/dev/null || true)
                if [[ -n "$desktop_icon" ]] && icon_exists_in_theme "$desktop_icon"; then
                    echo "$desktop_icon"
                    return
                fi
            fi
        fi
    fi

    # 3. Enhanced theme icon guessing (guaranteed fallback)
    local guessed_icon=$(guess_icon_name "$class")
    if icon_exists_in_theme "$guessed_icon"; then
        echo "$guessed_icon"
    else
        echo "application-x-executable"
    fi
}

# Build menu with icons
menu_items=()
icon_items=()
window_count=0

for nid in "${NIDS[@]}"; do
  # App display name: WM_CLASS "Class" (last quoted), fallback to title
  class=$(xprop -id "$nid" WM_CLASS 2>/dev/null | awk -F\" 'NF>=4{print $(NF-1)}' || true)
  [[ -n "$class" ]] || class=$(xprop -id "$nid" WM_NAME 2>/dev/null | awk -F\" 'NF>=2{print $2}' || true)
  [[ -n "$class" ]] || class="(unknown)"

  # Get window title for uniqueness
  title=$(xprop -id "$nid" WM_NAME 2>/dev/null | awk -F\" 'NF>=2{print $2}' || true)
  [[ -n "$title" ]] || title="(no title)"

  # Create unique display name with window index
  window_count=$((window_count + 1))
  if [[ "$title" != "$class" ]] && [[ "$title" != "(no title)" ]]; then
    display_name="$class - $title"
  else
    display_name="$class"
  fi

  # Enhanced icon detection
  icon_meta=$(find_window_icon "$nid" "$class" 2>/dev/null || echo "application-x-executable")

  # Final safety check
  [[ -n "$icon_meta" ]] || icon_meta="application-x-executable"

  # Store both text and icon info
  menu_items+=("$display_name")
  icon_items+=("$icon_meta")
done

# Create a temporary file with the menu data in the format rofi expects
temp_menu=$(mktemp)
trap 'rm -f "$temp_menu"' EXIT

# Build the menu entries with icons
for i in "${!menu_items[@]}"; do
    echo -e "${menu_items[$i]}\0icon\x1f${icon_items[$i]}" >> "$temp_menu"
done

# Call rofi with icon support
idx="$(cat "$temp_menu" | rofi -dmenu -p "hidden" -format 'i' -show-icons)"

if [[ -n "${idx:-}" ]]; then
  bspc node "${NIDS[$idx]}" -g hidden=off -f
  exit 0
fi

exit 0
