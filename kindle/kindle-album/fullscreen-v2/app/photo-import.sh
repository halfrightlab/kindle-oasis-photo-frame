#!/bin/sh
# Runs inside the RAM-backed album session. Never takes input or changes power.
photo_import_status=idle
photo_import_running=0
photo_import_notice_until=0
photos=/mnt/us/Photos
koreader=/mnt/us/koreader

photo_import_start() {
  [ -d "$photos" ] || return 0
  import_found=0
  for import_source in "$photos"/*; do
    case "$import_source" in
      *.[jJ][pP][gG]|*.[jJ][pP][eE][gG]|*.[pP][nN][gG])
        if [ -f "$import_source" ] && [ ! -L "$import_source" ]; then import_found=1; break; fi;;
    esac
  done
  [ "$import_found" = 1 ] || return 0
  if [ ! -x "$koreader/luajit" ]; then
    photo_import_status=warning
    photo_import_notice_until=$(($(date +%s)+8))
    printf 'photo_import_unavailable=yes\n' >> "$base/session.log"
    return 0
  fi
  (
    cd "$koreader" || exit 1
    LD_LIBRARY_PATH="$koreader/libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
      exec "$koreader/luajit" "$runtime/photo-import.lua" "$photos" "$base" "$app" "$runtime"
  ) > "$runtime/import-log" 2>&1 < /dev/null &
  import_pid=$!
  printf '%s\n' "$import_pid" > "$runtime/import-pid"
  awk '{print $22}' "/proc/$import_pid/stat" > "$runtime/import-start" 2>/dev/null || :
  photo_import_running=1
  photo_import_status=working
  printf 'photo_import_started=yes\n' >> "$base/session.log"
}

photo_import_activate() {
  [ -f "$runtime/import-pending" ] || return 0
  cmp -s "$base/slides.txt" "$runtime/import-original" || return 1
  import_count=$(wc -l < "$runtime/import-pending" | tr -d ' ')
  case "$import_count" in ''|*[!0-9]*) return 1;; esac
  [ "$import_count" -ge 1 ] && [ "$import_count" -le 500 ] || return 1
  while IFS= read -r import_prefix; do
    case "$import_prefix" in ''|*[!A-Za-z0-9_-]*) return 1;; esac
    for import_layout in crop contain; do
      for import_variant in clean 10 30 60 300; do
        [ -f "$base/assets/$import_prefix-$import_layout-$import_variant.png" ] || return 1
      done
    done
  done < "$runtime/import-pending"
  require_media
  mkdir -p "$base/import-backups" || return 1
  cp "$base/slides.txt" "$base/import-backups/$(date +%s)-$$.txt" || return 1
  cp "$runtime/import-pending" "$base/slides.next" || return 1
  mv "$base/slides.next" "$base/slides.txt" || return 1
  count=$import_count
  index=1
  ui_init "$(date +%s)"
  printf 'photo_import_playlist_activated=yes count=%s\n' "$count" >> "$base/session.log"
}

photo_import_poll() {
  # An import may finish in real suspend. Activate only after the existing
  # native-exit gate has restored the active album, keeping its lock photo.
  [ "$power_phase" = active ] || return 0
  if [ "$photo_import_running" = 1 ]; then
    import_finished=0
    import_failed=1
    if [ -f "$runtime/import-ready" ]; then
      if IFS=' ' read -r import_added import_failed import_duplicate import_total < "$runtime/import-result"; then
        for import_number in "$import_added" "$import_failed" "$import_duplicate" "$import_total"; do
          case "$import_number" in ''|*[!0-9]*) import_failed=1; break;; esac
        done
        if photo_import_activate; then
          printf 'photo_import_completed=yes added=%s failed=%s duplicate=%s total=%s\n' \
            "$import_added" "$import_failed" "$import_duplicate" "$import_total" >> "$base/session.log"
        else
          import_failed=1
          printf 'photo_import_activation_failed=yes\n' >> "$base/session.log"
        fi
      fi
      import_finished=1
    elif ! kill -0 "$import_pid" 2>/dev/null; then
      printf 'photo_import_worker_exited_without_result=yes\n' >> "$base/session.log"
      import_finished=1
    fi
    if [ "$import_finished" = 1 ]; then
      photo_import_running=0
      photo_import_status=idle
      if [ "$import_failed" != 0 ]; then
        photo_import_status=warning
        photo_import_notice_until=$(($(date +%s)+8))
      fi
      render_needed=1
    fi
  elif [ "$photo_import_status" = warning ] && [ "$(date +%s)" -ge "$photo_import_notice_until" ]; then
    photo_import_status=idle
    render_needed=1
  fi
}
