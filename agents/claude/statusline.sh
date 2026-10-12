#!/usr/bin/env bash
input=$(cat)
model=$(jq -r '.model.display_name' <<<"$input")
used=$(jq -r '.context_window.used_percentage // empty' <<<"$input")

# Solarized dark as 24-bit color, so the result does not depend on how the terminal maps its 16 ANSI colors.
reset=$'\e[0m'
base01=$'\e[38;2;88;110;117m'
base0=$'\e[38;2;131;148;150m'
green=$'\e[38;2;133;153;0m'
yellow=$'\e[38;2;181;137;0m'
orange=$'\e[38;2;203;75;22m'
red=$'\e[38;2;220;50;47m'
light_orange=$'\e[38;2;255;175;95m'
# Green, yellow, orange, light orange and red are left out so a model never shares a color with the context or disk segment.
model_palette=(
  $'\e[38;2;38;139;210m'
  $'\e[38;2;42;161;152m'
  $'\e[38;2;108;113;196m'
  $'\e[38;2;211;54;130m'
)
bar_width=10

model_color() {
  local hash
  hash=$(printf '%s' "$1" | cksum | cut -d' ' -f1)
  printf '%s' "${model_palette[hash % ${#model_palette[@]}]}"
}

context_color() {
  if (($1 >= 50)); then
    printf '%s' "$red"
  elif (($1 >= 30)); then
    printf '%s' "$orange"
  elif (($1 >= 20)); then
    printf '%s' "$yellow"
  else
    printf '%s' "$green"
  fi
}

# df -h uses base 1024 on both macOS and GNU, so G means GiB whether or not the unit carries an i.
# Prints nothing when the free space is large enough that the segment is noise.
disk_segment_color() {
  local num unit int frac
  num=${1%%[!0-9.,]*}
  unit=${1:${#num}:1}
  int=${num%%[.,]*}
  frac=${num:${#int}+1}
  int=$((10#${int:-0}))
  case $unit in
    T | P | E) ;;
    G)
      if gib_above "$int" "$frac" 100; then
        return
      elif gib_above "$int" "$frac" 50; then
        printf '%s' "$light_orange"
      else
        printf '%s' "$red"
      fi
      ;;
    *) printf '%s' "$red" ;;
  esac
}

# A nonzero fraction puts 100.5G above 100.
gib_above() {
  local int=$1 frac=$2 limit=$3
  ((int > limit)) || { ((int == limit)) && [[ $frac == *[1-9]* ]]; }
}

context_bar() {
  local pct=$1 color=$2 filled used_cells="" free_cells="" i
  filled=$(((pct * bar_width + 50) / 100))
  for ((i = 0; i < bar_width; i++)); do
    if ((i < filled)); then used_cells+="█"; else free_cells+="░"; fi
  done
  printf '%s%s%s%s' "$color" "$used_cells" "$base01" "$free_cells"
}

pct=${used%.*}
pct=${pct:-0}
((pct < 0)) && pct=0
((pct > 100)) && pct=100
color=$(context_color "$pct")

# Repo-relative rather than PATH: Claude Code and the tests start the status line with a PATH that has no scripts/.
disk=$("${BASH_SOURCE[0]%/*}/../../scripts/disk_free" 2>/dev/null)

printf '%s%s%s %s|%s CTX %s %s%d%%%s' \
  "$(model_color "$model")" "$model" "$reset" \
  "$base01" "$base0" \
  "$(context_bar "$pct" "$color")" \
  "$color" "$pct" "$reset"

disk_color=$([[ -n $disk ]] && disk_segment_color "$disk")
if [[ -n $disk_color ]]; then
  printf ' %s|%s %s⛁ %s%s' "$base01" "$reset" "$disk_color" "$disk" "$reset"
fi
