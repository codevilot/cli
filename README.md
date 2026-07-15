# codevilot CLI

`codevilot` is an extensible Bash CLI for developer and operations convenience tasks. The first command, `github-ssh`, configures a personal GitHub SSH identity, SSH host alias, and Git commit author settings.

The CLI is designed so each feature lives in its own command file under `commands/`, while shared output, prompting, path, and platform helpers live in `lib/`.

## Install

```bash
./install.sh
```

The installer creates or updates this symlink by default:

```text
~/.local/bin/codevilot -> /path/to/repo/cli.sh
```

It does not require root and does not edit `.bashrc` or `.zshrc`. If `~/.local/bin` is not in `PATH`, add this manually:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Quick Start

```bash
./cli.sh help
./cli.sh version
./cli.sh github-ssh

codevilot help
codevilot github-ssh
```

## `github-ssh`

`github-ssh` helps configure:

- a GitHub SSH host alias in `~/.ssh/config`
- an Ed25519 SSH key if one does not already exist
- `git config user.name`
- `git config user.email`

It never registers keys with GitHub through the API, never asks for a personal access token, and never prints your private key.

### Interactive Usage

```bash
codevilot github-ssh
```

You will be prompted for:

```text
GitHub SSH alias [example: github-user]:
GitHub email:
Git commit author name:
SSH key path [default]:
Git config scope [local/global]:
```

### Non-Interactive Usage

```bash
codevilot github-ssh \
  --alias github-user \
  --email user@example.com \
  --name "GitHub User" \
  --scope global \
  --non-interactive
```

Supported options:

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

Use `--dry-run` to preview changes without writing files or Git config:

```bash
codevilot github-ssh \
  --alias github-user \
  --email user@example.com \
  --name "GitHub User" \
  --scope global \
  --non-interactive \
  --dry-run
```

## SSH Alias

The command writes a managed block to `~/.ssh/config`:

```sshconfig
# BEGIN codevilot-cli:github-user
Host github-user
    HostName github.com
    User git
    IdentityFile "~/.ssh/id_ed25519_user"
    IdentitiesOnly yes
# END codevilot-cli:github-user
```

The alias is used in Git URLs:

```bash
git clone git@github-user:OWNER/REPOSITORY.git
```

For an existing repository:

```bash
git remote set-url origin git@github-user:OWNER/REPOSITORY.git
```

The alias `github-user` is resolved by the `~/.ssh/config` file on the machine where the `git` command is executed.

## Remote PC Behavior

Example:

```text
local PC
  -> SSH into remote PC
       -> run git clone on the remote PC
```

In this case GitHub authentication uses the remote PC's files, not the local PC's files:

```text
remote PC ~/.ssh/config
remote PC SSH private key
```

Configure `codevilot github-ssh` on the remote PC if the Git command runs there.

## Git Author vs SSH Account vs Remote

```text
git config user.name / user.email
-> author identity written into commit history

SSH key
-> authentication account used by GitHub for clone, fetch, pull, and push

git remote origin
-> repository URL and SSH alias used by Git
```

These are related but separate. You can commit with one author email and authenticate to GitHub with an SSH key registered to a different GitHub account. The `--test` option can show which GitHub account the SSH key authenticates as.

## Security Notes

- Private keys are never printed.
- Private keys are never sent over the network by this CLI.
- Existing private keys are not overwritten automatically.
- `~/.ssh` is set to `700`, `~/.ssh/config` to `600`, private keys to `600`, and public keys to `644`.
- Managed SSH config blocks are replaced by marker comments; unrelated SSH config content is preserved.
- The script uses `mktemp` for temporary files and avoids `eval`.
- The `.gitignore` ignores common private key and secret patterns. It also ignores `id_ed25519*`, including matching `.pub` files, because public key comments and filenames can still expose identity metadata.

## Add a New Command

1. Create `commands/my-command.sh`.
2. Define a `my_command_main "$@"` function.
3. Add a case branch in `cli.sh`.
4. Put shared helpers in `lib/common.sh` or a focused `lib/*.sh` file.
5. Add tests under `tests/`.

Keep command files independent and avoid hard-coded absolute paths. Use the existing `SCRIPT_DIR` based loading pattern so commands work from any current directory.

## Tests

Run the dependency-free Bash test suite:

```bash
./tests/run-tests.sh
```

The tests use a temporary `HOME` and mock `git`, `ssh`, and `ssh-keygen` executables, so they do not modify your real `~/.ssh/config` or global Git config.

If ShellCheck is installed:

```bash
shellcheck cli.sh install.sh commands/*.sh lib/*.sh tests/*.sh
```

## Uninstall

Remove the installed symlink:

```bash
rm -f "$HOME/.local/bin/codevilot"
```

This does not remove SSH keys or SSH config blocks. Remove those manually if you no longer need them.
