#!/usr/bin/env bash
set -u

TEST_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd -P "$TEST_DIR/.." >/dev/null 2>&1 && pwd)"
TEST_TMP_ROOT="${TMPDIR:-/tmp}/codevilot-tests.$$"
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
    export HOME
    mkdir -p "$HOME" "$MOCK_BIN" "$CASE_WORK"
    create_mocks "$MOCK_BIN"
    PATH="$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
    export PATH
    cd "$CASE_WORK" || exit 1
}

create_mocks() {
    local bin_dir="$1"

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

    chmod +x "$bin_dir/ssh-keygen" "$bin_dir/ssh" "$bin_dir/git"
}

run_cli() {
    "$REPO_ROOT/cli.sh" "$@"
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

test_new_ssh_config() {
    setup_case "new-config"
    run_cli github-ssh --alias github-user --email user@example.com --name "GitHub User" --scope global --non-interactive >/dev/null
    assert_file_contains "$HOME/.ssh/config" "Host github-user"
    assert_file_contains "$HOME/.ssh/config" 'IdentityFile "~/.ssh/id_ed25519_user"'
    assert_file_contains "$HOME/.gitconfig.mock" "user.name=GitHub User"
}

test_existing_config_preserved() {
    setup_case "preserve-config"
    mkdir -p "$HOME/.ssh"
    printf 'Host work\n    HostName example.com\n' >"$HOME/.ssh/config"
    run_cli github-ssh --alias github-user --email user@example.com --name "GitHub User" --scope global --non-interactive >/dev/null
    assert_file_contains "$HOME/.ssh/config" "Host work"
    assert_file_contains "$HOME/.ssh/config" "Host github-user"
}

test_no_duplicate_block() {
    setup_case "no-duplicate"
    run_cli github-ssh --alias github-user --email user@example.com --name "GitHub User" --scope global --non-interactive >/dev/null
    run_cli github-ssh --alias github-user --email user@example.com --name "GitHub User" --scope global --non-interactive >/dev/null
    count="$(grep -Fc "# BEGIN codevilot-cli:github-user" "$HOME/.ssh/config")"
    assert_eq "1" "$count"
}

test_multiple_aliases() {
    setup_case "multi-alias"
    run_cli github-ssh --alias github-one --email one@example.com --name "One User" --scope global --non-interactive >/dev/null
    run_cli github-ssh --alias github-two --email two@example.com --name "Two User" --scope global --non-interactive >/dev/null
    assert_file_contains "$HOME/.ssh/config" "Host github-one"
    assert_file_contains "$HOME/.ssh/config" "Host github-two"
}

test_existing_key_not_overwritten() {
    setup_case "existing-key"
    mkdir -p "$HOME/.ssh"
    printf 'ORIGINAL PRIVATE\n' >"$HOME/.ssh/id_ed25519_user"
    printf 'ssh-ed25519 ORIGINAL user@example.com\n' >"$HOME/.ssh/id_ed25519_user.pub"
    run_cli github-ssh --alias github-user --email user@example.com --name "GitHub User" --scope global --non-interactive >/dev/null
    assert_file_contains "$HOME/.ssh/id_ed25519_user" "ORIGINAL PRIVATE"
    assert_file_contains "$HOME/.ssh/id_ed25519_user.pub" "ORIGINAL"
}

test_dry_run_no_file_changes() {
    setup_case "dry-run"
    run_cli github-ssh --alias github-user --email user@example.com --name "GitHub User" --scope global --non-interactive --dry-run >/dev/null
    [[ ! -e "$HOME/.ssh/config" ]]
}

test_local_scope_outside_git_fails() {
    setup_case "local-fail"
    if run_cli github-ssh --alias github-user --email user@example.com --name "GitHub User" --scope local --non-interactive >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

test_non_interactive_missing_args_fails() {
    setup_case "missing-args"
    if run_cli github-ssh --alias github-user --non-interactive >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

test_git_name_with_spaces() {
    setup_case "name-spaces"
    mkdir -p ".git"
    run_cli github-ssh --alias github-user --email user@example.com --name "Baek Namheon Test" --scope local --non-interactive >/dev/null
    assert_file_contains "$PWD/.git/config.mock" "user.name=Baek Namheon Test"
}

test_bad_option_fails() {
    setup_case "bad-option"
    if run_cli github-ssh --bad-option >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

test_help() {
    setup_case "help"
    output="$(run_cli github-ssh --help)"
    printf '%s\n' "$output" | grep -Fq "Usage:"
}

test_config_permissions() {
    setup_case "permissions"
    run_cli github-ssh --alias github-user --email user@example.com --name "GitHub User" --scope global --non-interactive >/dev/null
    assert_eq "700" "$(file_mode "$HOME/.ssh")"
    assert_eq "600" "$(file_mode "$HOME/.ssh/config")"
    assert_eq "600" "$(file_mode "$HOME/.ssh/id_ed25519_user")"
    assert_eq "644" "$(file_mode "$HOME/.ssh/id_ed25519_user.pub")"
}

run_test "new SSH config generation" test_new_ssh_config
run_test "existing SSH config preserved" test_existing_config_preserved
run_test "same alias does not duplicate block" test_no_duplicate_block
run_test "multiple aliases remain independent" test_multiple_aliases
run_test "existing key is not overwritten" test_existing_key_not_overwritten
run_test "dry-run does not write files" test_dry_run_no_file_changes
run_test "local scope outside Git repository fails" test_local_scope_outside_git_fails
run_test "non-interactive missing required args fails" test_non_interactive_missing_args_fails
run_test "Git user name with spaces is handled" test_git_name_with_spaces
run_test "bad option fails" test_bad_option_fails
run_test "github-ssh help works" test_help
run_test "SSH config and key permissions are set" test_config_permissions

printf '\nPassed: %s\nFailed: %s\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
