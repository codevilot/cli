#!/usr/bin/env bash

if [[ -n "${CODEVILOT_UI_SH_LOADED:-}" ]]; then
    return 0
fi
CODEVILOT_UI_SH_LOADED=1

# shellcheck source=lib/common.sh
# shellcheck disable=SC2154
. "$SCRIPT_DIR/lib/common.sh"

ui_cyan() {
    printf '%s%s%s' "$(_color 36)" "$*" "$(_color 0)"
}

ui_green() {
    printf '%s%s%s' "$(_color 32)" "$*" "$(_color 0)"
}

ui_yellow() {
    printf '%s%s%s' "$(_color 33)" "$*" "$(_color 0)"
}

ui_bold() {
    printf '%s%s%s' "$(_color 1)" "$*" "$(_color 0)"
}

ui_step() {
    local index="$1"
    local total="$2"
    local title="$3"
    printf '%s %s\n' "$(ui_cyan "[${index}/${total}]")" "$(ui_bold "$title")"
}

ui_status() {
    local label="$1"
    local message="$2"
    printf '      %s %s\n' "$(ui_green "$label:")" "$message"
}

ui_note() {
    local message="$1"
    printf '      %s %s\n' "$(ui_yellow "Note:")" "$message"
}

ui_kv() {
    local label="$1"
    local value="$2"
    printf '%s\n  %s\n\n' "$(ui_bold "$label:")" "$value"
}

ui_command() {
    local command_line="$1"
    printf '  %s\n' "$command_line"
}
