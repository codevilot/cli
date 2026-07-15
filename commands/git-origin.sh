#!/usr/bin/env bash

: "${SCRIPT_DIR:?SCRIPT_DIR must be set by entry.sh}"

# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=../lib/platform.sh
. "$SCRIPT_DIR/lib/platform.sh"

git_origin_usage() {
    cat <<'EOF'
Usage:
  curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh | bash -s -- git-origin [options]

Update a repository remote URL to use a GitHub SSH alias.

Options:
  --repo <path>             Git repository path
  --alias <ssh-alias>       SSH Host alias
  --owner <owner>           GitHub owner
  --repository <repository> GitHub repository
  --url <remote-url>        Current or desired remote URL
  --remote <remote-name>    Remote name (default: origin)
  --non-interactive         Do not prompt for confirmation
  --dry-run                 Show planned change without modifying files
  --help                    Show this help
EOF
}

git_origin_parse_args() {
    GIT_ORIGIN_REPO=""
    GIT_ORIGIN_ALIAS=""
    GIT_ORIGIN_OWNER=""
    GIT_ORIGIN_REPOSITORY=""
    GIT_ORIGIN_URL=""
    GIT_ORIGIN_REMOTE="origin"
    GIT_ORIGIN_NON_INTERACTIVE=0
    DRY_RUN=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo)
                [[ $# -ge 2 ]] || die "--repo requires a value"
                GIT_ORIGIN_REPO="$2"
                shift 2
                ;;
            --alias)
                [[ $# -ge 2 ]] || die "--alias requires a value"
                GIT_ORIGIN_ALIAS="$2"
                shift 2
                ;;
            --owner)
                [[ $# -ge 2 ]] || die "--owner requires a value"
                GIT_ORIGIN_OWNER="$2"
                shift 2
                ;;
            --repository)
                [[ $# -ge 2 ]] || die "--repository requires a value"
                GIT_ORIGIN_REPOSITORY="$2"
                shift 2
                ;;
            --url)
                [[ $# -ge 2 ]] || die "--url requires a value"
                GIT_ORIGIN_URL="$2"
                shift 2
                ;;
            --remote)
                [[ $# -ge 2 ]] || die "--remote requires a value"
                GIT_ORIGIN_REMOTE="$2"
                shift 2
                ;;
            --non-interactive)
                GIT_ORIGIN_NON_INTERACTIVE=1
                shift
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --help|-h)
                git_origin_usage
                exit 0
                ;;
            *)
                die "Unknown option for git-origin: $1"
                ;;
        esac
    done
}

git_origin_is_repo() {
    local repo_path="$1"
    if [[ -n "$repo_path" ]]; then
        git -C "$repo_path" rev-parse --is-inside-work-tree >/dev/null 2>&1
    else
        git rev-parse --is-inside-work-tree >/dev/null 2>&1
    fi
}

git_origin_git() {
    local repo_path="$1"
    shift
    if [[ -n "$repo_path" ]]; then
        git -C "$repo_path" "$@"
    else
        git "$@"
    fi
}

git_origin_extract_owner_repo() {
    local url="$1"
    local path_part
    case "$url" in
        git@github.com:*)
            path_part="${url#git@github.com:}"
            ;;
        git@*:*)
            path_part="${url#git@*:}"
            ;;
        https://github.com/*)
            path_part="${url#https://github.com/}"
            ;;
        *)
            return 1
            ;;
    esac
    path_part="${path_part%.git}"
    GIT_ORIGIN_OWNER="${GIT_ORIGIN_OWNER:-${path_part%%/*}}"
    GIT_ORIGIN_REPOSITORY="${GIT_ORIGIN_REPOSITORY:-${path_part#*/}}"
    [[ -n "$GIT_ORIGIN_OWNER" && -n "$GIT_ORIGIN_REPOSITORY" && "$GIT_ORIGIN_REPOSITORY" != "$path_part" ]]
}

git_origin_main() {
    local repo_path old_url new_url
    git_origin_parse_args "$@"

    have_command git || die "git command not found"
    [[ -n "$GIT_ORIGIN_ALIAS" ]] || GIT_ORIGIN_ALIAS="$(prompt_required "GitHub SSH alias:")"

    repo_path="$GIT_ORIGIN_REPO"
    if [[ -n "$repo_path" ]]; then
        repo_path="$(absolute_path "$repo_path")"
    fi
    git_origin_is_repo "$repo_path" || die "Not a Git repository: ${repo_path:-$PWD}"

    if [[ -n "$GIT_ORIGIN_URL" ]]; then
        old_url="$GIT_ORIGIN_URL"
    else
        old_url="$(git_origin_git "$repo_path" remote get-url "$GIT_ORIGIN_REMOTE" 2>/dev/null)" || die "Remote not found: $GIT_ORIGIN_REMOTE"
    fi

    if [[ -z "$GIT_ORIGIN_OWNER" || -z "$GIT_ORIGIN_REPOSITORY" ]]; then
        git_origin_extract_owner_repo "$old_url" || die "Could not infer owner and repository from remote URL: $old_url"
    fi

    new_url="git@${GIT_ORIGIN_ALIAS}:${GIT_ORIGIN_OWNER}/${GIT_ORIGIN_REPOSITORY}.git"

    cat <<EOF
Current ${GIT_ORIGIN_REMOTE} URL:
  ${old_url}

New ${GIT_ORIGIN_REMOTE} URL:
  ${new_url}
EOF

    if [[ "$GIT_ORIGIN_NON_INTERACTIVE" != "1" ]]; then
        confirm "Update ${GIT_ORIGIN_REMOTE}?" "n" || die "Canceled"
    fi

    if [[ "$DRY_RUN" == "1" ]]; then
        printf '[dry-run] git'
        [[ -n "$repo_path" ]] && printf ' -C %q' "$repo_path"
        printf ' remote set-url %q %q\n' "$GIT_ORIGIN_REMOTE" "$new_url"
        return 0
    fi

    git_origin_git "$repo_path" remote set-url "$GIT_ORIGIN_REMOTE" "$new_url"
    success "Git origin setup completed."
}
