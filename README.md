# codevilot CLI

## Run

```bash
curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh | bash
```

`codevilot` is a Bash CLI that runs directly from GitHub Raw. It is not installed as a local `codevilot` executable.

Run a command directly:

```bash
curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh \
  | bash -s -- github-ssh
```

Pass options:

```bash
curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh \
  | bash -s -- github-ssh \
      --alias github-nam \
      --email user@example.com \
      --name "GitHub User" \
      --scope global
```

Help and version:

```bash
curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh \
  | bash -s -- help

curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh \
  | bash -s -- version
```

Install a reusable local command:

```bash
curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh \
  | bash -s -- install
```

The installer writes files to `~/.local/share/codevilot-cli` and creates `~/.local/bin/codevilot`.
After `~/.local/bin` is on `PATH`, run:

```bash
codevilot help
codevilot wifi-survey --interface wlan0 --watch 1
```

- The default `curl | bash` run does not install the codevilot CLI locally.
- Without `install`, each run downloads the current Raw scripts.
- Required command and lib files are downloaded into a temporary directory.
- Temporary CLI files are deleted when the process exits.
- SSH keys and Git config written by `github-ssh` are kept as the command result.

## Review Before Running

```bash
curl -fsSL \
  https://raw.githubusercontent.com/codevilot/cli/main/entry.sh \
  -o /tmp/codevilot-entry.sh

less /tmp/codevilot-entry.sh
bash /tmp/codevilot-entry.sh
```

## Version-Pinned Runs

`main` runs the latest code. To run a tag:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/codevilot/cli/v0.1.0/entry.sh \
  | bash
```

When pinning a version, set `CODEVILOT_REF` so downloaded command and lib files come from the same tag:

```bash
CODEVILOT_REF=v0.1.0 \
bash <(curl -fsSL \
  https://raw.githubusercontent.com/codevilot/cli/v0.1.0/entry.sh)
```

Supported environment variables:

```text
CODEVILOT_RAW_BASE_URL
CODEVILOT_REF
CODEVILOT_DEBUG
```

## Interactive Menu

Running without arguments opens the menu:

```bash
curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh | bash
```

```text
codevilot CLI

Select a command:

  1) GitHub SSH setup
  2) Show help
  3) Show version
  0) Exit

Enter selection:
```

The menu reads from `/dev/tty`, so `curl | bash` does not consume prompt answers from the script stream. In non-interactive environments, run a command explicitly:

```bash
curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh \
  | bash -s -- github-ssh --help
```

## How It Works

`entry.sh` performs the bootstrap flow:

1. Checks Bash and downloader availability.
2. Creates a temporary directory with `mktemp`.
3. Registers cleanup with `trap`.
4. Downloads required files from GitHub Raw.
5. Rejects failed, empty, non-file, or syntax-invalid downloads.
6. Sources only validated files.
7. Runs the menu or dispatches the requested subcommand.
8. Deletes the temporary CLI directory on exit.

Downloaded layout:

```text
/tmp/codevilot.XXXXXX/
├── commands/
│   └── github-ssh.sh
└── lib/
    ├── common.sh
    └── platform.sh
```

## `github-ssh`

`github-ssh` configures:

- a personal Ed25519 SSH key
- a GitHub SSH host alias in `~/.ssh/config`
- `git config user.name`
- `git config user.email`

It never prints your private key, never uploads your private key, and never asks for a GitHub Personal Access Token.

Interactive:

```bash
curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh \
  | bash -s -- github-ssh
```

Non-interactive:

```bash
curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh \
  | bash -s -- github-ssh \
      --alias github-nam \
      --email user@example.com \
      --name "GitHub User" \
      --scope global \
      --non-interactive
```

Options:

```text
--alias <alias>
--email <email>
--name <git-name>
--key-file <path>
--scope <local|global>
--test
--non-interactive
--force
--dry-run
--help
```

Use `--dry-run` to preview actions without writing SSH files or Git config:

```bash
curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh \
  | bash -s -- github-ssh \
      --alias github-nam \
      --email user@example.com \
      --name "GitHub User" \
      --scope global \
      --non-interactive \
      --dry-run
```

The command writes a managed block to `~/.ssh/config`:

```sshconfig
# BEGIN codevilot-cli:github-nam
Host github-nam
    HostName github.com
    User git
    IdentityFile "~/.ssh/id_ed25519_nam"
    IdentitiesOnly yes
# END codevilot-cli:github-nam
```

Clone with:

```bash
git clone git@github-nam:OWNER/REPOSITORY.git
```

Update an existing repository:

```bash
git remote set-url origin git@github-nam:OWNER/REPOSITORY.git
```

## Security Notes

- Private keys are never printed.
- Private keys are never downloaded or uploaded.
- Existing private keys are not overwritten automatically.
- Existing unmanaged SSH config content is preserved.
- Downloaded Bash files are checked with `bash -n` before `source`.
- `eval` is not used.
- Temporary CLI files are created with `mktemp` and removed with `trap`.
- Downloaded module paths are restricted to expected relative paths under the Raw base URL.
- `--dry-run` does not modify user files.

## `wifi-survey`

`wifi-survey` is Linux-only. It uses `iw survey dump` and prints a readable table with channel busy/utilization percentages.

```bash
curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh \
  | bash -s -- wifi-survey --interface wlan0 --in-use
```

Listen on CH36 without joining an AP:

```bash
curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh \
  | bash -s -- wifi-survey --interface wlan0 --monitor --channel 36
```

Monitor continuously without sending repeated GitHub requests:

```bash
curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh \
  | bash -s -- wifi-survey --interface wlan0 --watch 1
```

`--watch` defaults to the active survey entry. Show all survey entries instead:

```bash
curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh \
  | bash -s -- wifi-survey --interface wlan0 --watch 1 --all
```

Set 5180 MHz with 80 MHz width and center frequency 5210:

```bash
curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh \
  | bash -s -- wifi-survey --interface wlan0 --freq 5180 --width 80 --center-freq1 5210
```

Example output:

```text
IFACE      CH    FREQ      IN_USE  NOISE    BUSY       RX         TX         ACTIVE_MS  BUSY_MS
---------- ----- --------- ------- -------- ---------- ---------- ---------- ---------- ----------
wlan0      36    5180      yes     -95 dBm  66.8%      30.5%      14.2%      102345     68342
```

## Tests

Run:

```bash
./tests/run-tests.sh
```

The tests use a temporary `HOME`, a local Raw mock, and mock `curl`, `git`, `ssh`, and `ssh-keygen`, so they do not modify your real `~/.ssh/config` or Git config.

If ShellCheck is installed:

```bash
shellcheck entry.sh commands/*.sh lib/*.sh tests/*.sh
```

## Add a New Command

1. Create `commands/my-command.sh`.
2. Define a `my_command_main "$@"` function.
3. Add the file to `REQUIRED_FILES` in `entry.sh`.
4. Add a dispatcher branch in `entry.sh`.
5. Put shared helpers in `lib/common.sh` or a focused `lib/*.sh` file.
6. Add tests under `tests/`.
