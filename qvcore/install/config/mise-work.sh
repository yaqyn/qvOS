# shellcheck shell=bash

node_package_dir=${QVOS_NODE_PACKAGE_DIR:-/opt/packages}
work_root="$HOME/Work"
work_config="$work_root/.mise.toml"
expected_work_config=$'[env]\n_.path = "{{ cwd }}/bin"'

qvos_mise_fail() {
  printf 'qvOS Mise setup: %s\n' "$1" >&2
  return 1
}

qvos_mise_safe_directory() {
  local mode

  [[ -d $1 && ! -L $1 && -O $1 ]] || return 1
  mode=$(stat -c '%a' -- "$1") || return 1
  (( (8#$mode & 022) == 0 ))
}

qvos_mise_ensure_directory() {
  local path=$1

  if [[ -e $path || -L $path ]]; then
    qvos_mise_safe_directory "$path" ||
      qvos_mise_fail "refusing unsafe directory: $path"
  else
    install -d -m 0755 -- "$path"
  fi
}

qvos_mise_install_work_config() {
  local pending

  qvos_mise_ensure_directory "$work_root"
  qvos_mise_ensure_directory "$work_root/tries"
  if [[ -e $work_config || -L $work_config ]]; then
    if [[ ! -f $work_config || -L $work_config || ! -O $work_config ||
      $(stat -c '%a' -- "$work_config") != "644" ||
      $(<"$work_config") != "$expected_work_config" ]]; then
      printf 'qvOS preserved the existing Mise work configuration: %s\n' \
        "$work_config" >&2
      return 0
    fi
  else
    pending=$(mktemp "$work_root/.mise.toml.qvos.XXXXXX") || return 1
    if ! printf '%s\n' "$expected_work_config" >"$pending" ||
      ! chmod 0644 -- "$pending" ||
      ! mv -fT -- "$pending" "$work_config"; then
      rm -f -- "$pending"
      return 1
    fi
  fi

  mise trust "$work_config"
}

qvos_mise_safe_node_runtime() {
  local runtime=$1
  local command_path
  local resolved

  qvos_mise_safe_directory "$runtime" || return 1
  [[ -f $runtime/bin/node && ! -L $runtime/bin/node &&
    -O $runtime/bin/node && -x $runtime/bin/node ]] || return 1
  for command_path in "$runtime/bin/npm" "$runtime/bin/npx"; do
    [[ -L $command_path && -O $command_path ]] || return 1
    resolved=$(realpath -e -- "$command_path") || return 1
    [[ $resolved == "$runtime/"* && -f $resolved && -x $resolved ]]
  done
}

qvos_mise_validate_node_archive() {
  local archive=$1
  local archive_root=$2

  tar -tzf "$archive" | awk -v root="$archive_root/" '
    NF == 0 || index($0, root) != 1 || $0 ~ /(^|\/)\.\.(\/|$)/ {
      invalid = 1
    }
    END { exit invalid }
  '
}

qvos_mise_install_offline_node() {
  local archive
  local archive_name
  local archive_root
  local node_parent="$HOME/.local/share/mise/installs/node"
  local node_runtime
  local node_version
  local pending=""
  local -a archives=()

  [[ -d $node_package_dir && ! -L $node_package_dir ]] ||
    qvos_mise_fail "the offline package directory is unavailable"
  mapfile -d '' -t archives < <(
    find "$node_package_dir" -maxdepth 1 -type f \
      -name 'node-v*-linux-x64.tar.gz' -print0
  )
  (( ${#archives[@]} == 1 )) ||
    qvos_mise_fail "expected exactly one offline Node.js archive"
  archive=${archives[0]}
  archive_name=${archive##*/}
  if [[ $archive_name =~ ^node-v([0-9]+\.[0-9]+\.[0-9]+)-linux-x64\.tar\.gz$ ]]; then
    node_version=${BASH_REMATCH[1]}
  else
    qvos_mise_fail "the offline Node.js archive name is malformed"
  fi
  archive_root="node-v$node_version-linux-x64"
  qvos_mise_validate_node_archive "$archive" "$archive_root" ||
    qvos_mise_fail "the offline Node.js archive has an unsafe layout"

  qvos_mise_ensure_directory "$HOME/.local"
  qvos_mise_ensure_directory "$HOME/.local/share"
  qvos_mise_ensure_directory "$HOME/.local/share/mise"
  qvos_mise_ensure_directory "$HOME/.local/share/mise/installs"
  qvos_mise_ensure_directory "$node_parent"
  node_runtime="$node_parent/$node_version"
  if [[ -e $node_runtime || -L $node_runtime ]]; then
    qvos_mise_safe_node_runtime "$node_runtime" ||
      qvos_mise_fail "refusing an incomplete or unsafe Node.js runtime"
  else
    pending=$(mktemp -d "$node_parent/.node-$node_version.qvos.XXXXXX") ||
      return 1
    if ! tar -xzf "$archive" \
      --strip-components=1 \
      --no-same-owner \
      --no-same-permissions \
      -C "$pending" ||
      ! qvos_mise_safe_node_runtime "$pending" ||
      ! mv -T -- "$pending" "$node_runtime"; then
      rm -rf -- "$pending"
      return 1
    fi
  fi

  mise use -g node@"$node_version"
}

qvos_mise_install_work_config
if [[ ${QVOS_CHROOT_INSTALL:-} == "1" ]]; then
  qvos_mise_install_offline_node
else
  mise use -g node@lts
fi
