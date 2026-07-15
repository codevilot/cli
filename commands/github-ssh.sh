#!/usr/bin/env bash

: "${SCRIPT_DIR:?SCRIPT_DIR must be set by cli.sh}"

# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=../lib/platform.sh
. "$SCRIPT_DIR/lib/platform.sh"

github_ssh_usage() {
    cat <<'EOF'
Usage:
  codevilot github-ssh [options]
  ./cli.sh github-ssh [options]

Configure a personal GitHub SSH identity.

Options:
  --alias <alias>            SSH Host alias, for example github-user
  --email <email>            GitHub email used for key comment and Git commits
  --name <git-name>          Git commit author name
  --key-file <path>          SSH private key path
  --scope <local|global>     Git config scope
  --test                     Run GitHub SSH authentication test
  --non-interactive          Do not prompt; fail when required values are missing
  --force                    Allow updating an existing managed SSH config block
  --dry-run                  Show planned changes without modifying files
  --help                     Show this help
EOF
}

github_ssh_validate_alias() {
    local alias_name="$1"
    [[ "$alias_name" =~ ^[A-Za-z0-9._-]+$ ]]
}

github_ssh_default_key_file() {
    local alias_name="$1"
    local suffix="$alias_name"
    suffix="${suffix#github-}"
    suffix="${suffix//[^A-Za-z0-9._-]/_}"
    printf '%s/.ssh/id_ed25519_%s' "$HOME" "$suffix"
}

github_ssh_escape_config_path() {
    local path="$1"
    path="${path//\\/\\\\}"
    path="${path//\"/\\\"}"
    printf '"%s"' "$path"
}

github_ssh_block() {
    local alias_name="$1"
    local key_display="$2"
    local escaped_key
    escaped_key="$(github_ssh_escape_config_path "$key_display")"
    cat <<EOF
# BEGIN codevilot-cli:${alias_name}
Host ${alias_name}
    HostName github.com
    User git
    IdentityFile ${escaped_key}
    IdentitiesOnly yes
# END codevilot-cli:${alias_name}
EOF
}

github_ssh_parse_args() {
    GITHUB_SSH_ALIAS=""
    GITHUB_SSH_EMAIL=""
    GITHUB_SSH_NAME=""
    GITHUB_SSH_KEY_FILE=""
    GITHUB_SSH_SCOPE=""
    GITHUB_SSH_RUN_TEST=0
    GITHUB_SSH_NON_INTERACTIVE=0
    GITHUB_SSH_FORCE=0
    DRY_RUN=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --alias)
                [[ $# -ge 2 ]] || die "--alias requires a value"
                GITHUB_SSH_ALIAS="$2"
                shift 2
                ;;
            --email)
                [[ $# -ge 2 ]] || die "--email requires a value"
                GITHUB_SSH_EMAIL="$2"
                shift 2
                ;;
            --name)
                [[ $# -ge 2 ]] || die "--name requires a value"
                GITHUB_SSH_NAME="$2"
                shift 2
                ;;
            --key-file)
                [[ $# -ge 2 ]] || die "--key-file requires a value"
                GITHUB_SSH_KEY_FILE="$2"
                shift 2
                ;;
            --scope)
                [[ $# -ge 2 ]] || die "--scope requires a value"
                GITHUB_SSH_SCOPE="$2"
                shift 2
                ;;
            --test)
                GITHUB_SSH_RUN_TEST=1
                shift
                ;;
            --non-interactive)
                GITHUB_SSH_NON_INTERACTIVE=1
                shift
                ;;
            --force)
                GITHUB_SSH_FORCE=1
                shift
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --help|-h)
                github_ssh_usage
                exit 0
                ;;
            *)
                die "Unknown option for github-ssh: $1"
                ;;
        esac
    done
}

