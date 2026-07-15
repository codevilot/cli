#!/usr/bin/env bash

: "${SCRIPT_DIR:?SCRIPT_DIR must be set by entry.sh}"

# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=../lib/platform.sh
. "$SCRIPT_DIR/lib/platform.sh"

git_author_usage() {
    cat <<'EOF'
Usage:
  curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh | bash -s -- git-author [options]

Configure Git commit author.

Options:
  --name <name>             Git commit author name
  --email <email>           Git commit author email
  --scope <local|global>    Git config scope
  --repo <path>             Git repository path for local scope
  --non-interactive         Do not prompt; fail when required values are missing
  --dry-run                 Show planned changes without modifying files
  --help                    Show this help
EOF
}

git_author_parse_args() {
    GIT_AUTHOR_NAME=""
    GIT_AUTHOR_EMAIL=""
    GIT_AUTHOR_SCOPE=""
    GIT_AUTHOR_REPO=""
    GIT_AUTHOR_NON_INTERACTIVE=0
    DRY_RUN=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                [[ $# -ge 2 ]] || die "--name requires a value"
                GIT_AUTHOR_NAME="$2"
                shift 2
                ;;
            --email)
                [[ $# -ge 2 ]] || die "--email requires a value"
                GIT_AUTHOR_EMAIL="$2"
                shift 2
                ;;
            --scope)
                [[ $# -ge 2 ]] || die "--scope requires a value"
                GIT_AUTHOR_SCOPE="$2"
                shift 2
                ;;
            --repo)
                [[ $# -ge 2 ]] || die "--repo requires a value"
                GIT_AUTHOR_REPO="$2"
                shift 2
                ;;
            --non-interactive)
                GIT_AUTHOR_NON_INTERACTIVE=1
                shift
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --help|-h)
                git_author_usage
                exit 0
                ;;
            *)
                die "Unknown option for git-author: $1"
                ;;
        esac
    done
}

git_author_is_repo() {
    local repo_path="$1"
    if [[ -n "$repo_path" ]]; then
        git -C "$repo_path" rev-parse --is-inside-work-tree >/dev/null 2>&1
    else
        git rev-parse --is-inside-work-tree >/dev/null 2>&1
    fi
}

git_author_set() {
    local scope="$1" repo_path="$2" key="$3" value="$4"
    if [[ "$DRY_RUN" == "1" ]]; then
        if [[ "$scope" == "global" ]]; then
            printf '[dry-run] git config --global %q %q\n' "$key" "$value"
        elif [[ -n "$repo_path" ]]; then
            printf '[dry-run] git -C %q config --local %q %q\n' "$repo_path" "$key" "$value"
        else
            printf '[dry-run] git config --local %q %q\n' "$key" "$value"
        fi
        return 0
    fi

    if [[ "$scope" == "global" ]]; then
        git config --global "$key" "$value"
    elif [[ -n "$repo_path" ]]; then
        git -C "$repo_path" config --local "$key" "$value"
    else
        git config --local "$key" "$value"
    fi
}

git_author_apply() {
    local name="$1" email="$2" scope="$3" repo_path="$4" non_interactive="$5" dry_run="$6"
    local linux_user
    DRY_RUN="$dry_run"

    have_command git || die "git command not found"

    case "$scope" in
        local|global) ;;
        *) die "--scope must be local or global" ;;
    esac

    if [[ "$scope" == "local" ]]; then
        if [[ -n "$repo_path" ]]; then
            repo_path="$(absolute_path "$repo_path")"
            git_author_is_repo "$repo_path" || die "Not a Git repository: $repo_path"
        elif ! git_author_is_repo ""; then
            if [[ "$non_interactive" == "1" ]]; then
                cat >&2 <<'EOF'
ERROR: --scope local requires a Git repository.
Provide --repo <path> or run the command inside a repository.
EOF
                exit 1
            fi
            return 2
        fi
    fi

    if [[ "$scope" == "global" && "$non_interactive" != "1" ]]; then
        linux_user="${USER:-$(id -un 2>/dev/null || printf unknown)}"
        printf 'This will affect all repositories used by Linux user "%s".\n' "$linux_user"
        confirm "Continue?" "n" || die "Canceled"
    fi

    git_author_set "$scope" "$repo_path" user.name "$name"
    git_author_set "$scope" "$repo_path" user.email "$email"
}

