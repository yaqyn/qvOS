#!/bin/bash
set -euo pipefail

if omarchy-cmd-missing curl; then
  omarchy-pkg-add curl
fi

curl_path=$(command -v curl)
metadata_proxy_dir=""

cleanup() {
  if [[ -n $metadata_proxy_dir && -d $metadata_proxy_dir ]]; then
    rm -rf "$metadata_proxy_dir"
  fi
}
trap cleanup EXIT

if omarchy-cmd-present gh && gh auth status --hostname github.com >/dev/null 2>&1; then
  metadata_proxy_dir=$(mktemp -d)
  install -m 0755 /dev/stdin "$metadata_proxy_dir/curl" <<EOF
#!/bin/bash
for argument in "\$@"; do
  case \$argument in
  https://api.github.com/*)
    exec gh api "\${argument#https://api.github.com/}"
    ;;
  esac
done

exec "$curl_path" "\$@"
EOF
fi

echo "Installing Codex from OpenAI..."
"$curl_path" -fsSL https://chatgpt.com/codex/install.sh |
  PATH="${metadata_proxy_dir:+$metadata_proxy_dir:}$PATH" \
    CODEX_INSTALL_DIR="$HOME/.local/bin" \
    CODEX_NON_INTERACTIVE=1 \
    sh

"$HOME/.local/bin/codex" --version
