#!/usr/bin/env bash
set -u

TEST_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd -P "$TEST_DIR/.." >/dev/null 2>&1 && pwd)"
TEST_TMP_ROOT="${TMPDIR:-/tmp}/codevilot-tests.$$"
REAL_HOME="${HOME:-}"
PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
    rm -rf "$TEST_TMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$TEST_TMP_ROOT"

fail() {
    printf 'not ok - %s\n' "$1" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

pass() {
    printf 'ok - %s\n' "$1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

assert_file_contains() {
    local file="$1"
    local expected="$2"
    grep -Fq "$expected" "$file" || {
        printf 'Expected %s to contain: %s\n' "$file" "$expected" >&2
        return 1
    }
}

assert_file_not_contains() {
    local file="$1"
    local unexpected="$2"
    ! grep -Fq "$unexpected" "$file" || {
        printf 'Expected %s not to contain: %s\n' "$file" "$unexpected" >&2
        return 1
    }
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    [[ "$expected" == "$actual" ]] || {
        printf 'Expected: %s\nActual:   %s\n' "$expected" "$actual" >&2
        return 1
    }
}

file_mode() {
    local file="$1"
    if stat -c '%a' "$file" >/dev/null 2>&1; then
        stat -c '%a' "$file"
    else
        stat -f '%Lp' "$file"
    fi
}

setup_case() {
    local name="$1"
    CASE_DIR="$TEST_TMP_ROOT/$name"
    HOME="$CASE_DIR/home"
    MOCK_BIN="$CASE_DIR/bin"
    CASE_WORK="$CASE_DIR/work"
    MOCK_RAW_ROOT="$CASE_DIR/raw"
    TTY_INPUT="$CASE_DIR/tty.in"
    TTY_OUTPUT="$CASE_DIR/tty.out"
    export HOME MOCK_RAW_ROOT
    mkdir -p "$HOME" "$MOCK_BIN" "$CASE_WORK" "$MOCK_RAW_ROOT" "$CASE_DIR/tmp"
    create_raw_tree "$MOCK_RAW_ROOT"
    create_mocks "$MOCK_BIN"
    PATH="$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
    TMPDIR="$CASE_DIR/tmp"
    CODEVILOT_RAW_BASE_URL="https://mock.local/codevilot"
    unset CODEVILOT_TTY_INPUT_FILE CODEVILOT_TTY_OUTPUT_FILE CODEVILOT_TTY_PATH
    export PATH TMPDIR CODEVILOT_RAW_BASE_URL
    cd "$CASE_WORK" || exit 1
}

create_raw_tree() {
    local raw_root="$1"
    mkdir -p "$raw_root/lib" "$raw_root/commands"
    cp "$REPO_ROOT/lib/common.sh" "$raw_root/lib/common.sh"
    cp "$REPO_ROOT/lib/platform.sh" "$raw_root/lib/platform.sh"
    cp "$REPO_ROOT/commands/github-ssh.sh" "$raw_root/commands/github-ssh.sh"
}

create_mocks() {
    local bin_dir="$1"

    cat >"$bin_dir/curl" <<'EOF'
#!/usr/bin/env bash
set -u
destination=""
url=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o)
            destination="$2"
            shift 2
            ;;
        -*)
            shift
            ;;
        *)
            url="$1"
            shift
            ;;
    esac
done
[[ -n "$destination" && -n "$url" ]] || exit 2
relative="${url#https://mock.local/codevilot/}"
source_file="$MOCK_RAW_ROOT/$relative"
[[ -f "$source_file" ]] || exit 22
cp "$source_file" "$destination"
EOF

    cat >"$bin_dir/ssh-keygen" <<'EOF'
#!/usr/bin/env bash
set -u
key_file=""
comment=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f) key_file="$2"; shift 2 ;;
        -C) comment="$2"; shift 2 ;;
        *) shift ;;
    esac
done
[[ -n "$key_file" ]] || exit 2
if [[ -e "$key_file" || -e "${key_file}.pub" ]]; then
    echo "refusing to overwrite" >&2
    exit 1
fi
mkdir -p "$(dirname "$key_file")"
printf 'PRIVATE KEY FOR TEST\n' >"$key_file"
printf 'ssh-ed25519 AAAATEST %s\n' "$comment" >"${key_file}.pub"
EOF

    cat >"$bin_dir/ssh" <<'EOF'
#!/usr/bin/env bash
set -u
case "${1:-}" in
    -G)
        echo "hostname github.com"
        exit 0
        ;;
    -T)
        echo "Hi github-user! You've successfully authenticated, but GitHub does not provide shell access."
        exit 1
        ;;
esac
exit 0
EOF

    cat >"$bin_dir/git" <<'EOF'
#!/usr/bin/env bash
set -u

global_file="$HOME/.gitconfig.mock"
local_file="$PWD/.git/config.mock"

get_value() {
    local file="$1"
    local key="$2"
    [[ -f "$file" ]] || return 1
    sed -n "s/^${key}=//p" "$file" | tail -n 1
}

