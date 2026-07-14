#!/data/data/com.termux/files/usr/bin/bash

set -o pipefail

PACKAGE_PREFIX="free.no"
ROBLOX_URL="https://www.roblox.com/share?code=c398b5696d26e0449bb9c8e35be72152&type=Server"

CHECK_INTERVAL=2
CACHE_INTERVAL=60

DISCORD_WEBHOOK="https://discord.com/api/webhooks/1483451715104804964/o0vgYLS-zg4WUXHQM-GiaT0idCfzz-bqPAqRXi4ME0xjEQusxdA3zmEdRQIzUiHovOb3"
DISCORD_PING_USER=""

TMP_DIR="/data/data/com.termux/files/usr/tmp"
PID_FILE="${TMP_DIR}/roblox_bot.pid"
STATE_FILE="${TMP_DIR}/roblox_state.db"

ALLOWED_PKGS=("com.termux" "$PACKAGE_PREFIX")

# ============================================================
# INIT PACKAGES (dipanggil di semua mode yang butuh)
# ============================================================
init_packages() {
    PACKAGES=()
    while IFS= read -r pkg; do PACKAGES+=("$pkg"); done < <(su -c "pm list packages" 2>/dev/null | grep "^package:${PACKAGE_PREFIX}" 2>/dev/null | sed 's/package://')
}

# ============================================================
# DISCORD - Kirim embed + screenshot (langsung hapus file)
# ============================================================
discord() {
    local title="$1" desc="$2" color="${3:-3447003}" img="$4"
    [[ -z "$DISCORD_WEBHOOK" ]] && return

    local ping=""
    [[ -n "$DISCORD_PING_USER" ]] && ping="<@$DISCORD_PING_USER> "

    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    if [[ -n "$img" && -f "$img" ]]; then
        local b="----BotBoundary$(date +%s)"
        {
            echo "--$b"
            echo 'Content-Disposition: form-data; name="payload_json"'
            echo 'Content-Type: application/json'
            echo ""
            echo "{\"content\":\"${ping}\",\"embeds\":[{\"title\":\"$title\",\"description\":\"$desc\",\"color\":$color,\"timestamp\":\"$ts\",\"footer\":{\"text\":\"Roblox Bot\"}}]}"
            echo "--$b"
            echo 'Content-Disposition: form-data; name="file"; filename="screenshot.png"'
            echo 'Content-Type: image/png'
            echo ""
            cat "$img"
            echo ""
            echo "--$b--"
        } | curl -s -X POST -H "Content-Type: multipart/form-data; boundary=$b" --data-binary @- "$DISCORD_WEBHOOK" >/dev/null 2>&1

        # HAPUS SCREENSHOT SETELAH KIRIM - NGGAK ADA JEJAK DI HP
        rm -f "$img"
    else
        curl -s -H "Content-Type: application/json" -X POST -d "{\"content\":\"${ping}\",\"embeds\":[{\"title\":\"$title\",\"description\":\"$desc\",\"color\":$color,\"timestamp\":\"$ts\",\"footer\":{\"text\":\"Roblox Bot\"}}]}" "$DISCORD_WEBHOOK" >/dev/null 2>&1 &
    fi
}

# ============================================================
# SCREENSHOT - Simpan ke TMP_DIR doang, nggak ke sdcard
# ============================================================
ss() {
    local p="${TMP_DIR}/rb_$(date +%s)_$$.png"
    su -c "screencap -p $p" 2>/dev/null
    [[ -f "$p" ]] && echo "$p" || echo ""
}

# ============================================================
# SQLITE STATE DB
# ============================================================
db() { su -c "sqlite3 $STATE_FILE '$1' 2>/dev/null"; }
init_db() { [[ -f "$STATE_FILE" ]] || db "CREATE TABLE state(key TEXT PRIMARY KEY, value TEXT);"; }
get() { db "SELECT value FROM state WHERE key='$1';" || echo ""; }
set() { db "INSERT OR REPLACE INTO state(key,value) VALUES('$1','$2');"; }

