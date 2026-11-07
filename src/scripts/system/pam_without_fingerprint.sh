#!/usr/bin/env bash

SRC_DIR="${1:-/etc/pam.d}"
DEST_DIR="$2"
SERVICE="${3:-meander}"

[ -n "$DEST_DIR" ] || exit 1
[ -d "$SRC_DIR" ] || exit 1

base="$SRC_DIR/$SERVICE"
# Same order as the lock screen's own choice: Meander's, then Omarchy's lock
# password service, then login.
[ -e "$base" ] || base="$SRC_DIR/omarchy-lock-password"
[ -e "$base" ] || base="$SRC_DIR/login"
[ -r "$base" ] || exit 1

rm -rf "$DEST_DIR"
mkdir -p "$DEST_DIR" || exit 1

for file in "$SRC_DIR"/*; do
    [ -f "$file" ] || continue
    name="$(basename "$file")"
    if grep -qs "pam_fprintd" "$file"; then
        grep -v "pam_fprintd" "$file" > "$DEST_DIR/$name"
    else
        ln -sf "$(readlink -f "$file")" "$DEST_DIR/$name"
    fi
done

if grep -qs "pam_fprintd" "$base"; then
    grep -v "pam_fprintd" "$base" > "$DEST_DIR/meander-nofp"
else
    cp -L "$base" "$DEST_DIR/meander-nofp"
fi
