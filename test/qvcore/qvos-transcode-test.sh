#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
media_owner="$root/qvcore/transcode/media"
ascii_owner="$root/qvcore/transcode/ascii"
test_root=$(mktemp -d)
test_home="$test_root/home"
test_bin="$test_root/bin"
media_dir="$test_root/media"
magick_log="$test_root/magick.log"
ffmpeg_log="$test_root/ffmpeg.log"
clipboard_log="$test_root/clipboard.log"
notification_log="$test_root/notification.log"

cleanup() {
  [[ ! -d $test_root ]] || rm -rf -- "$test_root"
}
trap cleanup EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d \
  "$test_bin" \
  "$test_home/Pictures" \
  "$test_home/Videos" \
  "$media_dir"

install -m 0755 /dev/stdin "$test_bin/qv-cmd-missing" <<'SCRIPT'
#!/bin/bash
for command in "$@"; do
  command -v -- "$command" >/dev/null 2>&1 || exit 0
done
exit 1
SCRIPT
install -m 0755 /dev/stdin "$test_bin/file" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "${QVOS_TEST_MIME:-image/heic}"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/magick" <<'SCRIPT'
#!/bin/bash
printf 'call\n' >>"$QVOS_TEST_MAGICK_LOG"
printf '%s\n' "$@" >>"$QVOS_TEST_MAGICK_LOG"
last=${!#}
if [[ $last == "info:" ]]; then
  [[ ${QVOS_TEST_FAIL_IDENTIFY:-false} != "true" ]] || exit 9
  printf '0 1'
elif [[ $last == "pbm:-" ]]; then
  [[ ${QVOS_TEST_FAIL_RENDER:-false} != "true" ]] || exit 9
  printf 'P1\n1 2\n1\n1\n'
else
  [[ ${QVOS_TEST_FAIL_MAGICK:-false} != "true" ]] || {
    printf 'partial\n' >"$last"
    exit 9
  }
  printf 'converted picture\n' >"$last"
fi
SCRIPT
install -m 0755 /dev/stdin "$test_bin/ffmpeg" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$@" >"$QVOS_TEST_FFMPEG_LOG"
last=${!#}
[[ ${QVOS_TEST_FAIL_FFMPEG:-false} != "true" ]] || {
  printf 'partial\n' >"$last"
  exit 9
}
printf 'converted video\n' >"$last"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/wl-copy" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$@" >"$QVOS_TEST_CLIPBOARD_ARGS"
IFS= read -r value || true
value=${value%$'\r'}
printf '%s\n' "$value" >"$QVOS_TEST_CLIPBOARD_LOG"
[[ ${QVOS_TEST_FAIL_CLIPBOARD:-false} != "true" ]]
SCRIPT
install -m 0755 /dev/stdin "$test_bin/qv-notification-send" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TEST_NOTIFICATION_LOG"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/qv-menu-file" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$QVOS_TEST_MENU_FILE_LOG"
[[ ${QVOS_TEST_CANCEL_SELECTION:-false} != "true" ]] || exit 1
printf '%s\n' "$QVOS_TEST_SELECTED_INPUT"
SCRIPT
install -m 0755 /dev/stdin "$test_bin/qv-menu-select" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >>"$QVOS_TEST_MENU_SELECT_LOG"
case $1 in
*format*) printf 'jpg\n' ;;
*resolution*) printf 'low\n' ;;
*) exit 2 ;;
esac
SCRIPT

run_media() {
  HOME="$test_home" \
    PATH="$test_bin:/usr/bin" \
    QVOS_TEST_MAGICK_LOG="$magick_log" \
    QVOS_TEST_FFMPEG_LOG="$ffmpeg_log" \
    QVOS_TEST_CLIPBOARD_ARGS="$test_root/clipboard.args" \
    QVOS_TEST_CLIPBOARD_LOG="$clipboard_log" \
    QVOS_TEST_NOTIFICATION_LOG="$notification_log" \
    "$media_owner" "$@"
}

picture="$media_dir/photo source.heic"
printf 'picture fixture\n' >"$picture"
picture_output="$media_dir/photo source-medium.jpg"
run_media "$picture" jpg medium >/dev/null
[[ $(<"$picture_output") == "converted picture" ]] ||
  fail "picture result"
grep -Fqx "$(realpath -e -- "$picture")" "$magick_log" ||
  fail "picture input argument"
grep -Fqx -- '-strip' "$magick_log" || fail "picture metadata strip"
grep -Fqx 'file://'"$(dirname -- "$picture_output")"'/photo%20source-medium.jpg' \
  "$clipboard_log" || fail "percent-encoded clipboard URI"
