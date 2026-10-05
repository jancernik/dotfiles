#!/usr/bin/env bash

# Take screenshots with hyprshot and notify with the saved file

set -euo pipefail

if [[ ${1:-} == /* && -f $1 ]]; then
    path=$1
    action=$(notify-send -a Hyprshot -i "$path" -h "string:image-path:$path" \
        -A default=Open -A folder="Show in folder" \
        "Screenshot saved" "$(basename -- "$path")") || exit 0
    case $action in
    default) xdg-open "$path" ;;
    folder) xdg-open "$(dirname -- "$path")" ;;
    esac
    exit 0
fi

if pgrep -x slurp >/dev/null; then
    pkill -x slurp
    exit 0
fi

mode=${1:-region}
dir=${HYPRSHOT_DIR:-$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME")}
name="Screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"
exec hyprshot --freeze --silent -m "$mode" -o "$dir" -f "$name" -- "$(realpath -- "$0")"
