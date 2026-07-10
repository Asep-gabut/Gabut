#!/data/data/com.termux/files/usr/bin/bash

set -o pipefail

PACKAGE_PREFIX="free.no"
ROBLOX_URL="https://www.roblox.com/share?code=c398b5696d26e0449bb9c8e35be72152&type=Server"

CHECK_INTERVAL=3
CACHE_INTERVAL=3

DISCORD_WEBHOOK="https://discord.com/api/webhooks/1483451715104804964/o0vgYLS-zg4WUXHQM-GiaT0idCfzz-bqPAqRXi4ME0xjEQusxdA3zmEdRQIzUiHovOb3"
DISCORD_PING_USER=""

TMP_DIR="/data/data/com.termux/files/usr/tmp"
PID_FILE="${TMP_DIR}/roblox_bot.pid"
STATE_FILE="${TMP_DIR}/roblox_state.db"

ALLOWED_PKGS=("com.termux" "$PACKAGE_PREFIX")

discord() {
    local title="$1" desc="$2" color="${3:-3447003}" img="$4"
    [[ -z "$DISCORD_WEBHOOK" ]] && return
    local ping=""
    [[ -n "$DISCORD_PING_USER" ]] && ping="<@$DISCORD_PING_USER> "
    if [[ -n "$img" && -f "$img" ]]; then
        local b="----BotBoundary$(date +%s)"
        {
            echo "--$b"
            echo 'Content-Disposition: form-data; name="payload_json"'
            echo 'Content-Type: application/json'
            echo ""
            echo "{\"content\":\"${ping}\",\"embeds\":[{\"title\":\"$title\",\"description\":\"$desc\",\"color\":$color,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"footer\":{\"text\":\"Roblox Bot\"}}]}"
            echo "--$b"
            echo 'Content-Disposition: form-data; name="file"; filename="s.png"'
            echo 'Content-Type: image/png'
            echo ""
            cat "$img"
            echo ""
            echo "--$b--"
        } | curl -s -X POST -H "Content-Type: multipart/form-data; boundary=$b" --data-binary @- "$DISCORD_WEBHOOK" >/dev/null 2>&1 &
    else
        curl -s -H "Content-Type: application/json" -X POST -d "{\"content\":\"${ping}\",\"embeds\":[{\"title\":\"$title\",\"description\":\"$desc\",\"color\":$color,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"footer\":{\"text\":\"Roblox Bot\"}}]}" "$DISCORD_WEBHOOK" >/dev/null 2>&1 &
    fi
}

ss() {
    local p="/sdcard/rb_$(date +%s).png"
    su -c "screencap -p $p" 2>/dev/null
    [[ -f "$p" ]] && echo "$p" || echo ""
}

db() { su -c "sqlite3 $STATE_FILE '$1' 2>/dev/null"; }
init_db() { [[ -f "$STATE_FILE" ]] || db "CREATE TABLE state(key TEXT PRIMARY KEY, value TEXT);"; }
get() { db "SELECT value FROM state WHERE key='$1';" || echo ""; }
set() { db "INSERT OR REPLACE INTO state(key,value) VALUES('$1','$2');"; }

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

# Anti-FC: whitelist dari Doze + lock OOM score
protect_app() {
    local pkg="$1"
    # Whitelist dari Doze mode
    su -c "dumpsys deviceidle whitelist +$pkg 2>/dev/null"
    # Cari PID Roblox, set OOM score paling rendah (gak di-kill)
    local pid=$(su -c "pidof $pkg 2>/dev/null")
    if [[ -n "$pid" ]]; then
        su -c "echo -17 > /proc/$pid/oom_score_adj 2>/dev/null"
    fi
}

launch() {
    local pkg="$1" name="$2"
    alive "$pkg" && return 0
    su -c "am start -a android.intent.action.VIEW -d '$ROBLOX_URL' -p $pkg" >/dev/null 2>&1
}

clear_cache() {
    local pkg="$1"
    su -c "find /data/data/$pkg -maxdepth 1 -type d -iname '*cache*' -exec rm -rf {}/\* 2>/dev/null \;" 2>/dev/null
    [[ -d "/sdcard/Android/data/$pkg/cache" ]] && su -c "rm -rf /sdcard/Android/data/$pkg/cache/*" 2>/dev/null
}

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

