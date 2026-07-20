#!/usr/bin/env bash

if [[ -n "${CODEVILOT_PLATFORM_SH_LOADED:-}" ]]; then
    return 0
fi
CODEVILOT_PLATFORM_SH_LOADED=1

platform_os() {
    uname -s 2>/dev/null || printf 'unknown'
}

is_macos() {
    [[ "$(platform_os)" == "Darwin" ]]
}

is_linux() {
    [[ "$(platform_os)" == "Linux" ]]
}

home_path_to_tilde() {
    local path="$1"
    # shellcheck disable=SC2088
    case "$path" in
        "$HOME") printf '~' ;;
        "$HOME"/*) printf '~/%s' "${path#"$HOME"/}" ;;
        *) printf '%s' "$path" ;;
    esac
}

expand_tilde_path() {
    local path="$1"
    # shellcheck disable=SC2088
    case "$path" in
        "~") printf '%s' "$HOME" ;;
        "~/"*) printf '%s/%s' "$HOME" "${path#"~/"}" ;;
        *) printf '%s' "$path" ;;
    esac
}

absolute_path() {
    local path="$1"
    path="$(expand_tilde_path "$path")"
    case "$path" in
        /*) printf '%s' "$path" ;;
        *) printf '%s/%s' "$PWD" "$path" ;;
    esac
}

clipboard_command() {
    [[ "${CODEVILOT_DISABLE_CLIPBOARD:-}" == "1" ]] && return 0

    if is_macos && command -v pbcopy >/dev/null 2>&1; then
        printf 'pbcopy'
    elif command -v wl-copy >/dev/null 2>&1; then
        printf 'wl-copy'
    elif command -v xclip >/dev/null 2>&1; then
        printf 'xclip -selection clipboard'
    elif command -v xsel >/dev/null 2>&1; then
        printf 'xsel --clipboard --input'
    fi
}

browser_open_command() {
    [[ "${CODEVILOT_DISABLE_BROWSER_OPEN:-}" == "1" ]] && return 0

    if is_macos && command -v open >/dev/null 2>&1; then
        printf 'open'
    elif command -v wslview >/dev/null 2>&1; then
        printf 'wslview'
    elif command -v xdg-open >/dev/null 2>&1; then
        printf 'xdg-open'
    fi
}

open_url() {
    local url="$1"
    local opener
    opener="$(browser_open_command)"
    [[ -n "$opener" ]] || return 1
    "$opener" "$url" >/dev/null 2>&1
}
