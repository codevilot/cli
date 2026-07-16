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
        exit 1
    }
}

assert_file_not_contains() {
    local file="$1"
    local unexpected="$2"
    ! grep -Fq "$unexpected" "$file" || {
        printf 'Expected %s not to contain: %s\n' "$file" "$unexpected" >&2
        exit 1
    }
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    [[ "$expected" == "$actual" ]] || {
        printf 'Expected: %s\nActual:   %s\n' "$expected" "$actual" >&2
        exit 1
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
    BROWSER_OPEN_LOG="$CASE_DIR/browser-open.log"
    CODEVILOT_DISABLE_CLIPBOARD=1
    unset CODEVILOT_TTY_INPUT_FILE CODEVILOT_TTY_OUTPUT_FILE CODEVILOT_TTY_PATH SSH_MOCK_MODE
    export PATH TMPDIR CODEVILOT_RAW_BASE_URL CODEVILOT_DISABLE_CLIPBOARD BROWSER_OPEN_LOG
    cd "$CASE_WORK" || exit 1
}

create_raw_tree() {
    local raw_root="$1"
    mkdir -p "$raw_root/lib" "$raw_root/commands"
    cp "$REPO_ROOT"/lib/*.sh "$raw_root/lib/"
    cp "$REPO_ROOT"/commands/*.sh "$raw_root/commands/"
}

create_repo() {
    local repo_path="$1"
    mkdir -p "$repo_path/.git"
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

    cat >"$bin_dir/xdg-open" <<'EOF'
#!/usr/bin/env bash
set -u
printf '%s\n' "${1:-}" >>"$BROWSER_OPEN_LOG"
EOF
    cp "$bin_dir/xdg-open" "$bin_dir/open"
    cp "$bin_dir/xdg-open" "$bin_dir/wslview"

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
if [[ "${SSH_KEYGEN_FAIL:-0}" == "1" ]]; then
    echo "ssh-keygen failed" >&2
    exit 1
fi
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
        if [[ "${SSH_MOCK_MODE:-}" == "config-fail" ]]; then
            echo "bad config" >&2
            exit 255
        fi
        echo "hostname github.com"
        exit 0
        ;;
    -T)
        if [[ "${SSH_MOCK_MODE:-}" == "reject" ]]; then
            echo "git@github.com: Permission denied (publickey)."
            exit 255
        fi
        echo "Hi codevilot! You've successfully authenticated, but GitHub does not provide shell access."
        exit 1
        ;;
esac
exit 0
EOF

    cat >"$bin_dir/git" <<'EOF'
#!/usr/bin/env bash
set -u

repo=""
if [[ "${1:-}" == "-C" ]]; then
    repo="$2"
    shift 2
fi
work_dir="${repo:-$PWD}"
global_file="$HOME/.gitconfig.mock"
local_file="$work_dir/.git/config.mock"
remote_file="$work_dir/.git/remotes.mock"

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

is_repo() {
    [[ -d "$work_dir/.git" ]]
}

if [[ "${1:-}" == "rev-parse" && "${2:-}" == "--is-inside-work-tree" ]]; then
    is_repo && { echo true; exit 0; }
    exit 128
fi

if [[ "${1:-}" == "config" ]]; then
    shift
    scope_file="$local_file"
    if [[ "${1:-}" == "--global" ]]; then
        scope_file="$global_file"
        shift
    elif [[ "${1:-}" == "--local" ]]; then
        shift
    fi
    key="${1:-}"
    value="${2:-}"
    [[ -n "$key" ]] || exit 2
    if [[ -z "$value" ]]; then
        get_value "$scope_file" "$key"
        exit 0
    fi
    set_value "$scope_file" "$key" "$value"
    exit 0
fi

if [[ "${1:-}" == "remote" ]]; then
    shift
    case "${1:-}" in
        get-url)
            remote="${2:-origin}"
            get_value "$remote_file" "$remote"
            exit $?
            ;;
        set-url)
            remote="${2:-origin}"
            url="${3:-}"
            [[ -n "$url" ]] || exit 2
            set_value "$remote_file" "$remote" "$url"
            exit 0
            ;;
    esac
fi

exit 0
EOF

    chmod +x "$bin_dir/curl" "$bin_dir/xdg-open" "$bin_dir/open" "$bin_dir/wslview" "$bin_dir/ssh-keygen" "$bin_dir/ssh" "$bin_dir/git"
}

run_entry() {
    bash "$REPO_ROOT/entry.sh" "$@"
}

run_test() {
    local name="$1"
    shift
    if ( set -e; "$@" ); then
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
    printf '%s\n' "$output" | grep -Fq "github-ssh-test"
    printf '%s\n' "$output" | grep -Fq "wifi-survey"
}

test_download_failure_exits() {
    setup_case "download-failure"
    rm -f "$MOCK_RAW_ROOT/commands/git-author.sh"
    if run_entry help >/dev/null 2>&1; then
        return 1
    fi
}

test_menu_runs_without_args() {
    setup_case "menu-help"
    printf '2\n' >"$TTY_INPUT"
    CODEVILOT_TTY_INPUT_FILE="$TTY_INPUT" CODEVILOT_TTY_OUTPUT_FILE="$TTY_OUTPUT" run_entry >/dev/null
    assert_file_contains "$TTY_OUTPUT" "Select a category:"
    assert_file_contains "$TTY_OUTPUT" "1) GitHub"
    assert_file_contains "$TTY_OUTPUT" "2) Network"
}

test_network_submenu_displays() {
    setup_case "menu-network"
    printf '2\n0\n0\n' >"$TTY_INPUT"
    CODEVILOT_TTY_INPUT_FILE="$TTY_INPUT" CODEVILOT_TTY_OUTPUT_FILE="$TTY_OUTPUT" run_entry >/dev/null
    assert_file_contains "$TTY_OUTPUT" "Network"
    assert_file_contains "$TTY_OUTPUT" "Wi-Fi channel utilization"
    assert_file_contains "$TTY_OUTPUT" "Wi-Fi active utilization watch"
    assert_file_contains "$TTY_OUTPUT" "Wi-Fi all utilization watch"
}

test_github_submenu_displays() {
    setup_case "menu-github"
    printf '1\n0\n0\n' >"$TTY_INPUT"
    CODEVILOT_TTY_INPUT_FILE="$TTY_INPUT" CODEVILOT_TTY_OUTPUT_FILE="$TTY_OUTPUT" run_entry >/dev/null
    assert_file_contains "$TTY_OUTPUT" "GitHub"
    assert_file_contains "$TTY_OUTPUT" "GitHub SSH setup"
    assert_file_contains "$TTY_OUTPUT" "Configure commit author only"
    assert_file_contains "$TTY_OUTPUT" "Verify GitHub SSH authentication"
}

test_invalid_menu_reprompts() {
    setup_case "menu-invalid"
    printf '9\n0\n' >"$TTY_INPUT"
    CODEVILOT_TTY_INPUT_FILE="$TTY_INPUT" CODEVILOT_TTY_OUTPUT_FILE="$TTY_OUTPUT" run_entry >/dev/null
    assert_file_contains "$TTY_OUTPUT" "Invalid selection: 9"
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

test_github_ssh_home_success() {
    setup_case "github-ssh-home"
    output="$(run_entry github-ssh --alias github-codevilot --email namhundred@naver.com --non-interactive)"
    assert_file_contains "$HOME/.ssh/config" "Host github-codevilot"
    assert_file_contains "$HOME/.ssh/id_ed25519_codevilot.pub" "ssh-ed25519"
    printf '%s\n' "$output" | grep -Fq "GitHub SSH setup completed."
    printf '%s\n' "$output" | grep -Fq "https://github.com/settings/keys"
    printf '%s\n' "$output" | grep -Fq "Public key:"
}

test_github_ssh_local_scope_outside_git_skips_zero() {
    setup_case "github-ssh-local-skip"
    output="$(run_entry github-ssh --alias github-codevilot --email namhundred@naver.com --name codevilot --scope local --non-interactive)"
    status=$?
    assert_eq "0" "$status"
    assert_file_contains "$HOME/.ssh/config" "Host github-codevilot"
    printf '%s\n' "$output" | grep -Fq "Skipped: current directory is not a Git repository"
}

test_github_ssh_interactive_configures_author_by_default() {
    setup_case "github-ssh-author-default"
    create_repo "$CASE_WORK"
    printf '\n\nn\n\ncodevilot\n\n' >"$TTY_INPUT"
    CODEVILOT_TTY_INPUT_FILE="$TTY_INPUT" CODEVILOT_TTY_OUTPUT_FILE="$TTY_OUTPUT" run_entry github-ssh --alias github-codevilot --email namhundred@naver.com >/dev/null
    assert_file_contains "$CASE_WORK/.git/config.mock" "user.name=codevilot"
    assert_file_contains "$CASE_WORK/.git/config.mock" "user.email=namhundred@naver.com"
    assert_file_contains "$TTY_OUTPUT" "Configure commit author now? [Y/n]"
    assert_file_contains "$BROWSER_OPEN_LOG" "https://github.com/settings/keys"
}

test_ssh_failure_nonzero() {
    setup_case "ssh-failure"
    SSH_KEYGEN_FAIL=1 run_entry github-ssh --alias github-codevilot --email user@example.com --non-interactive >/dev/null 2>&1
    status=$?
    [[ "$status" -ne 0 ]]
}

test_git_author_local_inside_repo() {
    setup_case "git-author-local"
    create_repo "$CASE_WORK"
    run_entry git-author --name codevilot --email namhundred@naver.com --scope local --non-interactive >/dev/null
    assert_file_contains "$CASE_WORK/.git/config.mock" "user.name=codevilot"
    assert_file_contains "$CASE_WORK/.git/config.mock" "user.email=namhundred@naver.com"
}

test_git_author_repo_path() {
    setup_case "git-author-repo"
    repo="$CASE_DIR/repo"
    create_repo "$repo"
    run_entry git-author --name codevilot --email namhundred@naver.com --scope local --repo "$repo" --non-interactive >/dev/null
    assert_file_contains "$repo/.git/config.mock" "user.email=namhundred@naver.com"
}

test_git_author_bad_repo() {
    setup_case "git-author-bad-repo"
    if run_entry git-author --name codevilot --email n@example.com --scope local --repo "$CASE_DIR/nope" --non-interactive >/dev/null 2>&1; then
        return 1
    fi
}

test_git_author_global_confirm() {
    setup_case "git-author-global-confirm"
    printf 'y\n' >"$TTY_INPUT"
    CODEVILOT_TTY_INPUT_FILE="$TTY_INPUT" CODEVILOT_TTY_OUTPUT_FILE="$TTY_OUTPUT" run_entry git-author --name codevilot --email n@example.com --scope global >/dev/null
    assert_file_contains "$HOME/.gitconfig.mock" "user.name=codevilot"
    assert_file_contains "$TTY_OUTPUT" "Continue? [y/N]"
}

test_git_author_noninteractive_local_missing_repo() {
    setup_case "git-author-missing-repo"
    if run_entry git-author --name codevilot --email n@example.com --scope local --non-interactive >/dev/null 2>"$CASE_DIR/err"; then
        return 1
    fi
    assert_file_contains "$CASE_DIR/err" "ERROR: --scope local requires a Git repository."
}

test_existing_key_not_overwritten() {
    setup_case "existing-key"
    mkdir -p "$HOME/.ssh"
    printf 'ORIGINAL PRIVATE\n' >"$HOME/.ssh/id_ed25519_codevilot"
    printf 'ssh-ed25519 ORIGINAL user@example.com\n' >"$HOME/.ssh/id_ed25519_codevilot.pub"
    run_entry github-ssh --alias github-codevilot --email user@example.com --non-interactive >/dev/null
    assert_file_contains "$HOME/.ssh/id_ed25519_codevilot" "ORIGINAL PRIVATE"
    assert_file_contains "$HOME/.ssh/id_ed25519_codevilot.pub" "ORIGINAL"
}

test_existing_key_interactive_menu() {
    setup_case "existing-key-menu"
    mkdir -p "$HOME/.ssh"
    printf 'ORIGINAL PRIVATE\n' >"$HOME/.ssh/id_ed25519_codevilot"
    printf 'ssh-ed25519 ORIGINAL user@example.com\n' >"$HOME/.ssh/id_ed25519_codevilot.pub"
    printf '1\nn\nn\nn\n' >"$TTY_INPUT"
    CODEVILOT_TTY_INPUT_FILE="$TTY_INPUT" CODEVILOT_TTY_OUTPUT_FILE="$TTY_OUTPUT" run_entry github-ssh --alias github-codevilot --email user@example.com >/dev/null 2>"$CASE_DIR/err"
    assert_file_contains "$CASE_DIR/err" "Use existing key"
    assert_file_contains "$HOME/.ssh/id_ed25519_codevilot.pub" "ORIGINAL"
}

test_no_duplicate_alias() {
    setup_case "no-duplicate"
    run_entry github-ssh --alias github-codevilot --email user@example.com --non-interactive >/dev/null
    run_entry github-ssh --alias github-codevilot --email user@example.com --non-interactive >/dev/null
    count="$(grep -Fc "# BEGIN codevilot-cli:github-codevilot" "$HOME/.ssh/config")"
    assert_eq "1" "$count"
}

test_github_ssh_test_success() {
    setup_case "ssh-test-success"
    output="$(run_entry github-ssh-test --alias github-codevilot)"
    printf '%s\n' "$output" | grep -Fq "Authenticated account:"
    printf '%s\n' "$output" | grep -Fq "codevilot"
}

test_github_ssh_test_rejected() {
    setup_case "ssh-test-reject"
    SSH_MOCK_MODE=reject run_entry github-ssh-test --alias github-codevilot --public-key "$HOME/.ssh/id_ed25519_codevilot.pub" >/dev/null 2>"$CASE_DIR/err"
    status=$?
    [[ "$status" -ne 0 ]] || return 1
    assert_file_contains "$CASE_DIR/err" "GitHub rejected the SSH key."
}

test_wifi_survey_file_formats_table() {
    setup_case "wifi-survey-file"
    survey_file="$CASE_DIR/survey.txt"
    cat >"$survey_file" <<'EOF'
Survey data from wlan0
	in use: 0 ms ago
	frequency:			5180 MHz [in use]
	noise:				-95 dBm
	channel active time:		102345 ms
	channel busy time:		68342 ms
	channel receive time:		31234 ms
	channel transmit time:		14567 ms
Survey data from wlan0
	frequency:			5200 MHz
	noise:				-92 dBm
	channel active time:		100000 ms
	channel busy time:		25000 ms
	channel receive time:		10000 ms
	channel transmit time:		5000 ms
EOF
    output="$(run_entry wifi-survey --file "$survey_file" --in-use)"
    printf '%s\n' "$output" | grep -Fq "IFACE"
    printf '%s\n' "$output" | grep -Fq "CH"
    printf '%s\n' "$output" | grep -Fq "wlan0"
    printf '%s\n' "$output" | grep -Eq 'wlan0[[:space:]]+36[[:space:]]+5180'
    printf '%s\n' "$output" | grep -Fq "5180"
    printf '%s\n' "$output" | grep -Fq "66.8%"
    ! printf '%s\n' "$output" | grep -Fq "5200"
}

test_wifi_survey_watch_options_parse() {
    setup_case "wifi-survey-watch-parse"
    output="$(
        SCRIPT_DIR="$REPO_ROOT" bash -c '
            . "$SCRIPT_DIR/commands/wifi-survey.sh"
            wifi_survey_parse_args --interface wlan0 --watch 2 --all --count 1 --no-clear
            printf "%s %s %s %s %s\n" "$WIFI_SURVEY_IFACE" "$WIFI_SURVEY_WATCH" "$WIFI_SURVEY_INTERVAL" "$WIFI_SURVEY_ALL" "$WIFI_SURVEY_COUNT"
        '
    )"
    assert_eq "wlan0 1 2 1 1" "$output"
}

test_git_origin_alias_update() {
    setup_case "git-origin"
    repo="$CASE_DIR/repo"
    create_repo "$repo"
    printf 'origin=git@github.com:Tommoro-AI/data_foundry_platform.git\n' >"$repo/.git/remotes.mock"
    run_entry git-origin --repo "$repo" --alias github-codevilot --non-interactive >/dev/null
    assert_file_contains "$repo/.git/remotes.mock" "origin=git@github-codevilot:Tommoro-AI/data_foundry_platform.git"
}

test_dry_run_no_file_changes() {
    setup_case "dry-run"
    repo="$CASE_DIR/repo"
    create_repo "$repo"
    printf 'origin=git@github.com:Tommoro-AI/data_foundry_platform.git\n' >"$repo/.git/remotes.mock"
    run_entry github-ssh --alias github-codevilot --email user@example.com --non-interactive --dry-run >/dev/null
    run_entry git-author --name codevilot --email n@example.com --scope local --repo "$repo" --non-interactive --dry-run >/dev/null
    run_entry git-origin --repo "$repo" --alias github-codevilot --non-interactive --dry-run >/dev/null
    [[ ! -e "$HOME/.ssh/config" ]]
    assert_file_not_contains "$repo/.git/remotes.mock" "github-codevilot"
}

test_permissions() {
    setup_case "permissions"
    run_entry github-ssh --alias github-codevilot --email user@example.com --non-interactive >/dev/null
    assert_eq "700" "$(file_mode "$HOME/.ssh")"
    assert_eq "600" "$(file_mode "$HOME/.ssh/config")"
    assert_eq "600" "$(file_mode "$HOME/.ssh/id_ed25519_codevilot")"
    assert_eq "644" "$(file_mode "$HOME/.ssh/id_ed25519_codevilot.pub")"
}

test_real_home_not_modified() {
    setup_case "home-safe"
    run_entry github-ssh --alias github-codevilot --email user@example.com --non-interactive --dry-run >/dev/null
    [[ ! -e "$HOME/.ssh/config" ]]
    [[ -z "$REAL_HOME" || "$HOME" != "$REAL_HOME" ]]
}

run_test "entry.sh Bash syntax check" test_bash_syntax
run_test "required lib and command files download" test_entry_downloads_required_files
run_test "download failure exits" test_download_failure_exits
run_test "no-argument menu displays new commands" test_menu_runs_without_args
run_test "GitHub submenu displays GitHub commands" test_github_submenu_displays
run_test "Network submenu displays network commands" test_network_submenu_displays
run_test "invalid menu input reprompts" test_invalid_menu_reprompts
run_test "unknown command exits with code 2" test_unknown_command_exit_code
run_test "temporary directory is cleaned up" test_temp_cleanup
run_test "home directory github-ssh completes SSH setup" test_github_ssh_home_success
run_test "github-ssh local scope outside repo skips Git author with zero exit" test_github_ssh_local_scope_outside_git_skips_zero
run_test "github-ssh configures commit author by default when interactive" test_github_ssh_interactive_configures_author_by_default
run_test "actual SSH key generation failure is non-zero" test_ssh_failure_nonzero
run_test "git-author local works inside repository" test_git_author_local_inside_repo
run_test "git-author local works with --repo" test_git_author_repo_path
run_test "git-author rejects invalid repo path" test_git_author_bad_repo
run_test "git-author global asks for confirmation" test_git_author_global_confirm
run_test "git-author non-interactive local missing repo has clear error" test_git_author_noninteractive_local_missing_repo
run_test "existing SSH key is reused" test_existing_key_not_overwritten
run_test "existing SSH key menu can reuse key" test_existing_key_interactive_menu
run_test "same alias does not duplicate block" test_no_duplicate_alias
run_test "github-ssh-test parses GitHub success message" test_github_ssh_test_success
run_test "github-ssh-test explains rejected key" test_github_ssh_test_rejected
run_test "wifi-survey formats saved survey data" test_wifi_survey_file_formats_table
run_test "wifi-survey parses watch options" test_wifi_survey_watch_options_parse
run_test "git-origin changes github.com URL to alias URL" test_git_origin_alias_update
run_test "dry-run changes no user files" test_dry_run_no_file_changes
run_test "SSH config and key permissions are set" test_permissions
run_test "real HOME and Git config are not modified" test_real_home_not_modified

printf '\nPassed: %s\nFailed: %s\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
