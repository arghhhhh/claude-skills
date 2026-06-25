# gitbash-clipboard-cd: cd into folder paths copied from Windows Explorer.
# Solves two Git Bash pain points: backslash paths (C:\Users\... gets its
# backslashes eaten by bash) and pasted paths that aren't auto-quoted.

# cdc: cd to the folder path currently on the Windows clipboard.
# Copy a folder (or "Copy as path") in Explorer, then type: cdc
cdc() {
    local p
    p="$(cat /dev/clipboard)"            # read Windows clipboard
    p="${p//$'\r'/}"; p="${p//$'\n'/}"   # strip CR/LF
    p="${p%\"}"; p="${p#\"}"             # strip surrounding quotes
    cd "$(printf '%s' "$p" | tr '\134' '/')"  # backslashes -> forward slashes
}

# cdh: like cdc, but scans Windows clipboard HISTORY (Win+V) and cd's into the
# most recently copied entry that is an existing directory -- handy if you copied
# something else after the path. Requires clipboard history enabled.
cdh() {
    local p
    p="$(powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME/.cdh-cliphist.ps1" 2>/dev/null)"
    p="${p//$'\r'/}"; p="${p//$'\n'/}"
    if [ -z "$p" ]; then
        echo "cdh: no directory path found in clipboard history" >&2
        return 1
    fi
    cd "$(printf '%s' "$p" | tr '\134' '/')"
}