if find "$media_dir" -maxdepth 1 -name '.qvos-transcode.*' -print -quit |
  grep -q .; then
  fail "picture staging cleanup"
fi
pass "picture output publishes atomically with a valid clipboard URI"

set +e
run_media "$picture" jpg medium >/dev/null 2>&1
existing_status=$?
set -e
(( existing_status == 1 )) || fail "existing media result status"
[[ $(<"$picture_output") == "converted picture" ]] ||
  fail "existing media result preservation"
pass "media conversion never overwrites an existing result"

failed_output="$media_dir/photo source-low.png"
set +e
QVOS_TEST_FAIL_MAGICK=true run_media "$picture" png low >/dev/null 2>&1
failure_status=$?
set -e
(( failure_status == 9 )) || fail "failed picture status"
[[ ! -e $failed_output && ! -L $failed_output ]] ||
  fail "partial picture result"
if find "$media_dir" -maxdepth 1 -name '.qvos-transcode.*' -print -quit |
  grep -q .; then
  fail "failed picture staging cleanup"
fi
pass "failed conversion leaves no partial output or staging"

clipboard_output="$media_dir/photo source-high.png"
QVOS_TEST_FAIL_CLIPBOARD=true run_media "$picture" png high >/dev/null 2>&1 ||
  fail "clipboard failure changed saved conversion status"
[[ $(<"$clipboard_output") == "converted picture" ]] ||
  fail "clipboard-independent result"
pass "clipboard failure preserves a successful saved conversion"

video="$media_dir/demo recording.mov"
printf 'video fixture\n' >"$video"
QVOS_TEST_MIME=video/quicktime run_media "$video" mp4 1080p >/dev/null
video_output="$media_dir/demo recording-1080p.mp4"
[[ $(<"$video_output") == "converted video" ]] || fail "video result"
for expected_argument in \
  -nostdin \
  -n \
  -map_metadata \
  -map_chapters \
  libx264 \
  yuv420p \
  aac \
  +faststart; do
  grep -Fqx -- "$expected_argument" "$ffmpeg_log" ||
    fail "video argument: $expected_argument"
done
pass "video conversion strips metadata and uses share-compatible output"

interactive="$test_home/Pictures/interactive.avif"
printf 'interactive fixture\n' >"$interactive"
menu_file_log="$test_root/menu-file.log"
menu_select_log="$test_root/menu-select.log"
HOME="$test_home" \
  PATH="$test_bin:/usr/bin" \
  QVOS_TEST_SELECTED_INPUT="$interactive" \
  QVOS_TEST_MENU_FILE_LOG="$menu_file_log" \
  QVOS_TEST_MENU_SELECT_LOG="$menu_select_log" \
  QVOS_TEST_MAGICK_LOG="$magick_log" \
  QVOS_TEST_CLIPBOARD_ARGS="$test_root/clipboard.args" \
  QVOS_TEST_CLIPBOARD_LOG="$clipboard_log" \
  QVOS_TEST_NOTIFICATION_LOG="$notification_log" \
  "$media_owner" >/dev/null
[[ -f $test_home/Pictures/interactive-low.jpg ]] ||
  fail "interactive conversion result"
grep -Fq "$test_home/Pictures:$test_home/Videos" "$menu_file_log" ||
  fail "interactive search roots"
[[ $(wc -l <"$menu_select_log") == 2 ]] ||
  fail "interactive format and resolution selection"
pass "interactive conversion uses only existing native menu owners"

explicit_home="$test_root/explicit-home"
explicit_picture="$media_dir/explicit.webp"
install -d "$explicit_home"
printf 'explicit fixture\n' >"$explicit_picture"
HOME="$explicit_home" \
  PATH="$test_bin:/usr/bin" \
  QVOS_TEST_MAGICK_LOG="$magick_log" \
  QVOS_TEST_CLIPBOARD_ARGS="$test_root/clipboard.args" \
  QVOS_TEST_CLIPBOARD_LOG="$clipboard_log" \
  QVOS_TEST_NOTIFICATION_LOG="$notification_log" \
  "$media_owner" "$explicit_picture" jpg low >/dev/null
[[ -f $media_dir/explicit-low.jpg ]] ||
  fail "explicit conversion without media directories"
pass "explicit input does not depend on interactive search directories"

set +e
HOME="$test_home" \
  PATH="$test_bin:/usr/bin" \
  QVOS_TEST_CANCEL_SELECTION=true \
  QVOS_TEST_MENU_FILE_LOG="$menu_file_log" \
  QVOS_TEST_SELECTED_INPUT="$interactive" \
  "$media_owner" >/dev/null 2>&1