github_ssh_collect_inputs() {
    local default_key

    GITHUB_SSH_ALIAS="$(trim "$GITHUB_SSH_ALIAS")"
    GITHUB_SSH_EMAIL="$(trim "$GITHUB_SSH_EMAIL")"
    GITHUB_SSH_NAME="$(trim "$GITHUB_SSH_NAME")"
    GITHUB_SSH_SCOPE="$(trim "$GITHUB_SSH_SCOPE")"

    if [[ "$GITHUB_SSH_NON_INTERACTIVE" == "1" ]]; then
        [[ -n "$GITHUB_SSH_ALIAS" ]] || die "--alias is required in --non-interactive mode"
        [[ -n "$GITHUB_SSH_EMAIL" ]] || die "--email is required in --non-interactive mode"
        [[ -n "$GITHUB_SSH_NAME" ]] || die "--name is required in --non-interactive mode"
        [[ -n "$GITHUB_SSH_SCOPE" ]] || die "--scope is required in --non-interactive mode"
    else
        [[ -n "$GITHUB_SSH_ALIAS" ]] || GITHUB_SSH_ALIAS="$(prompt_required "GitHub SSH alias [example: github-user]:")"
        [[ -n "$GITHUB_SSH_EMAIL" ]] || GITHUB_SSH_EMAIL="$(prompt_required "GitHub email:")"
        [[ -n "$GITHUB_SSH_NAME" ]] || GITHUB_SSH_NAME="$(prompt_required "Git commit author name:")"
    fi

    github_ssh_validate_alias "$GITHUB_SSH_ALIAS" || die "Invalid alias. Use letters, numbers, dots, underscores, or hyphens."

    default_key="$(github_ssh_default_key_file "$GITHUB_SSH_ALIAS")"
    if [[ -z "$GITHUB_SSH_KEY_FILE" ]]; then
        if [[ "$GITHUB_SSH_NON_INTERACTIVE" == "1" ]]; then
            GITHUB_SSH_KEY_FILE="$default_key"
        else
            GITHUB_SSH_KEY_FILE="$(prompt_default "SSH key path" "$default_key")"
        fi
    fi

    if [[ -z "$GITHUB_SSH_SCOPE" ]]; then
        if [[ "$GITHUB_SSH_NON_INTERACTIVE" == "1" ]]; then
            die "--scope is required in --non-interactive mode"
        fi
        while true; do
            GITHUB_SSH_SCOPE="$(prompt_default "Git config scope" "local")"
            case "$GITHUB_SSH_SCOPE" in
                local|global) break ;;
                *) warn "Scope must be local or global." ;;
            esac
        done
    fi

    case "$GITHUB_SSH_SCOPE" in
        local|global) ;;
        *) die "--scope must be local or global" ;;
    esac

    GITHUB_SSH_KEY_FILE="$(absolute_path "$GITHUB_SSH_KEY_FILE")"
}

github_ssh_prepare_key() {
    local key_file="$1"
    local public_key="${key_file}.pub"
    local choice

    if [[ "$DRY_RUN" == "1" ]]; then
        if [[ -e "$key_file" || -e "$public_key" ]]; then
            printf '[dry-run] would validate existing SSH key pair: %s and %s\n' "$key_file" "$public_key"
        else
            printf '[dry-run] would generate SSH key: %s\n' "$key_file"
        fi
        return 0
    fi

    ensure_dir "$(dirname "$key_file")" 700

    if [[ -f "$key_file" && -f "$public_key" ]]; then
        chmod 600 "$key_file"
        chmod 644 "$public_key"
        return 0
    fi

    if [[ -e "$key_file" || -e "$public_key" ]]; then
        if [[ "$GITHUB_SSH_NON_INTERACTIVE" == "1" ]]; then
            die "Incomplete SSH key pair. Expected both $key_file and $public_key."
        fi

        warn "An SSH key file already exists, but the pair is incomplete or needs review."
        while true; do
            cat >&2 <<EOF
1. Use existing key
2. Enter another key path
3. Cancel
EOF
            printf 'Choose [1-3]: ' >&2
            IFS= read -r choice || die "Canceled"
            choice="$(trim "$choice")"
            case "$choice" in
                1)
                    [[ -f "$key_file" && -f "$public_key" ]] || die "Cannot use incomplete SSH key pair."
                    chmod 600 "$key_file"
                    chmod 644 "$public_key"
                    return 0
                    ;;
                2)
                    GITHUB_SSH_KEY_FILE="$(prompt_required "SSH key path:")"
                    GITHUB_SSH_KEY_FILE="$(absolute_path "$GITHUB_SSH_KEY_FILE")"
                    github_ssh_prepare_key "$GITHUB_SSH_KEY_FILE"
                    return $?
                    ;;
                3)
                    die "Canceled"
                    ;;
                *)
                    warn "Choose 1, 2, or 3."
                    ;;
            esac
        done
    fi

    run_cmd ssh-keygen -t ed25519 -C "$GITHUB_SSH_EMAIL" -f "$key_file" -N ""
    chmod 600 "$key_file"
    chmod 644 "$public_key"
}