# ============================================================
# CHECK APP ALIVE
# ============================================================
alive() {
    local pkg="$1" pids
    pids=$(su -c "ps -A | grep '$pkg' | grep -v grep | awk '{print \$2}'" 2>/dev/null)
    [[ -z "$pids" ]] && return 1

    for pid in $pids; do
        local st=$(su -c "cat /proc/$pid/stat 2>/dev/null | awk '{print \$3}'" 2>/dev/null)
        [[ "$st" == "Z" ]] && continue
        [[ -d "/proc/$pid" ]] && break
    done

    local act=$(su -c "dumpsys activity activities 2>/dev/null | grep -E '$pkg.*(Resumed|Paused|Stopped)' | grep -v ' finishing' | grep -v ' destroyed' | head -1" 2>/dev/null)
    [[ -n "$act" ]] && return 0

    su -c "dumpsys window windows 2>/dev/null | grep -q '$pkg'" 2>/dev/null
}

# ============================================================
# PROTECT APP (anti-kill, priority tinggi)
# ============================================================
protect_app() {
    local pkg="$1"
    local pid=$(su -c "pidof $pkg 2>/dev/null")
    [[ -z "$pid" ]] && return

    su -c "dumpsys deviceidle whitelist +$pkg 2>/dev/null"
    su -c "echo -1000 > /proc/$pid/oom_score_adj 2>/dev/null"
    su -c "chrt -f -p 99 $pid 2>/dev/null"
    su -c "taskset -p 0xF0 $pid 2>/dev/null"
    su -c "am set-inactive $pkg false 2>/dev/null"
    su -c "cmd appops set $pkg RUN_ANY_IN_BACKGROUND allow 2>/dev/null"
    su -c "cmd appops set $pkg RUN_IN_BACKGROUND allow 2>/dev/null"
    su -c "cmd deviceidle whitelist +$pkg 2>/dev/null"
}

# ============================================================
# LAUNCH APP
# ============================================================
launch() {
    local pkg="$1" name="$2"
    alive "$pkg" && return 0
    su -c "am start -a android.intent.action.VIEW -d '$ROBLOX_URL' -p $pkg" >/dev/null 2>&1
}

# ============================================================
# CLEAR CACHE - FIX BUG rm -rf {}/\* jadi proper delete
# ============================================================
clear_cache() {
    local pkg="$1"

    su -c "find /data/data/$pkg -maxdepth 2 -type d \( -name 'cache' -o -name 'code_cache' \) 2>/dev/null | while read d; do
        # Skip kalau folder ada file session-related
        case \"\$d\" in
            *session*|*auth*|*login*) continue ;;
        esac
        rm -rf \"\$d\"/* 2>/dev/null
    done" 2>/dev/null
}
# ============================================================
# KILL UNWANTED APPS
# ============================================================
kill_unwanted() {
    local pkg
    while IFS= read -r pkg; do
        pkg="${pkg#package:}"
        local allowed=0
        for a in "${ALLOWED_PKGS[@]}"; do
            [[ "$pkg" == "$a"* ]] && { allowed=1; break; }
        done
        [[ $allowed -eq 0 ]] && su -c "am force-stop '$pkg' 2>/dev/null" 2>/dev/null
    done < <(su -c "pm list packages -3" 2>/dev/null)
}

# ============================================================
# MONITOR LOOP
# ============================================================
monitor() {
    local pkg="$1" name="$2"

    if ! alive "$pkg"; then
        discord "💀 Crash" "**$name** crash! Restarting..." 16711680 "$(ss)"
        launch "$pkg" "$name"
        return
    fi

    if [[ "$CACHE_INTERVAL" != "0" ]]; then
        local now=$(date +%s)
        local last_c=$(get "c_$pkg")
        local diff=$(( now - ${last_c:-0} ))
        if [[ $diff -ge $CACHE_INTERVAL ]]; then
            clear_cache "$pkg"
            set "c_$pkg" "$(date +%s)"
        fi
    fi

    protect_app "$pkg"
}

# ============================================================
# CLEANUP - FIX: init_packages dulu biar PACKAGES keisi
# ============================================================
cleanup() {
    init_packages
    for pkg in "${PACKAGES[@]}"; do su -c "am force-stop $pkg 2>/dev/null"; done
    rm -f "$PID_FILE"
    # Bersihin screenshot sisa di TMP_DIR
    rm -f "${TMP_DIR}"/rb_*.png 2>/dev/null
}

