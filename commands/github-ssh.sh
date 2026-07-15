#!/usr/bin/env bash

: "${SCRIPT_DIR:?SCRIPT_DIR must be set by entry.sh}"

# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=../lib/platform.sh
. "$SCRIPT_DIR/lib/platform.sh"
# shellcheck source=../lib/ui.sh
. "$SCRIPT_DIR/lib/ui.sh"

github_ssh_usage() {
    cat <<'EOF'
Usage:
  curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh | bash -s -- github-ssh [options]

Configure a personal GitHub SSH identity.

Options:
  --alias <alias>            SSH Host alias, for example github-user
  --email <email>            Email used for key comment and default commit author email
  --name <git-name>          Deprecated; use git-author
  --key-file <path>          SSH private key path
  --scope <local|global>     Deprecated; use git-author
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
    GITHUB_SSH_AUTHOR_OPTIONS=0
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
                GITHUB_SSH_AUTHOR_OPTIONS=1
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
                GITHUB_SSH_AUTHOR_OPTIONS=1
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
    else
        [[ -n "$GITHUB_SSH_ALIAS" ]] || GITHUB_SSH_ALIAS="$(prompt_required "GitHub SSH alias [example: github-user]:")"
        [[ -n "$GITHUB_SSH_EMAIL" ]] || GITHUB_SSH_EMAIL="$(prompt_required "GitHub email:")"
    fi

    github_ssh_validate_alias "$GITHUB_SSH_ALIAS" || die "Invalid alias. Use letters, numbers, dots, underscores, or hyphens."

    default_key="$(github_ssh_default_key_file "$GITHUB_SSH_ALIAS")"
    if [[ -z "$GITHUB_SSH_KEY_FILE" ]]; then
        if [[ "$GITHUB_SSH_NON_INTERACTIVE" == "1" ]]; then
            GITHUB_SSH_KEY_FILE="$default_key"
        elif [[ -f "$default_key" && -f "${default_key}.pub" ]]; then
            GITHUB_SSH_KEY_FILE="$default_key"
        else
            GITHUB_SSH_KEY_FILE="$(prompt_default "SSH key path" "$default_key")"
        fi
    fi

    if [[ -n "$GITHUB_SSH_SCOPE" ]]; then
        case "$GITHUB_SSH_SCOPE" in
            local|global) ;;
            *) die "--scope must be local or global" ;;
        esac
    fi

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
        printf 'Existing SSH key found:\n  %s\n\n' "$key_file"
        if [[ "$GITHUB_SSH_NON_INTERACTIVE" != "1" ]]; then
            while true; do
                cat >&2 <<EOF
  1) Use existing key
  2) Enter another key path
  0) Cancel
EOF
                choice="$(read_from_tty "Enter selection: ")" || die "Canceled"
                choice="$(trim "$choice")"
                case "$choice" in
                    1) break ;;
                    2)
                        GITHUB_SSH_KEY_FILE="$(prompt_required "SSH key path:")"
                        GITHUB_SSH_KEY_FILE="$(absolute_path "$GITHUB_SSH_KEY_FILE")"
                        github_ssh_prepare_key "$GITHUB_SSH_KEY_FILE"
                        return $?
                        ;;
                    0)
                        die "Canceled"
                        ;;
                    *)
                        warn "Choose 1, 2, or 0."
                        ;;
                esac
            done
        fi
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
Existing SSH key found:
  $key_file

  1) Use existing key
  2) Enter another key path
  0) Cancel
EOF
            choice="$(read_from_tty "Enter selection: ")" || die "Canceled"
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
                0)
                    die "Canceled"
                    ;;
                *)
                    warn "Choose 1, 2, or 0."
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
        printf 'SSH alias already configured:\n  %s\n\nNo SSH config changes were required.\n' "$alias_name"
        return 0
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

github_ssh_print_public_key() {
    local public_key="$1"
    local clip
    local github_keys_url="https://github.com/settings/keys"

    if [[ "$DRY_RUN" == "1" ]]; then
        printf '[dry-run] would show public key from %s\n' "$public_key"
        return 0
    fi

    [[ -f "$public_key" ]] || die "Public key not found: $public_key"

    printf '\n'
    ui_step "3" "3" "Register this public key in GitHub"
    ui_status "Open" "$github_keys_url"
    ui_status "Click" "New SSH key"
    ui_status "Title" "$(hostname 2>/dev/null || printf codevilot)-${GITHUB_SSH_ALIAS}"
    ui_status "Key type" "Authentication Key"
    ui_status "Key" "paste the full public key below"
    printf '\n'
    ui_bold "Public key:"
    printf '\n\n'
    cat "$public_key"
    printf '\n'

    if [[ "$GITHUB_SSH_NON_INTERACTIVE" != "1" && -n "$(browser_open_command)" ]]; then
        if confirm "Open GitHub SSH keys page in your browser?" "y"; then
            open_url "$github_keys_url" || warn "Could not open browser. Open this URL manually: $github_keys_url"
        fi
    fi

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

github_ssh_final_notes() {
    local alias_name="$1" key_file="$2"
    success "GitHub SSH setup completed."
    printf '\n'

    ui_kv "Alias" "$alias_name"
    ui_kv "Private key" "$key_file"
    ui_kv "Public key" "${key_file}.pub"

    ui_bold "How to register the public key in GitHub:"
    cat <<EOF

  1) Open:
     https://github.com/settings/keys
  2) Click "New SSH key".
  3) Title:
     $(hostname 2>/dev/null || printf codevilot)-${alias_name}
  4) Key type:
     Authentication Key
  5) Key:
     paste the full public key printed above.
  6) Click "Add SSH key".