github_ssh_write_config() {
    local alias_name="$1"
    local key_file="$2"
    local ssh_dir config_file key_display begin_marker end_marker tmp_file backup_file_path
    local in_block=0

    ssh_dir="$HOME/.ssh"
    config_file="$ssh_dir/config"
    key_display="$(home_path_to_tilde "$key_file")"
    begin_marker="# BEGIN codevilot-cli:${alias_name}"
    end_marker="# END codevilot-cli:${alias_name}"

    if [[ "$DRY_RUN" == "1" ]]; then
        printf '[dry-run] would update SSH config block in %s\n' "$config_file"
        github_ssh_block "$alias_name" "$key_display"
        return 0
    fi

    ensure_dir "$ssh_dir" 700
    [[ -f "$config_file" ]] || : >"$config_file"
    chmod 600 "$config_file"

    if grep -Fqx "$begin_marker" "$config_file" && [[ "$GITHUB_SSH_FORCE" != "1" ]]; then
        info "Updating existing managed SSH config block for ${alias_name}."
    fi

    backup_file_path="$(backup_file "$config_file")"
    tmp_file="$(mktemp "${config_file}.tmp.XXXXXX")"
    trap 'rm -f "$tmp_file"' RETURN

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "$begin_marker" ]]; then
            in_block=1
            continue
        fi
        if [[ "$line" == "$end_marker" && "$in_block" == "1" ]]; then
            in_block=0
            continue
        fi
        if [[ "$in_block" == "0" ]]; then
            printf '%s\n' "$line" >>"$tmp_file"
        fi
    done <"$config_file"

    if [[ -s "$tmp_file" ]]; then
        printf '\n' >>"$tmp_file"
    fi
    github_ssh_block "$alias_name" "$key_display" >>"$tmp_file"
    mv "$tmp_file" "$config_file"
    chmod 600 "$config_file"

    if have_command ssh; then
        if ! ssh -G "git@${alias_name}" >/dev/null 2>"${config_file}.verify.err"; then
            if [[ -n "$backup_file_path" && -f "$backup_file_path" ]]; then
                cp "$backup_file_path" "$config_file"
            else
                rm -f "$config_file"
            fi
            error "SSH config validation failed. Restored the previous config."
            if [[ -s "${config_file}.verify.err" ]]; then
                sed 's/^/ssh: /' "${config_file}.verify.err" >&2
            fi
            rm -f "${config_file}.verify.err"
            exit 1
        fi
        rm -f "${config_file}.verify.err"
    else
        warn "ssh command not found; skipped SSH config validation."
    fi

    rm -f "$tmp_file"
    trap - RETURN
}

github_ssh_git_get() {
    local scope="$1"
    local key="$2"
    if [[ "$scope" == "global" ]]; then
        git config --global "$key" 2>/dev/null || true
    else
        git config "$key" 2>/dev/null || true
    fi
}

github_ssh_git_set() {
    local scope="$1"
    local key="$2"
    local value="$3"
    if [[ "$DRY_RUN" == "1" ]]; then
        if [[ "$scope" == "global" ]]; then
            printf '[dry-run] git config --global %q %q\n' "$key" "$value"
        else
            printf '[dry-run] git config %q %q\n' "$key" "$value"
        fi
        return 0
    fi

    if [[ "$scope" == "global" ]]; then
        git config --global "$key" "$value"
    else
        git config "$key" "$value"
    fi
}

github_ssh_configure_git() {
    local scope="$1"
    local name="$2"
    local email="$3"
    local old_name old_email new_name new_email

    have_command git || die "git command not found"

    if [[ "$scope" == "local" && "$DRY_RUN" != "1" ]]; then
        git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "--scope local requires running inside a Git repository"
    fi

    old_name="$(github_ssh_git_get "$scope" user.name)"
    old_email="$(github_ssh_git_get "$scope" user.email)"

    if [[ "$GITHUB_SSH_NON_INTERACTIVE" != "1" && ( "$old_name" != "" || "$old_email" != "" ) && ( "$old_name" != "$name" || "$old_email" != "$email" ) ]]; then
        cat >&2 <<EOF
Current Git ${scope} config:
  user.name:  ${old_name:-<unset>}
  user.email: ${old_email:-<unset>}

New Git ${scope} config:
  user.name:  ${name}
  user.email: ${email}
EOF
        confirm "Apply these Git config changes?" "y" || die "Canceled"
    fi

    github_ssh_git_set "$scope" user.name "$name"
    github_ssh_git_set "$scope" user.email "$email"

    if [[ "$DRY_RUN" != "1" ]]; then
        new_name="$(github_ssh_git_get "$scope" user.name)"
        new_email="$(github_ssh_git_get "$scope" user.email)"
        [[ "$new_name" == "$name" ]] || die "Failed to verify git user.name"
        [[ "$new_email" == "$email" ]] || die "Failed to verify git user.email"
    fi
}

