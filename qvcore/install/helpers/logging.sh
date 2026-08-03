# shellcheck shell=bash

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
      mapfile -t current_lines < <(tail -n $log_lines "$OMARCHY_INSTALL_LOG_FILE" 2>/dev/null)

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
    clear
  fi
}

start_install_log() {
  local install_group
  local qvos_tui

  install_group=$(id -gn)
  sudo touch "$OMARCHY_INSTALL_LOG_FILE"
  sudo chown "$USER:$install_group" "$OMARCHY_INSTALL_LOG_FILE"
  sudo chmod 0640 "$OMARCHY_INSTALL_LOG_FILE"

  OMARCHY_START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
  export OMARCHY_START_TIME

  echo "=== qvOS Installation Started: $OMARCHY_START_TIME ===" \
    >>"$OMARCHY_INSTALL_LOG_FILE"
  qvos_tui=$(command -v qvos-tui 2>/dev/null || true)
  if [[ -n ${OMARCHY_CHROOT_INSTALL:-} && -n $qvos_tui && -x $qvos_tui ]]; then
    QVOS_TUI_FULLSCREEN=1 "$qvos_tui" \
      --iso-progress \
      --log "$OMARCHY_INSTALL_LOG_FILE" \
      --no-input &
    QVOS_ISO_PROGRESS_PID=$!
  elif [[ -z ${QVOS_ISO_PROGRESS_PID:-} ]]; then
    start_log_output
  fi
}

stop_install_log() {
  stop_log_output
  show_cursor

  if [[ -n ${OMARCHY_INSTALL_LOG_FILE:-} ]]; then
    OMARCHY_END_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    {
      echo "=== qvOS Installation Completed: $OMARCHY_END_TIME ==="
      echo ""
      echo "=== Installation Time Summary ==="
    } >>"$OMARCHY_INSTALL_LOG_FILE"

    if [[ -f "/var/log/archinstall/install.log" ]]; then
      ARCHINSTALL_START=$(grep -m1 '^\[' /var/log/archinstall/install.log 2>/dev/null | sed 's/^\[\([^]]*\)\].*/\1/' || true)
      ARCHINSTALL_END=$(grep 'Installation completed without any errors' /var/log/archinstall/install.log 2>/dev/null | sed 's/^\[\([^]]*\)\].*/\1/' || true)

      if [[ -n $ARCHINSTALL_START ]] && [[ -n $ARCHINSTALL_END ]]; then
        ARCH_START_EPOCH=$(date -d "$ARCHINSTALL_START" +%s)
        ARCH_END_EPOCH=$(date -d "$ARCHINSTALL_END" +%s)
        ARCH_DURATION=$((ARCH_END_EPOCH - ARCH_START_EPOCH))

        ARCH_MINS=$((ARCH_DURATION / 60))
        ARCH_SECS=$((ARCH_DURATION % 60))

        echo "Archinstall: ${ARCH_MINS}m ${ARCH_SECS}s" >>"$OMARCHY_INSTALL_LOG_FILE"
      fi
    fi

    if [[ -n $OMARCHY_START_TIME ]]; then
      OMARCHY_START_EPOCH=$(date -d "$OMARCHY_START_TIME" +%s)
      OMARCHY_END_EPOCH=$(date -d "$OMARCHY_END_TIME" +%s)
      OMARCHY_DURATION=$((OMARCHY_END_EPOCH - OMARCHY_START_EPOCH))

      OMARCHY_MINS=$((OMARCHY_DURATION / 60))
      OMARCHY_SECS=$((OMARCHY_DURATION % 60))

      echo "qvOS:        ${OMARCHY_MINS}m ${OMARCHY_SECS}s" >>"$OMARCHY_INSTALL_LOG_FILE"

      if [[ -n $ARCH_DURATION ]]; then
        TOTAL_DURATION=$((ARCH_DURATION + OMARCHY_DURATION))
        TOTAL_MINS=$((TOTAL_DURATION / 60))
        TOTAL_SECS=$((TOTAL_DURATION % 60))
        echo "Total:       ${TOTAL_MINS}m ${TOTAL_SECS}s" >>"$OMARCHY_INSTALL_LOG_FILE"
      fi
    fi
    echo "=================================" >>"$OMARCHY_INSTALL_LOG_FILE"

    echo "Rebooting system..." >>"$OMARCHY_INSTALL_LOG_FILE"
  fi
}

run_logged() {
  local script="$1"

  export CURRENT_SCRIPT="$script"

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting: $script" >>"$OMARCHY_INSTALL_LOG_FILE"

  # Use bash -c to create a clean subshell
  bash -c "source '$script'" </dev/null >>"$OMARCHY_INSTALL_LOG_FILE" 2>&1

  local exit_code=$?

  if (( exit_code == 0 )); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Completed: $script" >>"$OMARCHY_INSTALL_LOG_FILE"
    unset CURRENT_SCRIPT
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Failed: $script (exit code: $exit_code)" >>"$OMARCHY_INSTALL_LOG_FILE"
  fi

  return $exit_code
}
