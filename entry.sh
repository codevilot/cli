#!/usr/bin/env bash
set -u

CODEVILOT_REF="${CODEVILOT_REF:-main}"
CODEVILOT_RAW_BASE_URL="${CODEVILOT_RAW_BASE_URL:-https://raw.githubusercontent.com/codevilot/cli/${CODEVILOT_REF}}"
CODEVILOT_DEBUG="${CODEVILOT_DEBUG:-}"
CODEVILOT_LOCAL_MODE="${CODEVILOT_LOCAL_MODE:-0}"
TEMP_DIR=""

REQUIRED_FILES=(
    "lib/common.sh"
    "lib/platform.sh"
    "lib/ui.sh"
    "commands/github-ssh.sh"
    "commands/git-author.sh"
    "commands/github-ssh-test.sh"
    "commands/git-origin.sh"
    "commands/wifi-survey.sh"
)

debug() {
    if [[ -n "$CODEVILOT_DEBUG" ]]; then
        printf 'DEBUG: %s\n' "$*" >&2
    fi
}

print_error() {
    printf 'ERROR: %s\n' "$*" >&2
}

codevilot_lang() {
    local requested="${lang:-${CODEVILOT_LANG:-}}"
    case "$requested" in
        ko|en)
            printf '%s' "$requested"
            return 0
            ;;
    esac

    case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in
        ko_KR*|ko-KR*|ko.*|ko)
            printf 'ko'
            ;;
        *)
            printf 'en'
            ;;
    esac
}

msg() {
    local key="$1"
    if [[ "$(codevilot_lang)" == "ko" ]]; then
        case "$key" in
            select_category) printf '카테고리를 선택하세요:' ;;
            select_command) printf '명령을 선택하세요:' ;;
            enter_selection) printf '번호 입력: ' ;;
            github) printf 'GitHub' ;;
            network) printf '네트워크' ;;
            info) printf '정보' ;;
            install_local) printf '로컬 명령 설치' ;;
            github_ssh_setup) printf 'GitHub SSH 설정' ;;
            github_ssh_verify) printf 'GitHub SSH 인증 확인' ;;
            git_author) printf '커밋 작성자 설정' ;;
            git_origin) printf '저장소 origin 변경' ;;
            wifi_channel) printf 'Wi-Fi 채널 사용률' ;;
            wifi_active_watch) printf '사용 중 Wi-Fi 사용률 감시' ;;
            wifi_all_watch) printf '전체 Wi-Fi 사용률 감시' ;;
            show_help) printf '도움말 보기' ;;
            show_version) printf '버전 보기' ;;
            back) printf '뒤로' ;;
            exit) printf '종료' ;;
            invalid_selection) printf '잘못된 선택' ;;
            interactive_unavailable) printf '대화형 터미널을 사용할 수 없습니다.' ;;
            run_explicit) printf '명령을 직접 지정해서 실행하세요. 예:' ;;
            *) printf '%s' "$key" ;;
        esac
        return 0
    fi

    case "$key" in
        select_category) printf 'Select a category:' ;;
        select_command) printf 'Select a command:' ;;
        enter_selection) printf 'Enter selection: ' ;;
        github) printf 'GitHub' ;;
        network) printf 'Network' ;;
        info) printf 'Info' ;;
        install_local) printf 'Install local command' ;;
        github_ssh_setup) printf 'GitHub SSH setup' ;;
        github_ssh_verify) printf 'Verify GitHub SSH authentication' ;;
        git_author) printf 'Configure commit author only' ;;
        git_origin) printf 'Update repository origin' ;;
        wifi_channel) printf 'Wi-Fi channel utilization' ;;
        wifi_active_watch) printf 'Wi-Fi active utilization watch' ;;
        wifi_all_watch) printf 'Wi-Fi all utilization watch' ;;
        show_help) printf 'Show help' ;;
        show_version) printf 'Show version' ;;
        back) printf 'Back' ;;
        exit) printf 'Exit' ;;
        invalid_selection) printf 'Invalid selection' ;;
        interactive_unavailable) printf 'Interactive terminal is unavailable.' ;;
        run_explicit) printf 'Run a command explicitly, for example:' ;;
        *) printf '%s' "$key" ;;
    esac
}