git_author_collect_inputs() {
    GIT_AUTHOR_NAME="$(trim "$GIT_AUTHOR_NAME")"
    GIT_AUTHOR_EMAIL="$(trim "$GIT_AUTHOR_EMAIL")"
    GIT_AUTHOR_SCOPE="$(trim "$GIT_AUTHOR_SCOPE")"

    if [[ "$GIT_AUTHOR_NON_INTERACTIVE" == "1" ]]; then
        [[ -n "$GIT_AUTHOR_NAME" ]] || die "--name is required in --non-interactive mode"
        [[ -n "$GIT_AUTHOR_EMAIL" ]] || die "--email is required in --non-interactive mode"
        [[ -n "$GIT_AUTHOR_SCOPE" ]] || die "--scope is required in --non-interactive mode"
    else
        [[ -n "$GIT_AUTHOR_NAME" ]] || GIT_AUTHOR_NAME="$(prompt_required "Git commit author name:")"
        [[ -n "$GIT_AUTHOR_EMAIL" ]] || GIT_AUTHOR_EMAIL="$(prompt_required "Git commit author email:")"
        while [[ -z "$GIT_AUTHOR_SCOPE" ]]; do
            GIT_AUTHOR_SCOPE="$(prompt_default "Git config scope" "local")"
            case "$GIT_AUTHOR_SCOPE" in
                local|global) ;;
                *)
                    warn "Scope must be local or global."
                    GIT_AUTHOR_SCOPE=""
                    ;;
            esac
        done
    fi

    case "$GIT_AUTHOR_SCOPE" in
        local|global) ;;
        *) die "--scope must be local or global" ;;
    esac
}

git_author_skip_message() {
    cat <<'EOF'
Git author setup was skipped.

After cloning a repository, run:

cd /path/to/repository

curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh \
  | bash -s -- git-author
EOF
}

git_author_handle_missing_local_repo() {
    local selection repo_path
    cat <<'EOF'
The current directory is not a Git repository.

  1) Enter a Git repository path
  2) Configure globally instead
  3) Skip Git author setup
  0) Cancel

EOF
    selection="$(read_from_tty "Enter selection: ")" || die "Canceled"
    selection="$(trim "$selection")"
    case "$selection" in
        1)
            repo_path="$(prompt_required "Git repository path:")"
            repo_path="$(absolute_path "$repo_path")"
            git_author_is_repo "$repo_path" || die "Not a Git repository: $repo_path"
            git_author_apply "$GIT_AUTHOR_NAME" "$GIT_AUTHOR_EMAIL" local "$repo_path" "$GIT_AUTHOR_NON_INTERACTIVE" "$DRY_RUN"
            ;;
        2)
            git_author_apply "$GIT_AUTHOR_NAME" "$GIT_AUTHOR_EMAIL" global "" "$GIT_AUTHOR_NON_INTERACTIVE" "$DRY_RUN"
            ;;
        3)
            git_author_skip_message
            return 0
            ;;
        0)
            die "Canceled"
            ;;
        *)
            warn "Invalid selection: $selection"
            git_author_handle_missing_local_repo
            ;;
    esac
}

git_author_main() {
    local status
    git_author_parse_args "$@"
    git_author_collect_inputs

    git_author_apply "$GIT_AUTHOR_NAME" "$GIT_AUTHOR_EMAIL" "$GIT_AUTHOR_SCOPE" "$GIT_AUTHOR_REPO" "$GIT_AUTHOR_NON_INTERACTIVE" "$DRY_RUN"
    status=$?
    if [[ "$status" == "2" ]]; then
        git_author_handle_missing_local_repo
    fi

    success "Git author setup completed."
}
