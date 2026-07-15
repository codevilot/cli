#!/usr/bin/env bash
set -u

SCRIPT_PATH="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" >/dev/null 2>&1 && pwd)"

# Resolve a symlinked entrypoint far enough to find this repository's lib/commands.
while [[ -L "$SCRIPT_PATH" ]]; do
    LINK_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" >/dev/null 2>&1 && pwd)"
    LINK_TARGET="$(readlink "$SCRIPT_PATH")"
    [[ "$LINK_TARGET" != /* ]] && LINK_TARGET="$LINK_DIR/$LINK_TARGET"
    SCRIPT_PATH="$LINK_TARGET"
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" >/dev/null 2>&1 && pwd)"
done

# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

show_help() {
    cat <<EOF
${CODEVILOT_NAME} ${CODEVILOT_VERSION}

Usage:
  ./cli.sh <command> [options]
  codevilot <command> [options]

Available commands:
  github-ssh    Configure a personal GitHub SSH identity
  help          Show help
  version       Show CLI version

Global options:
  -h, --help       Show help
  -v, --version    Show CLI version
EOF
}

show_version() {
    printf '%s %s\n' "$CODEVILOT_NAME" "$CODEVILOT_VERSION"
}

unknown_command() {
    local command_name="$1"
    cat >&2 <<EOF
Unknown command: ${command_name}

Available commands:
  github-ssh    Configure a personal GitHub SSH identity
  help          Show help
  version       Show CLI version
EOF
    exit 1
}

main() {
    local command_name="${1:-help}"
    if [[ $# -gt 0 ]]; then
        shift
    fi

    case "$command_name" in
        help|-h|--help)
            show_help
            ;;
        version|-v|--version)
            show_version
            ;;
        github-ssh)
            # shellcheck source=commands/github-ssh.sh
            . "$SCRIPT_DIR/commands/github-ssh.sh"
            github_ssh_main "$@"
            ;;
        *)
            unknown_command "$command_name"
            ;;
    esac
}

main "$@"