# ============================================================
# DAEMON MODE
# ============================================================
if [[ "$1" == "daemon" ]]; then
    echo $$ > "$PID_FILE"
    init_db
    init_packages
    trap 'cleanup; exit 0' SIGTERM SIGINT

    [[ ${#PACKAGES[@]} -eq 0 ]] && { echo "No packages found."; exit 1; }

    for pkg in "${PACKAGES[@]}"; do
        su -c "am force-stop $pkg 2>/dev/null"
    done
    sleep 2

    local i=0
    for pkg in "${PACKAGES[@]}"; do
        launch "$pkg" "${pkg##*.}"
        (( i++ )); (( i < ${#PACKAGES[@]} )) && sleep 30
    done

    while true; do
        kill_unwanted
        for pkg in "${PACKAGES[@]}"; do monitor "$pkg" "${pkg##*.}"; done
        sleep "$CHECK_INTERVAL"
    done
    exit 0
fi

# ============================================================
# START
# ============================================================
if [[ "$1" == "start" ]]; then
    [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null && { echo "❌ Already running"; exit 1; }
    nohup bash "$0" daemon >/dev/null 2>&1 &
    sleep 1
    [[ -f "$PID_FILE" ]] && echo "✅ Started" || echo "❌ Failed to start"
    exit 0
fi

# ============================================================
# STOP - FIX: init_packages biar PACKAGES keisi
# ============================================================
if [[ "$1" == "stop" ]]; then
    init_packages
    [[ -f "$PID_FILE" ]] && { kill "$(cat "$PID_FILE")" 2>/dev/null; sleep 1; kill -9 "$(cat "$PID_FILE")" 2>/dev/null; }
    cleanup
    echo "🛑 Stopped"
    exit 0
fi

# ============================================================
# RESTART
# ============================================================
if [[ "$1" == "restart" ]]; then
    bash "$0" stop; sleep 2; bash "$0" start
    exit 0
fi

# ============================================================
# STATUS - FIX: init_packages biar PACKAGES keisi
# ============================================================
if [[ "$1" == "status" ]]; then
    init_packages
    [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null || { echo "🔴 Stopped"; exit 0; }
    echo "🟢 Running"
    for pkg in "${PACKAGES[@]}"; do alive "$pkg" && echo "   🟢 ${pkg##*.}" || echo "   🔴 ${pkg##*.}"; done
    exit 0
fi

# ============================================================
# TEST WEBHOOK
# ============================================================
if [[ "$1" == "test-webhook" ]]; then
    [[ -z "$DISCORD_WEBHOOK" ]] && { echo "❌ No webhook configured"; exit 1; }
    discord "🧪 Test" "Webhook working!" 3447003
    echo "✅ Sent"
    exit 0
fi

# ============================================================
# TEST SCREENSHOT - Langsung kirim ke DC, nggak simpen di HP
# ============================================================
if [[ "$1" == "test-screenshot" ]]; then
    local s
    s=$(ss)
    if [[ -n "$s" ]]; then
        discord "🧪 Screenshot Test" "Screenshot captured and sent." 3447003 "$s"
        echo "✅ Sent to Discord"
    else
        echo "❌ Failed to capture"
    fi
    exit 0
fi

# ============================================================
# RESET STATE
# ============================================================
if [[ "$1" == "reset-state" ]]; then
    rm -f "$STATE_FILE"
    rm -f "${TMP_DIR}"/rb_*.png 2>/dev/null
    echo "✅ State reset"
    exit 0
fi

# ============================================================
# HELP
# ============================================================
echo "🎮 RobloxBot | Usage:"
echo "  start          - Start daemon"
echo "  stop           - Stop daemon & kill Roblox"
echo "  restart        - Restart daemon"
echo "  status         - Check status"
echo "  test-webhook   - Test Discord webhook"
echo "  test-screenshot - Test screenshot (sends to DC, no local save)"
echo "  reset-state    - Reset state DB"