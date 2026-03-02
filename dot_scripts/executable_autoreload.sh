#!/usr/bin/env bash

# Reloads the Hyprland config without losing current workspaces or focus.

if [[ "$1" != "--watch" ]]; then
    active_address="$(hyprctl activewindow -j | jq -r '.address')"
    current_workspaces="$(hyprctl monitors -j | jq -r '.[] | .activeWorkspace.id')"

    printf 'Reloading config...\n'
    hyprctl keyword animations:enabled false -q
    hyprctl reload -q

    printf 'Restoring workspaces and focus...\n'
    for id in $current_workspaces; do
        hyprctl dispatch workspace "$id" >/dev/null 2>&1
    done
    hyprctl dispatch focuswindow "address:$active_address" -q

    hyprctl keyword animations:enabled true -q
    printf 'Done.\n'
    exit 0
fi

printf 'Watching %s/hypr for changes...\n' "$HOME/.config"
find "$HOME/.config/hypr" -type f | entr -r -n "$0"
