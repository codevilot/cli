#!/usr/bin/env bash
set -u

SCRIPT_PATH="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" >/dev/null 2>&1 && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
INSTALL_PATH="${INSTALL_PATH:-$INSTALL_DIR/codevilot}"

mkdir -p "$INSTALL_DIR"
ln -sfn "$SCRIPT_DIR/cli.sh" "$INSTALL_PATH"
chmod +x "$SCRIPT_DIR/cli.sh"

printf 'Installed codevilot at %s\n' "$INSTALL_PATH"

case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *)
        cat <<EOF

$INSTALL_DIR is not in your PATH.
Add this to your shell config if needed:

  export PATH="$INSTALL_DIR:\$PATH"

For bash, edit ~/.bashrc.
For zsh, edit ~/.zshrc.
EOF
        ;;
esac

cat <<'EOF'

Try:
  codevilot help
EOF
