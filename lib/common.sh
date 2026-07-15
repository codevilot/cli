#!/usr/bin/env bash

if [[ -n "${CODEVILOT_COMMON_SH_LOADED:-}" ]]; then
    return 0
fi
CODEVILOT_COMMON_SH_LOADED=1

CODEVILOT_VERSION="0.1.0"
CODEVILOT_NAME="codevilot"

color_enabled() {
    [[ "${NO_COLOR:-}" == "" ]] || return 1
    [[ -n "${CODEVILOT_TTY_OUTPUT_FILE:-}" ]] && return 1
    [[ -t 1 ]] && return 0
    [[ -w "${CODEVILOT_TTY_PATH:-/dev/tty}" ]]
}

_color() {
    local code="$1"
    if color_enabled; then
        printf '\033[%sm' "$code"
    fi
}

info() {
    printf '%s%s%s\n' "$(_color 34)" "$*" "$(_color 0)"
}

success() {
    printf '%s%s%s\n' "$(_color 32)" "$*" "$(_color 0)"
}

warn() {
    printf '%sWarning:%s %s\n' "$(_color 33)" "$(_color 0)" "$*" >&2
}

error() {
    printf '%sError:%s %s\n' "$(_color 31)" "$(_color 0)" "$*" >&2
}

die() {
    error "$*"
    exit 1
}

trim() {
    local value="$*"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local answer
    local suffix="[y/N]"

    if [[ "$default" == "y" ]]; then
        suffix="[Y/n]"
    fi

    while true; do
        answer="$(read_from_tty "${prompt} ${suffix} ")" || return 1
        answer="$(trim "$answer")"
        if [[ -z "$answer" ]]; then
            answer="$default"
        fi
        case "$answer" in
            y|Y|yes|YES) return 0 ;;
            n|N|no|NO) return 1 ;;
            *) warn "Please answer yes or no." ;;
        esac
    done
}

prompt_required() {
    local prompt="$1"
    local value
    while true; do
        value="$(read_from_tty "${prompt} ")" || return 1
        value="$(trim "$value")"
        if [[ -n "$value" ]]; then
            printf '%s' "$value"
            return 0
        fi
        warn "This value is required."
    done
}

prompt_default() {
    local prompt="$1"
    local default="$2"
    local value
    value="$(read_from_tty "${prompt} [${default}]: ")" || return 1
    value="$(trim "$value")"
    if [[ -z "$value" ]]; then
        value="$default"
    fi
    printf '%s' "$value"
}

have_command() {
    command -v "$1" >/dev/null 2>&1
}

run_cmd() {
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        printf '[dry-run]'
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi
    "$@"
}

ensure_dir() {
    local dir="$1"
    local mode="$2"
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        printf '[dry-run] mkdir -p %q\n' "$dir"
        printf '[dry-run] chmod %q %q\n' "$mode" "$dir"
        return 0
    fi
    mkdir -p "$dir"
    chmod "$mode" "$dir"
}

backup_file() {
    local file="$1"
    local timestamp backup
    timestamp="$(date '+%Y%m%d-%H%M%S')"
    backup="${file}.bak.${timestamp}"
    if [[ -f "$file" ]]; then
        cp "$file" "$backup"
        printf '%s' "$backup"
    fi
}

portable_realpath_dir() {
    local source="$1"
    local dir

    while [[ -L "$source" ]]; do
        dir="$(cd -P "$(dirname "$source")" >/dev/null 2>&1 && pwd)"
        source="$(readlink "$source")"
        [[ "$source" != /* ]] && source="$dir/$source"
    done

    cd -P "$(dirname "$source")" >/dev/null 2>&1 && pwd
}

shell_quote() {
    printf '%q' "$1"
}

read_from_tty() {
    local prompt="$1"
    local value=""
    local tty_path="${CODEVILOT_TTY_PATH:-/dev/tty}"
    local input_file="${CODEVILOT_TTY_INPUT_FILE:-}"
    local output_file="${CODEVILOT_TTY_OUTPUT_FILE:-}"
    local tmp_file

    if [[ -n "$input_file" ]]; then
        [[ -r "$input_file" ]] || return 1
        if [[ -n "$output_file" ]]; then
            printf '%s' "$prompt" >>"$output_file"
        fi
        IFS= read -r value <"$input_file" || return 1
        tmp_file="$(mktemp "${TMPDIR:-/tmp}/codevilot-tty.XXXXXX")"
        tail -n +2 "$input_file" >"$tmp_file"
        mv "$tmp_file" "$input_file"
        printf '%s' "$value"
        return 0
    fi

    if [[ -r "$tty_path" && -w "$tty_path" ]]; then
        printf '%s' "$prompt" >"$tty_path"
        IFS= read -r value <"$tty_path"
    else
        return 1
    fi

    printf '%s' "$value"
}