github_ssh_print_public_key() {
    local public_key="$1"
    local clip

    if [[ "$DRY_RUN" == "1" ]]; then
        printf '[dry-run] would show public key from %s\n' "$public_key"
        return 0
    fi

    [[ -f "$public_key" ]] || die "Public key not found: $public_key"

    cat <<EOF

Register the following public key in GitHub:

GitHub
-> Settings
-> SSH and GPG keys
-> New SSH key

EOF
    cat "$public_key"
    printf '\n'

    clip="$(clipboard_command)"
    if [[ -n "$clip" && "$GITHUB_SSH_NON_INTERACTIVE" != "1" ]]; then
        if confirm "Copy the public key to clipboard?" "n"; then
            case "$clip" in
                pbcopy) pbcopy <"$public_key" ;;
                wl-copy) wl-copy <"$public_key" ;;
                "xclip -selection clipboard") xclip -selection clipboard <"$public_key" ;;
                "xsel --clipboard --input") xsel --clipboard --input <"$public_key" ;;
            esac
        fi
    fi
}

github_ssh_test_auth() {
    local alias_name="$1"
    local output status username

    if [[ "$DRY_RUN" == "1" ]]; then
        printf '[dry-run] ssh -T git@%q\n' "$alias_name"
        return 0
    fi

    output="$(ssh -T "git@${alias_name}" 2>&1)"
    status=$?
    printf '%s\n' "$output"

    if printf '%s\n' "$output" | grep -Eq "Hi .+! You've successfully authenticated"; then
        username="$(printf '%s\n' "$output" | sed -n "s/.*Hi \([^!]*\)! You've successfully authenticated.*/\1/p" | head -n 1)"
        [[ -n "$username" ]] && printf 'Authenticated GitHub account: %s\n' "$username"
        warn "Confirm this is the GitHub account you intended to use."
        return 0
    fi

    if printf '%s\n' "$output" | grep -Eiq 'permission denied|publickey'; then
        die "GitHub rejected the SSH key. Register the public key in GitHub and try again."
    elif printf '%s\n' "$output" | grep -Eiq 'could not resolve hostname|name or service not known|nodename nor servname'; then
        die "DNS or hostname resolution failed while connecting to GitHub."
    elif printf '%s\n' "$output" | grep -Eiq 'host key verification failed'; then
        die "Host key verification failed. Review your SSH known_hosts entry for github.com."
    elif printf '%s\n' "$output" | grep -Eiq 'connection timed out|network is unreachable|connection refused'; then
        die "Network connection to GitHub SSH failed."
    fi

    die "SSH authentication test did not return GitHub's success message. Exit code: $status"
}

github_ssh_final_notes() {
    local alias_name="$1"
    cat <<EOF

Clone with:
  git clone git@${alias_name}:OWNER/REPOSITORY.git

Change an existing repository origin with:
  git remote set-url origin git@${alias_name}:OWNER/REPOSITORY.git

The alias "${alias_name}" is resolved by the ~/.ssh/config file
on the machine where the git command is executed.
EOF
}

github_ssh_main() {
    github_ssh_parse_args "$@"
    github_ssh_collect_inputs

    github_ssh_prepare_key "$GITHUB_SSH_KEY_FILE"
    github_ssh_write_config "$GITHUB_SSH_ALIAS" "$GITHUB_SSH_KEY_FILE"
    github_ssh_configure_git "$GITHUB_SSH_SCOPE" "$GITHUB_SSH_NAME" "$GITHUB_SSH_EMAIL"
    github_ssh_print_public_key "${GITHUB_SSH_KEY_FILE}.pub"

    if [[ "$GITHUB_SSH_RUN_TEST" == "1" ]]; then
        github_ssh_test_auth "$GITHUB_SSH_ALIAS"
    elif [[ "$GITHUB_SSH_NON_INTERACTIVE" != "1" ]]; then
        if confirm "Run GitHub SSH authentication test now?" "n"; then
            github_ssh_test_auth "$GITHUB_SSH_ALIAS"
        fi
    fi

    github_ssh_final_notes "$GITHUB_SSH_ALIAS"
    success "github-ssh configuration complete."
}