set_value() {
    local file="$1"
    local key="$2"
    local value="$3"
    mkdir -p "$(dirname "$file")"
    if [[ -f "$file" ]]; then
        grep -Fv "${key}=" "$file" >"${file}.tmp" || true
        mv "${file}.tmp" "$file"
    fi
    printf '%s=%s\n' "$key" "$value" >>"$file"
}

if [[ "${1:-}" == "rev-parse" && "${2:-}" == "--is-inside-work-tree" ]]; then
    [[ -d "$PWD/.git" ]] && { echo true; exit 0; }
    exit 128
fi

if [[ "${1:-}" == "config" ]]; then
    shift
    scope_file="$local_file"
    if [[ "${1:-}" == "--global" ]]; then
        scope_file="$global_file"
        shift
    fi
    key="${1:-}"
    value="${2:-}"
    if [[ -z "$key" ]]; then
        exit 2
    fi
    if [[ -z "$value" ]]; then
        get_value "$scope_file" "$key"
        exit 0
    fi
    set_value "$scope_file" "$key" "$value"
    exit 0
fi

exit 0
EOF

    chmod +x "$bin_dir/curl" "$bin_dir/ssh-keygen" "$bin_dir/ssh" "$bin_dir/git"
}

run_entry() {
    bash "$REPO_ROOT/entry.sh" "$@"
}

run_test() {
    local name="$1"
    shift
    if "$@"; then
        pass "$name"
    else
        fail "$name"
    fi
}

