#!/bin/bash

qvos_prayer_city="${QVOS_PRAYER_CITY:-6th of October City}"
qvos_prayer_country="${QVOS_PRAYER_COUNTRY:-Egypt}"
qvos_prayer_state="${QVOS_PRAYER_STATE:-}"
qvos_prayer_method="${QVOS_PRAYER_METHOD:-5}"
qvos_prayer_date_value="$(date +%d-%m-%Y)"
qvos_prayer_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/qvos"
qvos_prayer_cache_key="$(printf '%s-%s-%s-%s-%s' "$qvos_prayer_city" "$qvos_prayer_country" "$qvos_prayer_state" "$qvos_prayer_method" "$qvos_prayer_date_value" | tr ' /' '__')"
qvos_prayer_cache_file="$qvos_prayer_cache_dir/prayerbar-${qvos_prayer_cache_key}.json"
qvos_prayer_latest_cache_file="$qvos_prayer_cache_dir/prayerbar-latest.json"
qvos_prayers=("Fajr" "Sunrise" "Dhuhr" "Asr" "Maghrib" "Isha" "Midnight")

qvos_prayer_empty() {
  printf '{"text":"Prayer --:--","tooltip":"prayer times unavailable","class":"missing"}\n'
}

qvos_prayer_hijri_month() {
  case "$1" in
  1) printf 'Muharram' ;;
  2) printf 'Safar' ;;
  3) printf 'Rabi Al-Awwal' ;;
  4) printf 'Rabi Al-Thani' ;;
  5) printf 'Jumada Al-Awwal' ;;
  6) printf 'Jumada Al-Thani' ;;
  7) printf 'Rajab' ;;
  8) printf 'Shaban' ;;
  9) printf 'Ramadan' ;;
  10) printf 'Shawwal' ;;
  11) printf 'Dhu Al-Qidah' ;;
  12) printf 'Dhu Al-Hijjah' ;;
  *) jq -r '.data.date.hijri.month.en // empty' "$qvos_prayer_cache_file" ;;
  esac
}

qvos_prayer_fetch() {
  command -v curl >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1
  install -d "$qvos_prayer_cache_dir"

  local cache_is_fresh=false
  if [[ -f "$qvos_prayer_cache_file" ]]; then
    local now_epoch cache_epoch
    now_epoch="$(date +%s)"
    cache_epoch="$(stat -c %Y "$qvos_prayer_cache_file" 2>/dev/null || printf 0)"
    if ((now_epoch - cache_epoch < 10800)); then
      cache_is_fresh=true
    fi
  fi

  if [[ "$cache_is_fresh" == false ]]; then
    local curl_args=(
      -fs
      --connect-timeout 1
      --max-time 2
      --get
      "https://api.aladhan.com/v1/timingsByCity/$qvos_prayer_date_value"
      --data-urlencode "city=$qvos_prayer_city"
      --data-urlencode "country=$qvos_prayer_country"
      --data-urlencode "method=$qvos_prayer_method"
    )

    if [[ -n "$qvos_prayer_state" ]]; then
      curl_args+=(--data-urlencode "state=$qvos_prayer_state")
    fi

    local tmp_file
    tmp_file="$(mktemp "$qvos_prayer_cache_file.tmp.XXXXXX")"
    if ! curl "${curl_args[@]}" >"$tmp_file"; then
      rm -f "$tmp_file"
      qvos_prayer_use_stale_cache || return 1
    else
      if jq -e '.code == 200' "$tmp_file" >/dev/null 2>&1; then
        mv "$tmp_file" "$qvos_prayer_cache_file"
        cp -f "$qvos_prayer_cache_file" "$qvos_prayer_latest_cache_file"
      else
        rm -f "$tmp_file"
        qvos_prayer_use_stale_cache || return 1
      fi
    fi
  fi

  jq -e '.code == 200' "$qvos_prayer_cache_file" >/dev/null 2>&1
}

qvos_prayer_use_stale_cache() {
  if [[ -f "$qvos_prayer_cache_file" ]] && jq -e '.code == 200' "$qvos_prayer_cache_file" >/dev/null 2>&1; then
    return 0
  fi

  if [[ -f "$qvos_prayer_latest_cache_file" ]] && jq -e '.code == 200' "$qvos_prayer_latest_cache_file" >/dev/null 2>&1; then
    qvos_prayer_cache_file="$qvos_prayer_latest_cache_file"
    return 0
  fi

  return 1
}

qvos_prayer_hijri_line() {
  local hijri_day hijri_year hijri_month_number hijri_month
  hijri_day="$(jq -r '.data.date.hijri.day // empty' "$qvos_prayer_cache_file")"
  hijri_year="$(jq -r '.data.date.hijri.year // empty' "$qvos_prayer_cache_file")"
  hijri_month_number="$(jq -r '.data.date.hijri.month.number // empty' "$qvos_prayer_cache_file")"
  hijri_month="$(qvos_prayer_hijri_month "$hijri_month_number")"

  if [[ -n "$hijri_day" && -n "$hijri_month" && -n "$hijri_year" ]]; then
    printf '%s %s %s' "$hijri_day" "$hijri_month" "$hijri_year"
  fi
}

qvos_prayer_times_lines() {
  local prayer time_value hour minute hour_12
  for prayer in "${qvos_prayers[@]}"; do
    time_value="$(jq -r --arg prayer "$prayer" '.data.timings[$prayer] // empty' "$qvos_prayer_cache_file" | sed -E 's/ .*//')"
    [[ "$time_value" =~ ^[0-9]{2}:[0-9]{2}$ ]] || continue
    hour="${time_value%%:*}"
    minute="${time_value##*:}"
    hour_12="$((10#$hour % 12))"
    if ((hour_12 == 0)); then
      hour_12=12
    fi
    printf '%s %02d:%s\n' "$prayer" "$hour_12" "$minute"
  done
}