EOF
    ui_bold "Next steps:"
    cat <<EOF

1. Register the public key in GitHub.
2. Verify authentication:
   ssh -T git@${alias_name}
3. Clone using the alias:
   git clone git@${alias_name}:OWNER/REPOSITORY.git
4. If you skip commit author setup now, enter the cloned repository and run:
   codevilot git-author

For curl | bash:
  curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh \\
    | bash -s -- git-author

The alias "${alias_name}" is resolved by the ~/.ssh/config file
on the machine where the git command is executed.
EOF
}

github_ssh_offer_author_setup() {
    local status

    [[ "$GITHUB_SSH_NON_INTERACTIVE" != "1" ]] || return 0
    [[ "$GITHUB_SSH_AUTHOR_OPTIONS" != "1" ]] || return 0

    printf '\n'
    printf '%s %s\n' "$(ui_cyan "[optional]")" "$(ui_bold "Commit author")"
    ui_note "This sets the name and email shown on Git commits."

    if ! confirm "Configure commit author now?" "y"; then
        git_author_skip_message
        return 0
    fi

    GIT_AUTHOR_NAME=""
    GIT_AUTHOR_EMAIL="$GITHUB_SSH_EMAIL"
    GIT_AUTHOR_SCOPE=""
    GIT_AUTHOR_REPO=""
    GIT_AUTHOR_NON_INTERACTIVE=0

    git_author_collect_inputs
    git_author_apply "$GIT_AUTHOR_NAME" "$GIT_AUTHOR_EMAIL" "$GIT_AUTHOR_SCOPE" "$GIT_AUTHOR_REPO" "$GIT_AUTHOR_NON_INTERACTIVE" "$DRY_RUN"
    status=$?
    if [[ "$status" == "2" ]]; then
        git_author_handle_missing_local_repo
    fi

    success "Commit author setup completed."
}

github_ssh_handle_deprecated_author_options() {
    local skipped=0
    [[ "$GITHUB_SSH_AUTHOR_OPTIONS" == "1" ]] || return 0

    cat >&2 <<'EOF'
WARNING: Git author options in github-ssh are deprecated.
Use the separate git-author command instead.
EOF

    if [[ -z "$GITHUB_SSH_NAME" || -z "$GITHUB_SSH_EMAIL" || -z "$GITHUB_SSH_SCOPE" ]]; then
        cat <<'EOF'

[optional] Git author
      Skipped: incomplete deprecated Git author options
EOF
        return 0
    fi

    if [[ "$GITHUB_SSH_SCOPE" == "local" ]] && ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        cat <<'EOF'

[optional] Git author
      Skipped: current directory is not a Git repository

Git local author configuration was skipped because the current
directory is not a Git repository.

After cloning, run:
  curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh | bash -s -- git-author
EOF
        skipped=1
    else
        git_author_apply "$GITHUB_SSH_NAME" "$GITHUB_SSH_EMAIL" "$GITHUB_SSH_SCOPE" "" "$GITHUB_SSH_NON_INTERACTIVE" "$DRY_RUN"
        cat <<EOF

[optional] Git author
      Configured: ${GITHUB_SSH_SCOPE}
EOF
    fi

    if [[ "$skipped" == "1" ]]; then
        printf '\nCompleted with one optional step skipped.\n'
    fi
}

github_ssh_main() {
    github_ssh_parse_args "$@"
    github_ssh_collect_inputs

    ui_step "1" "3" "SSH key"
    github_ssh_prepare_key "$GITHUB_SSH_KEY_FILE"
    ui_status "Ready" "$GITHUB_SSH_KEY_FILE"
    printf '\n'

    ui_step "2" "3" "SSH config"
    github_ssh_write_config "$GITHUB_SSH_ALIAS" "$GITHUB_SSH_KEY_FILE"
    ui_status "Alias" "$GITHUB_SSH_ALIAS"

    github_ssh_handle_deprecated_author_options
    github_ssh_print_public_key "${GITHUB_SSH_KEY_FILE}.pub"

    if [[ "$GITHUB_SSH_RUN_TEST" == "1" ]]; then
        github_ssh_test_run "$GITHUB_SSH_ALIAS" "${GITHUB_SSH_KEY_FILE}.pub" "$DRY_RUN"
    elif [[ "$GITHUB_SSH_NON_INTERACTIVE" != "1" ]]; then
        if confirm "Run GitHub SSH authentication test now?" "n"; then
            github_ssh_test_run "$GITHUB_SSH_ALIAS" "${GITHUB_SSH_KEY_FILE}.pub" "$DRY_RUN"
        fi
    fi

    github_ssh_final_notes "$GITHUB_SSH_ALIAS" "$GITHUB_SSH_KEY_FILE"
    github_ssh_offer_author_setup
}