cleanup() {
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        rm -rf -- "$TEMP_DIR"
    fi
}

check_bash() {
    if [[ -z "${BASH_VERSION:-}" ]]; then
        print_error "bash is required."
        exit 1
    fi
}

check_downloader() {
    if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
        return 0
    fi
    print_error "curl or wget is required."
    exit 1
}

download_file() {
    local url="$1"
    local destination="$2"

    debug "download ${url}"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$destination"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$destination" "$url"
    else
        return 127
    fi
}

validate_relative_path() {
    local path="$1"
    case "$path" in
        ""|/*|*".."*|*[$' \t\r\n']*)
            return 1
            ;;
    esac
    case "$path" in
        lib/*.sh|commands/*.sh)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

entry_script_dir() {
    local source="${BASH_SOURCE[0]}"
    case "$source" in
        /*) ;;
        *) source="$PWD/$source" ;;
    esac
    cd -P "$(dirname "$source")" >/dev/null 2>&1 && pwd
}

validate_downloaded_file() {
    local file="$1"
    [[ -f "$file" ]] || {
        print_error "Downloaded path is not a regular file: $file"
        return 1
    }
    [[ -s "$file" ]] || {
        print_error "Downloaded file is empty: $file"
        return 1
    }
    bash -n "$file" || {
        print_error "Downloaded file failed Bash syntax check: $file"
        return 1
    }
}

validate_local_tree() {
    local relative_path file

    validate_downloaded_file "$TEMP_DIR/entry.sh" || exit 1
    for relative_path in "${REQUIRED_FILES[@]}"; do
        validate_relative_path "$relative_path" || {
            print_error "Invalid required file path: $relative_path"
            exit 1
        }
        file="$TEMP_DIR/$relative_path"
        validate_downloaded_file "$file" || exit 1
    done
}

download_required_files() {
    local relative_path destination url

    for relative_path in "${REQUIRED_FILES[@]}"; do
        validate_relative_path "$relative_path" || {
            print_error "Invalid required file path: $relative_path"
            exit 1
        }
        destination="$TEMP_DIR/$relative_path"
        mkdir -p "$(dirname "$destination")"
        url="${CODEVILOT_RAW_BASE_URL%/}/${relative_path}"
        if ! download_file "$url" "$destination"; then
            print_error "Failed to download: $relative_path"
            exit 1
        fi
        validate_downloaded_file "$destination" || exit 1
    done
}

load_modules() {
    SCRIPT_DIR="$TEMP_DIR"
    export SCRIPT_DIR

    # shellcheck source=lib/common.sh
    . "$TEMP_DIR/lib/common.sh"
    # shellcheck source=lib/platform.sh
    . "$TEMP_DIR/lib/platform.sh"
    # shellcheck source=lib/ui.sh
    . "$TEMP_DIR/lib/ui.sh"
    # shellcheck source=commands/github-ssh.sh
    . "$TEMP_DIR/commands/github-ssh.sh"
    # shellcheck source=commands/git-author.sh
    . "$TEMP_DIR/commands/git-author.sh"
    # shellcheck source=commands/github-ssh-test.sh
    . "$TEMP_DIR/commands/github-ssh-test.sh"
    # shellcheck source=commands/git-origin.sh
    . "$TEMP_DIR/commands/git-origin.sh"
    # shellcheck source=commands/wifi-survey.sh
    . "$TEMP_DIR/commands/wifi-survey.sh"
}

show_help() {
    cat <<'EOF'
codevilot 0.1.0

Usage:
  curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh | bash
  curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh | bash -s -- <command> [options]
  codevilot <command> [options]

Available commands:
  install            Install codevilot as a local command
  github-ssh         Configure a personal GitHub SSH identity
  git-author         Configure Git commit author
  github-ssh-test    Verify GitHub SSH authentication
  git-origin         Update repository origin SSH alias
  wifi-survey        Show Linux Wi-Fi channel utilization
  help               Show help
  version            Show CLI version

Global options:
  -h, --help       Show help
  -v, --version    Show CLI version
EOF
}

install_usage() {
    cat <<'EOF'
Usage:
  curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh | bash -s -- install [options]

Install codevilot as a local command.

Options:
  --install-dir <path>      Install files here (default: ~/.local/share/codevilot-cli)
  --bin-dir <path>          Write codevilot wrapper here (default: ~/.local/bin)
  --help                    Show this help
EOF
}

install_parse_args() {
    INSTALL_DIR="${CODEVILOT_INSTALL_DIR:-$HOME/.local/share/codevilot-cli}"
    INSTALL_BIN_DIR="${CODEVILOT_BIN_DIR:-$HOME/.local/bin}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --install-dir)
                [[ $# -ge 2 ]] || {
                    print_error "--install-dir requires a value"
                    exit 1
                }
                INSTALL_DIR="$2"
                shift 2
                ;;
            --bin-dir)
                [[ $# -ge 2 ]] || {
                    print_error "--bin-dir requires a value"
                    exit 1
                }
                INSTALL_BIN_DIR="$2"
                shift 2
                ;;
            --help|-h)
                install_usage
                exit 0
                ;;
            *)
                print_error "Unknown option for install: $1"
                exit 2
                ;;
        esac
    done
}

install_entry_file() {
    local destination="$1"
    if [[ "$CODEVILOT_LOCAL_MODE" == "1" && -f "$TEMP_DIR/entry.sh" ]]; then
        cp "$TEMP_DIR/entry.sh" "$destination"
    else
        download_file "${CODEVILOT_RAW_BASE_URL%/}/entry.sh" "$destination" || {
            print_error "Failed to download: entry.sh"
            exit 1
        }
    fi
    validate_downloaded_file "$destination" || exit 1
}

install_main() {
    local relative_path source_file destination wrapper entry_path_quoted
    install_parse_args "$@"

    mkdir -p "$INSTALL_DIR/lib" "$INSTALL_DIR/commands" "$INSTALL_BIN_DIR"

    install_entry_file "$INSTALL_DIR/entry.sh"
    chmod 755 "$INSTALL_DIR/entry.sh"

    for relative_path in "${REQUIRED_FILES[@]}"; do
        source_file="$TEMP_DIR/$relative_path"
        destination="$INSTALL_DIR/$relative_path"
        validate_downloaded_file "$source_file" || exit 1
        mkdir -p "$(dirname "$destination")"
        cp "$source_file" "$destination"
        chmod 644 "$destination"
    done

    wrapper="$INSTALL_BIN_DIR/codevilot"
    entry_path_quoted="$(printf '%q' "$INSTALL_DIR/entry.sh")"
    {
        printf '#!/usr/bin/env bash\n'
        printf 'export CODEVILOT_LOCAL_MODE=1\n'
        printf 'exec bash %s "$@"\n' "$entry_path_quoted"
    } >"$wrapper"
    chmod 755 "$wrapper"

    cat <<EOF
codevilot installed.

Command:
  ${wrapper}

If this directory is not on PATH, add it:
  export PATH="${INSTALL_BIN_DIR}:\$PATH"

Try:
  codevilot help
EOF
}

show_version() {
    printf 'codevilot 0.1.0\n'
}

read_menu_selection() {
    local value
    if ! value="$(read_from_tty "$(msg enter_selection)")"; then
        print_error "$(msg interactive_unavailable)"
        printf '%s\n\n' "$(msg run_explicit)" >&2
        cat >&2 <<'EOF'
curl -fsSL <entry-url> | bash -s -- github-ssh --help
EOF
        return 1
    fi
    printf '%s' "$value"
}

write_to_tty() {
    local tty_path="${CODEVILOT_TTY_PATH:-/dev/tty}"
    if [[ -n "${CODEVILOT_TTY_OUTPUT_FILE:-}" ]]; then
        cat >>"$CODEVILOT_TTY_OUTPUT_FILE"
        return 0
    fi
    [[ -w "$tty_path" ]] || return 1
    cat >"$tty_path"
}

write_menu() {
    {
        ui_bold "codevilot CLI"
        printf '\n\n'
        ui_cyan "$(msg select_category)"
        printf '\n\n\n'
        printf '  1) %s\n' "$(msg github)"
        printf '  2) %s\n' "$(msg network)"
        printf '  3) %s\n' "$(msg info)"
        printf '  4) %s\n' "$(msg install_local)"
        printf '  0) %s\n' "$(msg exit)"
        printf '\n'
    } | write_to_tty
}

write_github_menu() {
    {
        ui_bold "codevilot CLI"
        printf '\n\n'
        ui_cyan "$(msg github)"
        printf '\n\n'
        ui_cyan "$(msg select_command)"
        printf '\n\n'
        printf '  1) %s\n' "$(msg github_ssh_setup)"
        printf '  2) %s\n' "$(msg github_ssh_verify)"
        printf '  3) %s\n' "$(msg git_author)"
        printf '  4) %s\n' "$(msg git_origin)"
        printf '  0) %s\n' "$(msg back)"
        printf '\n'
    } | write_to_tty
}

write_network_menu() {
    {
        ui_bold "codevilot CLI"
        printf '\n\n'
        ui_cyan "$(msg network)"
        printf '\n\n'
        ui_cyan "$(msg select_command)"
        printf '\n\n'
        printf '  1) %s\n' "$(msg wifi_channel)"
        printf '  2) %s\n' "$(msg wifi_active_watch)"
        printf '  3) %s\n' "$(msg wifi_all_watch)"
        printf '  0) %s\n' "$(msg back)"
        printf '\n'
    } | write_to_tty
}

write_info_menu() {
    {
        ui_bold "codevilot CLI"
        printf '\n\n'
        ui_cyan "$(msg info)"
        printf '\n\n'
        ui_cyan "$(msg select_command)"
        printf '\n\n'
        printf '  1) %s\n' "$(msg show_help)"
        printf '  2) %s\n' "$(msg show_version)"
        printf '  0) %s\n' "$(msg back)"
        printf '\n'
    } | write_to_tty
}

print_interactive_unavailable() {
    print_error "$(msg interactive_unavailable)"
    printf '%s\n\n' "$(msg run_explicit)" >&2
    cat >&2 <<'EOF'
curl -fsSL <entry-url> | bash -s -- github-ssh --help
EOF
}

show_menu() {
    local selection

    while true; do
        if ! write_menu; then
            print_interactive_unavailable
            return 1
        fi
        selection="$(read_menu_selection)" || return 1
        case "$selection" in
            1)
                show_github_menu || return $?
                ;;
            2)
                show_network_menu || return $?
                ;;
            3)
                show_info_menu || return $?
                ;;
            4)
                install_main
                return $?
                ;;
            0)
                return 0
                ;;
            *)
                if [[ -n "${CODEVILOT_TTY_OUTPUT_FILE:-}" ]]; then
                    printf '%s: %s\n' "$(msg invalid_selection)" "$selection" >>"$CODEVILOT_TTY_OUTPUT_FILE"
                else
                    printf '%s: %s\n' "$(msg invalid_selection)" "$selection" >"${CODEVILOT_TTY_PATH:-/dev/tty}"
                fi
                ;;
        esac
    done
}

show_github_menu() {
    local selection

    while true; do
        if ! write_github_menu; then
            print_interactive_unavailable
            return 1
        fi
        selection="$(read_menu_selection)" || return 1
        case "$selection" in
            1)
                github_ssh_main
                return $?
                ;;
            2)
                github_ssh_test_main
                return $?
                ;;
            3)
                git_author_main
                return $?
                ;;
            4)
                git_origin_main
                return $?
                ;;
            0)
                return 0
                ;;
            *)
                if [[ -n "${CODEVILOT_TTY_OUTPUT_FILE:-}" ]]; then
                    printf '%s: %s\n' "$(msg invalid_selection)" "$selection" >>"$CODEVILOT_TTY_OUTPUT_FILE"
                else
                    printf '%s: %s\n' "$(msg invalid_selection)" "$selection" >"${CODEVILOT_TTY_PATH:-/dev/tty}"
                fi
                ;;
        esac
    done
}

show_network_menu() {
    local selection

    while true; do
        if ! write_network_menu; then
            print_interactive_unavailable
            return 1
        fi
        selection="$(read_menu_selection)" || return 1
        case "$selection" in
            1)
                wifi_survey_main
                return $?
                ;;
            2)
                wifi_survey_main --watch 1 --in-use
                return $?
                ;;
            3)
                wifi_survey_main --watch 1 --all
                return $?
                ;;
            0)
                return 0
                ;;
            *)
                if [[ -n "${CODEVILOT_TTY_OUTPUT_FILE:-}" ]]; then
                    printf '%s: %s\n' "$(msg invalid_selection)" "$selection" >>"$CODEVILOT_TTY_OUTPUT_FILE"
                else
                    printf '%s: %s\n' "$(msg invalid_selection)" "$selection" >"${CODEVILOT_TTY_PATH:-/dev/tty}"
                fi
                ;;
        esac
    done
}

show_info_menu() {
    local selection

    while true; do
        if ! write_info_menu; then
            print_interactive_unavailable
            return 1
        fi
        selection="$(read_menu_selection)" || return 1
        case "$selection" in
            1)
                show_help
                return 0
                ;;
            2)
                show_version
                return 0
                ;;
            0)
                return 0
                ;;
            *)
                if [[ -n "${CODEVILOT_TTY_OUTPUT_FILE:-}" ]]; then
                    printf '%s: %s\n' "$(msg invalid_selection)" "$selection" >>"$CODEVILOT_TTY_OUTPUT_FILE"
                else
                    printf '%s: %s\n' "$(msg invalid_selection)" "$selection" >"${CODEVILOT_TTY_PATH:-/dev/tty}"
                fi
                ;;
        esac
    done
}

dispatch() {
    local command_name="${1:-}"

    case "$command_name" in
        "")
            show_menu
            ;;
        install)
            shift
            install_main "$@"
            ;;
        github-ssh)
            shift
            github_ssh_main "$@"
            ;;
        git-author)
            shift
            git_author_main "$@"
            ;;
        github-ssh-test|ssh-test)
            shift
            github_ssh_test_main "$@"
            ;;
        git-origin)
            shift
            git_origin_main "$@"
            ;;
        wifi-survey|wifi-channel|wifi-cu)
            shift
            wifi_survey_main "$@"
            ;;
        help|-h|--help)
            show_help
            ;;
        version|-v|--version)
            show_version
            ;;
        *)
            print_error "Unknown command: $command_name"
            show_help
            exit 2
            ;;
    esac
}

main() {
    check_bash

    case "${1:-}" in
        lang=ko|lang=en)
            lang="${1#lang=}"
            shift
            ;;
    esac

    if [[ "$CODEVILOT_LOCAL_MODE" == "1" ]]; then
        TEMP_DIR="$(entry_script_dir)"
        validate_local_tree
        load_modules
        dispatch "$@"
        return
    fi

    check_downloader

    TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codevilot.XXXXXX")"
    trap cleanup EXIT INT TERM

    download_required_files
    load_modules
    dispatch "$@"
}

main "$@"
