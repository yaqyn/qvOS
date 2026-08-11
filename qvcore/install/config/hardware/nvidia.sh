# shellcheck shell=bash

if lspci | grep -qi 'nvidia'; then
  # Check which kernel is installed and set appropriate headers package
  KERNEL_HEADERS="$(pacman -Qqs '^linux(-zen|-lts|-hardened)?$' | head -1)-headers"

  if qv-hw-nvidia-gsp; then
    PACKAGES=(nvidia-open-dkms nvidia-utils lib32-nvidia-utils libva-nvidia-driver)
    GPU_ARCH="turing_plus"
  elif qv-hw-nvidia-without-gsp; then
    PACKAGES=(nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils)
    GPU_ARCH="maxwell_pascal_volta"
  fi
  # Bail if no supported GPU
  if [[ -z ${PACKAGES+x} ]]; then
    echo "No compatible driver for your NVIDIA GPU. See: https://wiki.archlinux.org/title/NVIDIA"
    exit 0
  fi

  qv-pkg-add "$KERNEL_HEADERS" "${PACKAGES[@]}"

  # Configure modprobe for early KMS
  sudo tee /etc/modprobe.d/nvidia.conf <<EOF >/dev/null
options nvidia_drm modeset=1
EOF

  # Configure mkinitcpio for early loading
  sudo tee /etc/mkinitcpio.conf.d/nvidia.conf <<EOF >/dev/null
MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
EOF

  # Publish the exact NVIDIA environment for this hardware atomically.
  nvidia_env="$HOME/.config/hypr/envs.lua"
  nvidia_env_stage=$(mktemp "${nvidia_env%/*}/.qvos-nvidia-env.XXXXXX")
  if [[ $GPU_ARCH = "turing_plus" ]]; then
    # Turing+ (RTX 20xx, GTX 16xx, and newer) with GSP firmware support
    if ! install -m 0644 /dev/stdin "$nvidia_env_stage" <<'EOF'
-- qvOS-managed NVIDIA environment (Turing+ with GSP firmware).
hl.env("NVD_BACKEND", "direct")
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
EOF
    then
      rm -f -- "$nvidia_env_stage"
      return 1
    fi
  elif [[ $GPU_ARCH = "maxwell_pascal_volta" ]]; then
    # Maxwell/Pascal/Volta (GTX 9xx/10xx, GT 10xx, Quadro P/M/GV, MX series, Titan X/Xp/V) lack GSP firmware
    if ! install -m 0644 /dev/stdin "$nvidia_env_stage" <<'EOF'
-- qvOS-managed NVIDIA environment (Maxwell/Pascal/Volta without GSP firmware).
hl.env("NVD_BACKEND", "egl")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
EOF
    then
      rm -f -- "$nvidia_env_stage"
      return 1
    fi
  fi
  if ! mv -f -- "$nvidia_env_stage" "$nvidia_env"; then
    rm -f -- "$nvidia_env_stage"
    return 1
  fi
fi