monitor() {
    local pkg="$1" name="$2"
    
    # Clear cache tiap 3 detik tanpa relaunch
    if [[ "$CACHE_INTERVAL" != "0" ]]; then
        local now=$(date +%s)
        local last_c=$(get "c_$pkg")
        local diff=$(( now - ${last_c:-0} ))
        if [[ $diff -ge $CACHE_INTERVAL ]]; then
            clear_cache "$pkg"
            set "c_$pkg" "$(date +%s)"
        fi
    fi
    
    # Protect dari FC (Doze whitelist + OOM lock)
    protect_app "$pkg"
}

cleanup() {
    for pkg in "${PACKAGES[@]}"; do su -c "am force-stop $pkg 2>/dev/null"; done
    rm -f "$PID_FILE"
}

if [[ "$1" == "daemon" ]]; then
    echo $$ > "$PID_FILE"
    init_db
    trap 'cleanup; exit 0' SIGTERM SIGINT
    
    PACKAGES=()
    while IFS= read -r pkg; do PACKAGES+=("$pkg"); done < <(su -c "pm list packages" | grep "^package:${PACKAGE_PREFIX}" | sed 's/package://')
    [[ ${#PACKAGES[@]} -eq 0 ]] && { echo "No packages found."; exit 1; }
    
    # Force-stop sekali pas awal
    for pkg in "${PACKAGES[@]}"; do
        su -c "am force-stop $pkg 2>/dev/null"
    done
    sleep 2
    
    # Buka Roblox sekali doang
    local i=0
    for pkg in "${PACKAGES[@]}"; do
        launch "$pkg" "${pkg##*.}"
        (( i++ )); (( i < ${#PACKAGES[@]} )) && sleep 20
    done
    
    # Loop: kill unwanted apps + clear cache + protect dari FC
    while true; do
        kill_unwanted
        for pkg in "${PACKAGES[@]}"; do monitor "$pkg" "${pkg##*.}"; done
        sleep "$CHECK_INTERVAL"
    done
    exit 0
fi

if [[ "$1" == "start" ]]; then
    [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null && { echo "❌ Running"; exit 1; }
    nohup bash "$0" daemon >/dev/null 2>&1 &
    sleep 1; [[ -f "$PID_FILE" ]] && echo "✅ Start" || echo "❌ Fail"
    exit 0
fi

if [[ "$1" == "stop" ]]; then
    [[ -f "$PID_FILE" ]] && { kill "$(cat "$PID_FILE")" 2>/dev/null; sleep 1; kill -9 "$(cat "$PID_FILE")" 2>/dev/null; }
    cleanup; echo "🛑 Stop"
    exit 0
fi

if [[ "$1" == "restart" ]]; then
    bash "$0" stop; sleep 2; bash "$0" start
    exit 0
fi

if [[ "$1" == "status" ]]; then
    [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null || { echo "🔴 Stop"; exit 0; }
    echo "🟢 Running"
    for pkg in "${PACKAGES[@]}"; do alive "$pkg" && echo "   🟢 ${pkg##*.}" || echo "   🔴 ${pkg##*.}"; done
    exit 0
fi

if [[ "$1" == "test-webhook" ]]; then
    [[ -z "$DISCORD_WEBHOOK" ]] && { echo "❌ No webhook"; exit 1; }
    discord "🧪 Test" "Ok." 3447003; echo "✅ Sent"
    exit 0
fi

if [[ "$1" == "test-screenshot" ]]; then
    local s; s=$(ss); [[ -n "$s" ]] && { echo "✅ $s"; discord "🧪 SS" "Test." 3447003 "$s"; } || echo "❌ Fail"
    exit 0
fi

if [[ "$1" == "reset-state" ]]; then
    rm -f "$STATE_FILE"; echo "✅ Reset"; exit 0
fi

echo "🎮 RobloxBot | start|stop|restart|status|test-webhook|test-screenshot|reset-state"