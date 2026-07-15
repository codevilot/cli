#!/usr/bin/env bash
set -u

CODEVILOT_REF="${CODEVILOT_REF:-main}"
CODEVILOT_RAW_BASE_URL="${CODEVILOT_RAW_BASE_URL:-https://raw.githubusercontent.com/codevilot/cli/${CODEVILOT_REF}}"
CODEVILOT_DEBUG="${CODEVILOT_DEBUG:-}"
TEMP_DIR=""

REQUIRED_FILES=(
    "lib/common.sh"
    "lib/platform.sh"
    "lib/ui.sh"
    "commands/github-ssh.sh"
    "commands/git-author.sh"
    "commands/github-ssh-test.sh"
    "commands/git-origin.sh"
)

debug() {
    if [[ -n "$CODEVILOT_DEBUG" ]]; then
        printf 'DEBUG: %s\n' "$*" >&2
    fi
}

print_error() {
    printf 'ERROR: %s\n' "$*" >&2
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
}

show_help() {
    cat <<'EOF'
codevilot 0.1.0

Usage:
  curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh | bash
  curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh | bash -s -- <command> [options]

Available commands:
  github-ssh         Configure a personal GitHub SSH identity
  git-author         Configure Git commit author
  github-ssh-test    Verify GitHub SSH authentication
  git-origin         Update repository origin SSH alias
  help               Show help
  version            Show CLI version

Global options:
  -h, --help       Show help
  -v, --version    Show CLI version
EOF
}

show_version() {
    printf 'codevilot 0.1.0\n'
}

read_menu_selection() {
    local value
    if ! value="$(read_from_tty "Enter selection: ")"; then
        print_error "Interactive terminal is unavailable."
        cat >&2 <<'EOF'
Run a command explicitly, for example:

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
        ui_cyan "Select a category:"
        cat <<'EOF'


  1) GitHub
  2) Show help
  3) Show version
  0) Exit

EOF
    } | write_to_tty
}

write_github_menu() {
    {
        ui_bold "codevilot CLI"
        printf '\n\n'
        ui_cyan "GitHub"
        printf '\n\n'
        ui_cyan "Select a command:"
        cat <<'EOF'

  1) GitHub SSH setup
  2) Git author setup
  3) Verify GitHub SSH authentication
  4) Update repository origin
  0) Back

EOF
    } | write_to_tty
}

print_interactive_unavailable() {
    print_error "Interactive terminal is unavailable."
    cat >&2 <<'EOF'
Run a command explicitly, for example:

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
                show_help
                return 0
                ;;
            3)
                show_version
                return 0
                ;;
            0)
                return 0
                ;;
            *)
                if [[ -n "${CODEVILOT_TTY_OUTPUT_FILE:-}" ]]; then
                    printf 'Invalid selection: %s\n' "$selection" >>"$CODEVILOT_TTY_OUTPUT_FILE"
                else
                    printf 'Invalid selection: %s\n' "$selection" >"${CODEVILOT_TTY_PATH:-/dev/tty}"
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
                git_author_main
                return $?
                ;;
            3)
                github_ssh_test_main
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
                    printf 'Invalid selection: %s\n' "$selection" >>"$CODEVILOT_TTY_OUTPUT_FILE"
                else
                    printf 'Invalid selection: %s\n' "$selection" >"${CODEVILOT_TTY_PATH:-/dev/tty}"
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
    check_downloader

    TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codevilot.XXXXXX")"
    trap cleanup EXIT INT TERM

    download_required_files
    load_modules
    dispatch "$@"
}

main "$@"
