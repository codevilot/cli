#!/usr/bin/env bash

: "${SCRIPT_DIR:?SCRIPT_DIR must be set by entry.sh}"

# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=../lib/platform.sh
. "$SCRIPT_DIR/lib/platform.sh"

github_ssh_test_usage() {
    cat <<'EOF'
Usage:
  curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh | bash -s -- github-ssh-test --alias <ssh-alias>

Verify GitHub SSH authentication.

Options:
  --alias <ssh-alias>       SSH Host alias
  --public-key <path>       Public key path to show if GitHub rejects the key
  --dry-run                 Show planned command without connecting
  --help                    Show this help
EOF
}

github_ssh_test_parse_args() {
    GITHUB_SSH_TEST_ALIAS=""
    GITHUB_SSH_TEST_PUBLIC_KEY=""
    DRY_RUN=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --alias)
                [[ $# -ge 2 ]] || die "--alias requires a value"
                GITHUB_SSH_TEST_ALIAS="$2"
                shift 2
                ;;
            --public-key)
                [[ $# -ge 2 ]] || die "--public-key requires a value"
                GITHUB_SSH_TEST_PUBLIC_KEY="$(absolute_path "$2")"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --help|-h)
                github_ssh_test_usage
                exit 0
                ;;
            *)
                die "Unknown option for github-ssh-test: $1"
                ;;
        esac
    done
}

github_ssh_test_default_public_key() {
    local alias_name="$1" suffix
    suffix="$alias_name"
    suffix="${suffix#github-}"
    suffix="${suffix//[^A-Za-z0-9._-]/_}"
    printf '%s/.ssh/id_ed25519_%s.pub' "$HOME" "$suffix"
}

github_ssh_test_run() {
    local alias_name="$1" public_key="$2" dry_run="$3"
    local output status username

    if [[ "$dry_run" == "1" ]]; then
        printf '[dry-run] ssh -T git@%q\n' "$alias_name"
        return 0
    fi

    output="$(ssh -T "git@${alias_name}" 2>&1)"
    status=$?

    if printf '%s\n' "$output" | grep -Eq "Hi .+! You've successfully authenticated"; then
        username="$(printf '%s\n' "$output" | sed -n "s/.*Hi \([^!]*\)! You've successfully authenticated.*/\1/p" | head -n 1)"
        cat <<EOF
GitHub SSH authentication succeeded.

Authenticated account:
  ${username}

SSH alias:
  ${alias_name}
EOF
        return 0
    fi

    if printf '%s\n' "$output" | grep -Eiq 'permission denied|publickey'; then
        cat >&2 <<EOF
GitHub rejected the SSH key.

Register this public key in your GitHub account:
  ${public_key}
EOF
        return 1
    fi

    printf '%s\n' "$output" >&2
    die "SSH authentication test did not return GitHub's success message. Exit code: $status"
}

github_ssh_test_main() {
    github_ssh_test_parse_args "$@"
    if [[ -z "$GITHUB_SSH_TEST_ALIAS" ]]; then
        if [[ "$DRY_RUN" == "1" ]]; then
            die "--alias is required"
        fi
        GITHUB_SSH_TEST_ALIAS="$(prompt_required "GitHub SSH alias:")"
    fi
    if [[ -z "$GITHUB_SSH_TEST_PUBLIC_KEY" ]]; then
        GITHUB_SSH_TEST_PUBLIC_KEY="$(github_ssh_test_default_public_key "$GITHUB_SSH_TEST_ALIAS")"
    fi
    github_ssh_test_run "$GITHUB_SSH_TEST_ALIAS" "$GITHUB_SSH_TEST_PUBLIC_KEY" "$DRY_RUN"
}