cancel_status=$?
set -e
(( cancel_status == 130 )) || fail "interactive cancellation status"
pass "interactive cancellation closes without a false failure result"

set +e
run_media "$picture" jpg high unexpected >/dev/null 2>&1
extra_status=$?
run_media "$picture" gif high >/dev/null 2>&1
target_status=$?
QVOS_TEST_MIME=video/quicktime run_media "$video" gif 4k >/dev/null 2>&1
gif_status=$?
set -e
(( extra_status == 2 && target_status == 2 && gif_status == 2 )) ||
  fail "media argument validation"
pass "media arguments and type-specific targets are validated before mutation"

ascii_input="$media_dir/logo image.png"
ascii_output="$media_dir/logo.txt"
printf 'image fixture\n' >"$ascii_input"
printf 'old terminal art\n' >"$ascii_output"
chmod 0640 "$ascii_output"
: >"$magick_log"
HOME="$test_home" PATH="$test_bin:/usr/bin" \
  QVOS_TEST_MAGICK_LOG="$magick_log" \
  "$ascii_owner" "$ascii_input" "$ascii_output" \
  --mode block --width 1 --height 1 >/dev/null
[[ $(<"$ascii_output") == "█" ]] || fail "block terminal art"
[[ $(stat -c '%a' "$ascii_output") == "640" ]] ||
  fail "terminal-art destination mode"
[[ $(grep -Fc 'call' "$magick_log") == 2 ]] ||
  fail "terminal-art image decode count"
grep -Fqx -- '-limit' "$magick_log" || fail "terminal-art resource bounds"
if find "$media_dir" -maxdepth 1 -name '.qvos-terminal-art.*' -print -quit |
  grep -q .; then
  fail "terminal-art staging cleanup"
fi
pass "terminal art decodes twice and replaces a safe destination atomically"

printf 'preserve me\n' >"$ascii_output"
set +e
HOME="$test_home" PATH="$test_bin:/usr/bin" \
  QVOS_TEST_MAGICK_LOG="$magick_log" \
  QVOS_TEST_FAIL_RENDER=true \
  "$ascii_owner" "$ascii_input" "$ascii_output" --mode block >/dev/null 2>&1
render_status=$?
set -e
(( render_status == 1 )) || fail "terminal-art failure status"
[[ $(<"$ascii_output") == "preserve me" ]] ||
  fail "terminal-art failure preservation"
pass "failed terminal-art conversion preserves the prior destination"

symlink_target="$media_dir/foreign.txt"
symlink_output="$media_dir/linked.txt"
printf 'foreign\n' >"$symlink_target"
ln -s "$symlink_target" "$symlink_output"
if HOME="$test_home" PATH="$test_bin:/usr/bin" \
  "$ascii_owner" "$ascii_input" "$symlink_output" >/dev/null 2>&1; then
  fail "terminal-art symlink output"
fi
[[ $(<"$symlink_target") == "foreign" ]] ||
  fail "terminal-art symlink target preservation"
if HOME="$test_home" PATH="$test_bin:/usr/bin" \
  "$ascii_owner" "$ascii_input" "$ascii_input" >/dev/null 2>&1; then
  fail "terminal-art input replacement"
fi
pass "terminal art refuses links and its own input"

for invalid_args in \
  "$ascii_input|$media_dir/invalid.txt|--width|401" \
  "$ascii_input|$media_dir/invalid.txt|--height|201" \
  "$ascii_input|$media_dir/invalid.txt|--threshold|101" \
  "$ascii_input|$media_dir/invalid.txt|--mode|unknown" \
  "$ascii_input|$media_dir/invalid.txt|extra"; do
  IFS='|' read -r -a arguments <<<"$invalid_args"
  set +e
  HOME="$test_home" PATH="$test_bin:/usr/bin" \
    "$ascii_owner" "${arguments[@]}" >/dev/null 2>&1
  invalid_status=$?
  set -e
  (( invalid_status == 2 )) ||
    fail "terminal-art invalid arguments: $invalid_args"
done
set +e
HOME="$test_home" PATH="$test_bin:/usr/bin" \
  "$ascii_owner" "$ascii_input" "$media_dir/invalid.txt" --width \
  >/dev/null 2>&1
missing_value_status=$?
set -e
(( missing_value_status == 2 )) || fail "terminal-art missing option value"
pass "terminal-art dimensions, thresholds, modes, and arity are bounded"

env -u QVOS_PATH -u OMARCHY_PATH "$root/qvcore/transcode/check"