test_bash_syntax() {
    bash -n "$REPO_ROOT/entry.sh"
    bash -n "$REPO_ROOT"/commands/*.sh
    bash -n "$REPO_ROOT"/lib/*.sh
    bash -n "$REPO_ROOT"/tests/*.sh
}

test_entry_downloads_required_files() {
    setup_case "download-required"
    output="$(run_entry help)"
    printf '%s\n' "$output" | grep -Fq "Available commands:"
}

test_download_failure_exits() {
    setup_case "download-failure"
    rm -f "$MOCK_RAW_ROOT/lib/platform.sh"
    if run_entry help >/dev/null 2>&1; then
        return 1
    fi
}

test_empty_download_rejected() {
    setup_case "empty-download"
    : >"$MOCK_RAW_ROOT/lib/platform.sh"
    if run_entry help >/dev/null 2>&1; then
        return 1
    fi
}

test_syntax_error_source_rejected() {
    setup_case "syntax-error"
    printf 'if then\n' >"$MOCK_RAW_ROOT/lib/platform.sh"
    if run_entry help >/dev/null 2>&1; then
        return 1
    fi
}

test_menu_runs_without_args() {
    setup_case "menu-help"
    printf '2\n' >"$TTY_INPUT"
    CODEVILOT_TTY_INPUT_FILE="$TTY_INPUT" CODEVILOT_TTY_OUTPUT_FILE="$TTY_OUTPUT" run_entry >/dev/null
    assert_file_contains "$TTY_OUTPUT" "codevilot CLI"
}

test_menu_one_runs_github_ssh() {
    setup_case "menu-github-ssh"
    printf '1\ngithub-menu\nmenu@example.com\nMenu User\n\nglobal\nn\n' >"$TTY_INPUT"
    CODEVILOT_TTY_INPUT_FILE="$TTY_INPUT" CODEVILOT_TTY_OUTPUT_FILE="$TTY_OUTPUT" run_entry >/dev/null
    assert_file_contains "$HOME/.ssh/config" "Host github-menu"
    assert_file_contains "$HOME/.gitconfig.mock" "user.email=menu@example.com"
}

test_invalid_menu_reprompts() {
    setup_case "menu-invalid"
    printf '9\n0\n' >"$TTY_INPUT"
    CODEVILOT_TTY_INPUT_FILE="$TTY_INPUT" CODEVILOT_TTY_OUTPUT_FILE="$TTY_OUTPUT" run_entry >/dev/null
    assert_file_contains "$TTY_OUTPUT" "Invalid selection: 9"
}

test_menu_zero_exits() {
    setup_case "menu-zero"
    printf '0\n' >"$TTY_INPUT"
    CODEVILOT_TTY_INPUT_FILE="$TTY_INPUT" CODEVILOT_TTY_OUTPUT_FILE="$TTY_OUTPUT" run_entry
}

test_no_tty_error() {
    setup_case "no-tty"
    CODEVILOT_TTY_PATH="$CASE_DIR/no-tty" run_entry >/dev/null 2>"$CASE_DIR/err" && return 1
    assert_file_contains "$CASE_DIR/err" "Interactive terminal is unavailable."
}

test_direct_github_ssh() {
    setup_case "direct-github-ssh"
    run_entry github-ssh --alias github-user --email user@example.com --name "GitHub User" --scope global --non-interactive >/dev/null
    assert_file_contains "$HOME/.ssh/config" "Host github-user"
    assert_file_contains "$HOME/.gitconfig.mock" "user.name=GitHub User"
}

test_help_forwarded() {
    setup_case "help-forwarded"
    output="$(run_entry github-ssh --help)"
    printf '%s\n' "$output" | grep -Fq "Usage:"
}

test_unknown_command_exit_code() {
    setup_case "unknown-command"
    run_entry nope >/dev/null 2>&1
    status=$?
    assert_eq "2" "$status"
}

test_temp_cleanup() {
    setup_case "temp-cleanup"
    run_entry help >/dev/null
    count="$(find "$TMPDIR" -maxdepth 1 -type d -name 'codevilot.*' | wc -l | tr -d ' ')"
    assert_eq "0" "$count"
}

test_real_home_not_modified() {
    setup_case "home-safe"
    run_entry github-ssh --alias github-user --email user@example.com --name "GitHub User" --scope global --non-interactive --dry-run >/dev/null
    [[ ! -e "$HOME/.ssh/config" ]]
    [[ -z "$REAL_HOME" || "$HOME" != "$REAL_HOME" ]]
}

test_dry_run_no_file_changes() {
    setup_case "dry-run"
    run_entry github-ssh --alias github-user --email user@example.com --name "GitHub User" --scope global --non-interactive --dry-run >/dev/null
    [[ ! -e "$HOME/.ssh/config" ]]
}

test_no_duplicate_block() {
    setup_case "no-duplicate"
    run_entry github-ssh --alias github-user --email user@example.com --name "GitHub User" --scope global --non-interactive >/dev/null
    run_entry github-ssh --alias github-user --email user@example.com --name "GitHub User" --scope global --non-interactive >/dev/null
    count="$(grep -Fc "# BEGIN codevilot-cli:github-user" "$HOME/.ssh/config")"
    assert_eq "1" "$count"
}

test_existing_config_preserved() {
    setup_case "preserve-config"
    mkdir -p "$HOME/.ssh"
    printf 'Host work\n    HostName example.com\n' >"$HOME/.ssh/config"
    run_entry github-ssh --alias github-user --email user@example.com --name "GitHub User" --scope global --non-interactive >/dev/null
    assert_file_contains "$HOME/.ssh/config" "Host work"
    assert_file_contains "$HOME/.ssh/config" "Host github-user"
}

test_existing_key_not_overwritten() {
    setup_case "existing-key"
    mkdir -p "$HOME/.ssh"
    printf 'ORIGINAL PRIVATE\n' >"$HOME/.ssh/id_ed25519_user"
    printf 'ssh-ed25519 ORIGINAL user@example.com\n' >"$HOME/.ssh/id_ed25519_user.pub"
    run_entry github-ssh --alias github-user --email user@example.com --name "GitHub User" --scope global --non-interactive >/dev/null
    assert_file_contains "$HOME/.ssh/id_ed25519_user" "ORIGINAL PRIVATE"
    assert_file_contains "$HOME/.ssh/id_ed25519_user.pub" "ORIGINAL"
}

test_local_scope_outside_git_fails() {
    setup_case "local-fail"
    if run_entry github-ssh --alias github-user --email user@example.com --name "GitHub User" --scope local --non-interactive >/dev/null 2>&1; then
        return 1
    fi
}

test_permissions() {
    setup_case "permissions"
    run_entry github-ssh --alias github-user --email user@example.com --name "GitHub User" --scope global --non-interactive >/dev/null
    assert_eq "700" "$(file_mode "$HOME/.ssh")"
    assert_eq "600" "$(file_mode "$HOME/.ssh/config")"
    assert_eq "600" "$(file_mode "$HOME/.ssh/id_ed25519_user")"
    assert_eq "644" "$(file_mode "$HOME/.ssh/id_ed25519_user.pub")"
}

run_test "entry.sh Bash syntax check" test_bash_syntax
run_test "required lib and command files download" test_entry_downloads_required_files
run_test "download failure exits" test_download_failure_exits
run_test "empty downloaded file is rejected" test_empty_download_rejected
run_test "syntax error file is not sourced" test_syntax_error_source_rejected
run_test "no-argument menu displays" test_menu_runs_without_args
run_test "menu selection 1 runs github-ssh" test_menu_one_runs_github_ssh
run_test "invalid menu input reprompts" test_invalid_menu_reprompts
run_test "menu selection 0 exits" test_menu_zero_exits
run_test "missing tty gives clear error" test_no_tty_error
run_test "direct github-ssh subcommand works" test_direct_github_ssh
run_test "github-ssh --help is forwarded" test_help_forwarded
run_test "unknown command exits with code 2" test_unknown_command_exit_code
run_test "temporary directory is cleaned up" test_temp_cleanup
run_test "real HOME and Git config are not modified" test_real_home_not_modified
run_test "github-ssh --dry-run changes no files" test_dry_run_no_file_changes
run_test "same alias does not duplicate block" test_no_duplicate_block
run_test "existing SSH config is preserved" test_existing_config_preserved
run_test "existing key is not overwritten" test_existing_key_not_overwritten
run_test "local scope outside Git repository fails" test_local_scope_outside_git_fails
run_test "SSH config and key permissions are set" test_permissions

printf '\nPassed: %s\nFailed: %s\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
