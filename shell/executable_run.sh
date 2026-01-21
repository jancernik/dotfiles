#!/bin/bash

DIR="$(dirname "$(realpath "$0")")"

cd "$DIR" && pnpm install

if [[ "$1" == "--dev" ]]; then
	trap 'pkill -f "gjs.*$DIR"; exit' INT TERM
	find "$DIR/src" -name "*.tsx" -o -name "*.ts" -o -name "*.scss" | entr -r ags run "$DIR/src" --gtk 4
else
	ags run "$DIR/src" --gtk 4
fi
