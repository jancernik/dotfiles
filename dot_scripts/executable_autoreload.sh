#!/usr/bin/env bash

if [[ "$1" == "--watch" ]]; then
    active_address="$(hyprctl activewindow -j | jq -r '.address')"
    current_workspaces=$(hyprctl monitors -j | jq -r '.[] | .activeWorkspace.id')

    hyprctl keyword animations:enabled false
    hyprctl reload

    for id in $current_workspaces; do
      hyprctl dispatch workspace "$id"
    done

    hyprctl dispatch focuswindow "address:$active_address"
    hyprctl keyword animations:enabled true
    exit 0
fi

find "$HOME/.config/hypr" -type f | entr -r -n "$0" --watch