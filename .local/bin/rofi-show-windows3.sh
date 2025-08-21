#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C.UTF-8

cache_dir="/tmp/bspwm-icons"
mkdir -p "$cache_dir"

# ---- helpers ---------------------------------------------------------------

get_label() {
  local nid="$1" raw class utf8 title label
  raw="$(xprop -notype -id "$nid" WM_CLASS 2>/dev/null || true)"
  class="$(awk -F\" 'NF>=4{print $(NF-1)}' <<<"$raw")"
  [[ -n "$class" && "$class" == *.* ]] && class="${class##*.}"
  if [[ -n "${class:-}" ]]; then
    label="$(awk 'BEGIN{ORS=""}{print toupper(substr($0,1,1)) tolower(substr($0,2))}' <<<"$class")"
  fi
  if [[ -z "${label:-}" ]]; then
    utf8="$(xprop -notype -id "$nid" _NET_WM_NAME 2>/dev/null | awk -F\" 'NF>=2{print $2}')"
    title="$(xprop -notype -id "$nid" WM_NAME      2>/dev/null | awk -F\" 'NF>=2{print $2}')"
    label="${utf8:-$title}"
  fi
  label="$(printf '%s' "${label:-}" | tr -d '\000\r' | tr '\n\t' '  ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  [[ -n "$label" ]] || label="(unnamed)"
  printf '%s' "$label"
}

# Convert largest _NET_WM_ICON frame to PNG using your PAM->PNG pipeline.
# Returns 0 on success, non-zero on any failure (missing/empty/corrupt).
icon_from_netwm_pam() {
  local nid="$1" out_png="$2"
  local pam_tmp
  pam_tmp="$(mktemp "$cache_dir/icon.XXXXXX.pam")"
  # Produce PAM; on any failure, clean up and return non-zero
  if xprop -id "$nid" -notype 32c _NET_WM_ICON 2>/dev/null | \
     perl -0777 -ne '
       my @v = /(\d+)/g; exit 2 unless @v >= 3;
       my ($i,$best_i,$best_w,$best_h,$best_area)=(0,undef,0,0,-1);
       while ($i+1 < @v) {
         my ($w,$h)=@v[$i,$i+1]; last if $w==0 || $h==0;
         my $cnt=$w*$h; last if $i+2+$cnt > @v;
         if ($cnt > $best_area){($best_i,$best_w,$best_h,$best_area)=($i+2,$w,$h,$cnt);}
         $i += 2 + $cnt;
       }
       exit 2 unless defined $best_i;
       print "P7\nWIDTH $best_w\nHEIGHT $best_h\nDEPTH 4\nMAXVAL 255\nTUPLTYPE RGB_ALPHA\nENDHDR\n";
       my $bytes = pack("N*", @v[$best_i .. $best_i+$best_area-1]);
       $bytes =~ s/(.)(...)/$2$1/gs;  # ARGB -> RGBA
       print $bytes;
     ' >"$pam_tmp" 2>/dev/null
  then
    if [[ -s "$pam_tmp" ]]; then
      if pamrgbatopng "$pam_tmp" >"$out_png" 2>/dev/null && [[ -s "$out_png" ]]; then
        rm -f "$pam_tmp"
        return 0
      fi
    fi
  fi
  rm -f "$pam_tmp"
  return 1
}

guess_theme_icon_name() {
  local label="$1" lc
  lc="$(tr '[:upper:] ' '[:lower:]-' <<<"$label" | tr -cd '[:alnum:]-._')"
  case "$lc" in
    google-chrome-*) lc="google-chrome" ;;
    code-oss|vscodium|visual-studio-code) lc="code" ;;
  esac
  [[ -n "$lc" ]] || lc="application-x-executable"
  printf '%s' "$lc"
}

# ---- collect windows -------------------------------------------------------

mapfile -t NIDS < <(bspc query -N -n .hidden)
(( ${#NIDS[@]} )) || exit 0

# ---- build rofi menu (NUL-separated) --------------------------------------

menu_blob=""
for nid in "${NIDS[@]}"; do
  label="$(get_label "$nid")"

  # Prefer per-window PNG (cached), else theme icon name
  png="$cache_dir/$nid.png"
  if [[ ! -s "$png" ]]; then
    icon_from_netwm_pam "$nid" "$png" || true
  fi

  if [[ -s "$png" ]]; then
    iconmeta="$png"
  else
    full_class="$(xprop -notype -id "$nid" WM_CLASS 2>/dev/null | awk -F\" 'NF>=4{print $(NF-1)}')"
    short="${full_class##*.}"; short="${short,,}"
    iconmeta="${full_class:-$(guess_theme_icon_name "$label")}"
    [[ -n "$full_class" ]] && iconmeta="$full_class"
  fi

  # One row: text + icon metadata (path or theme name). NUL-separated.
  menu_blob+="${label}\x00icon\x1f${iconmeta}\x00"
done

# ---- rofi selection by index ----------------------------------------------

idx="$(
  printf "%b" "$menu_blob" | rofi -dmenu \
    -p hidden \
    -show-icons \
    -format i \
    -sep $'\0' \
    -no-custom
)"
[[ -n "${idx:-}" ]] || exit 0

bspc node "${NIDS[$idx]}" -g hidden=off -f
