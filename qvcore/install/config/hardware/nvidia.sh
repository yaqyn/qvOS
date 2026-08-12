# shellcheck shell=bash

if lspci | grep -qi 'nvidia'; then
  if qv-hw-nvidia-gsp; then
    PACKAGES=(nvidia-open-dkms nvidia-utils lib32-nvidia-utils libva-nvidia-driver)
    nvidia_env_source="$QVOS_PATH/qvcore/install/hardware/nvidia/env-gsp.lua"
  elif qv-hw-nvidia-without-gsp; then
    PACKAGES=(nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils)
    nvidia_env_source="$QVOS_PATH/qvcore/install/hardware/nvidia/env-legacy.lua"
  fi
  # Bail if no supported GPU
  if [[ -z ${PACKAGES+x} ]]; then
    echo "No compatible driver for your NVIDIA GPU. See: https://wiki.archlinux.org/title/NVIDIA"
    return 0
  fi

  nvidia_env="$HOME/.config/hypr/envs.lua"
  nvidia_env_parent=${nvidia_env%/*}
  [[ -d $nvidia_env_parent && ! -L $nvidia_env_parent && -O $nvidia_env_parent ]] || {
    echo "Refusing unsafe NVIDIA environment directory: $nvidia_env_parent" >&2
    return 1
  }
  if [[ -e $nvidia_env || -L $nvidia_env ]]; then
    [[ -f $nvidia_env && ! -L $nvidia_env && -O $nvidia_env ]] || {
      echo "Refusing unsafe NVIDIA environment target: $nvidia_env" >&2
      return 1
    }
    nvidia_env_known=false
    for known_env in \
      "$QVOS_PATH/qvcore/config/files/hypr/envs.lua" \
      "$QVOS_PATH/qvcore/install/hardware/nvidia/env-gsp.lua" \
      "$QVOS_PATH/qvcore/install/hardware/nvidia/env-legacy.lua"; do
      if cmp -s -- "$known_env" "$nvidia_env"; then
        nvidia_env_known=true
        break
      fi
    done
    if [[ $nvidia_env_known == "false" ]]; then
      echo "Preserving modified NVIDIA environment: $nvidia_env" >&2
      return 1
    fi
  fi

  qv-pkg-add linux-headers "${PACKAGES[@]}"
  "$QVOS_PATH/qvcore/install/hardware/identity" nvidia-boot

  # Publish the exact NVIDIA environment for this hardware atomically.
  cmp -s -- "$nvidia_env_source" "$nvidia_env" && return 0
  nvidia_env_stage=$(mktemp "${nvidia_env%/*}/.qvos-nvidia-env.XXXXXX")
  if ! install -m 0644 -- "$nvidia_env_source" "$nvidia_env_stage"; then
    rm -f -- "$nvidia_env_stage"
    return 1
  fi
  if ! mv -f -- "$nvidia_env_stage" "$nvidia_env"; then
    rm -f -- "$nvidia_env_stage"
    return 1
  fi
fi
