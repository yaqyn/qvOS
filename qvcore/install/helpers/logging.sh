# shellcheck shell=bash

qvos_install_start_time=""

start_log_output() {
  local ANSI_SAVE_CURSOR="\033[s"
  local ANSI_RESTORE_CURSOR="\033[u"
  local ANSI_CLEAR_LINE="\033[2K"
  local ANSI_HIDE_CURSOR="\033[?25l"
  local ANSI_RESET="\033[0m"
  local ANSI_GRAY="\033[90m"

  # Save cursor position and hide cursor
  printf '%b' "$ANSI_SAVE_CURSOR"
  printf '%b' "$ANSI_HIDE_CURSOR"

  (
    local log_lines=20
    local max_line_width=$((LOGO_WIDTH - 4))

    while true; do
      # Read the last N lines into an array
      mapfile -t current_lines < <(tail -n "$log_lines" "$QVOS_INSTALL_LOG_FILE" 2>/dev/null)

      # Build complete output buffer with escape sequences
      output=""
      for ((i = 0; i < log_lines; i++)); do
        line="${current_lines[i]:-}"

        # Truncate if needed
        if (( ${#line} > max_line_width )); then
          line="${line:0:$max_line_width}..."
        fi

        # Add clear line escape and formatted output for each line
        if [[ -n $line ]]; then
          output+="${ANSI_CLEAR_LINE}${ANSI_GRAY}${PADDING_LEFT_SPACES}  → ${line}${ANSI_RESET}\n"
        else
          output+="${ANSI_CLEAR_LINE}${PADDING_LEFT_SPACES}\n"
        fi
      done

      printf "${ANSI_RESTORE_CURSOR}%b" "$output"

      sleep 0.1
    done
  ) &
  monitor_pid=$!
}

stop_log_output() {
  if [[ -n ${monitor_pid:-} ]]; then
    kill "$monitor_pid" 2>/dev/null || true
    wait "$monitor_pid" 2>/dev/null || true
    unset monitor_pid
  fi

  if [[ -n ${QVOS_ISO_PROGRESS_PID:-} ]]; then
    kill "$QVOS_ISO_PROGRESS_PID" 2>/dev/null || true
    for _ in {1..20}; do
      kill -0 "$QVOS_ISO_PROGRESS_PID" 2>/dev/null || break
      sleep 0.05
    done
    if kill -0 "$QVOS_ISO_PROGRESS_PID" 2>/dev/null; then
      kill -KILL "$QVOS_ISO_PROGRESS_PID" 2>/dev/null || true
    fi
    wait "$QVOS_ISO_PROGRESS_PID" 2>/dev/null || true
    unset QVOS_ISO_PROGRESS_PID
    clear || true
  fi
}

start_install_log() {
  local install_group
  local qvos_tui

  install_group=$(id -gn)
  sudo touch "$QVOS_INSTALL_LOG_FILE"
  sudo chown "$USER:$install_group" "$QVOS_INSTALL_LOG_FILE"
  sudo chmod 0640 "$QVOS_INSTALL_LOG_FILE"

  qvos_install_start_time=$(date '+%Y-%m-%d %H:%M:%S')

  echo "=== qvOS Installation Started: $qvos_install_start_time ===" \
    >>"$QVOS_INSTALL_LOG_FILE"
  qvos_tui=$(command -v qvos-tui 2>/dev/null || true)
  if [[ ${QVOS_CHROOT_INSTALL:-} == "1" && -n $qvos_tui && -x $qvos_tui ]]; then
    QVOS_TUI_FULLSCREEN=1 "$qvos_tui" \
      --iso-progress \
      --log "$QVOS_INSTALL_LOG_FILE" \
      --no-input &
    QVOS_ISO_PROGRESS_PID=$!
  elif [[ -z ${QVOS_ISO_PROGRESS_PID:-} ]]; then
    start_log_output
  fi
}

stop_install_log() {
  local arch_duration=""
  local arch_end_epoch
  local arch_mins
  local arch_secs
  local arch_start_epoch
  local archinstall_end=""
  local archinstall_start=""
  local qvos_duration
  local qvos_end_epoch
  local qvos_end_time
  local qvos_mins
  local qvos_secs
  local qvos_start_epoch
  local total_duration
  local total_mins
  local total_secs

  stop_log_output
  show_cursor

  if [[ -n ${QVOS_INSTALL_LOG_FILE:-} ]]; then
    qvos_end_time=$(date '+%Y-%m-%d %H:%M:%S')
    {
      echo "=== qvOS Installation Completed: $qvos_end_time ==="
      echo ""
      echo "=== Installation Time Summary ==="
    } >>"$QVOS_INSTALL_LOG_FILE"

    if [[ -f "/var/log/archinstall/install.log" ]]; then
      archinstall_start=$(grep -m1 '^\[' /var/log/archinstall/install.log 2>/dev/null | sed 's/^\[\([^]]*\)\].*/\1/' || true)
      archinstall_end=$(grep 'Installation completed without any errors' /var/log/archinstall/install.log 2>/dev/null | sed 's/^\[\([^]]*\)\].*/\1/' || true)

      if [[ -n $archinstall_start && -n $archinstall_end ]]; then
        arch_start_epoch=$(date -d "$archinstall_start" +%s)
        arch_end_epoch=$(date -d "$archinstall_end" +%s)
        arch_duration=$((arch_end_epoch - arch_start_epoch))

        arch_mins=$((arch_duration / 60))
        arch_secs=$((arch_duration % 60))

        echo "Archinstall: ${arch_mins}m ${arch_secs}s" >>"$QVOS_INSTALL_LOG_FILE"
      fi
    fi

    if [[ -n $qvos_install_start_time ]]; then
      qvos_start_epoch=$(date -d "$qvos_install_start_time" +%s)
      qvos_end_epoch=$(date -d "$qvos_end_time" +%s)
      qvos_duration=$((qvos_end_epoch - qvos_start_epoch))

      qvos_mins=$((qvos_duration / 60))
      qvos_secs=$((qvos_duration % 60))

      echo "qvOS:        ${qvos_mins}m ${qvos_secs}s" >>"$QVOS_INSTALL_LOG_FILE"

      if [[ -n $arch_duration ]]; then
        total_duration=$((arch_duration + qvos_duration))
        total_mins=$((total_duration / 60))
        total_secs=$((total_duration % 60))
        echo "Total:       ${total_mins}m ${total_secs}s" >>"$QVOS_INSTALL_LOG_FILE"
      fi
    fi
    echo "=================================" >>"$QVOS_INSTALL_LOG_FILE"

    echo "Rebooting system..." >>"$QVOS_INSTALL_LOG_FILE"
  fi
}

run_logged() {
  local exit_code
  local script="$1"

  export CURRENT_SCRIPT="$script"

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting: $script" >>"$QVOS_INSTALL_LOG_FILE"

  # Use bash -c to create a clean subshell. Save the path and clear the
  # transport argument before sourcing so a stage receives no false $1.
  if bash -c 'script=$1; set --; source "$script"' _ "$script" \
    </dev/null >>"$QVOS_INSTALL_LOG_FILE" 2>&1; then
    exit_code=0
  else
    exit_code=$?
  fi

  if (( exit_code == 0 )); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Completed: $script" >>"$QVOS_INSTALL_LOG_FILE"
    unset CURRENT_SCRIPT
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Failed: $script (exit code: $exit_code)" >>"$QVOS_INSTALL_LOG_FILE"
  fi

  return $exit_code
}
