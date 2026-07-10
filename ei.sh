#!/data/data/com.termux/files/usr/bin/bash

set -o pipefail

# ═══════════════════════════════════════════════════════
#  CONFIG
# ═══════════════════════════════════════════════════════

PACKAGE_PREFIX="free.no"
ROBLOX_URL="https://www.roblox.com/share?code=c398b5696d26e0449bb9c8e35be72152&type=Server"

CHECK_INTERVAL=10
CACHE_INTERVAL=3600
FREEZE_THRESHOLD=60
LAUNCH_TIMEOUT=45
MAX_RESTARTS=50

DISCORD_WEBHOOK="https://discord.com/api/webhooks/1483451715104804964/o0vgYLS-zg4WUXHQM-GiaT0idCfzz-bqPAqRXi4ME0xjEQusxdA3zmEdRQIzUiHovOb3"
DISCORD_PING_USER=""

TMP_DIR="/data/data/com.termux/files/usr/tmp"
PID_FILE="${TMP_DIR}/roblox_bot.pid"
STATE_FILE="${TMP_DIR}/roblox_state.json"

# ═══════════════════════════════════════════════════════
#  UTILS
# ═══════════════════════════════════════════════════════

discord() {
    local title="$1" desc="$2" color="${3:-3447003}" img="$4"
    [[ -z "$DISCORD_WEBHOOK" ]] && return
    local ping=""; [[ -n "$DISCORD_PING_USER" ]] && ping="<@$DISCORD_PING_USER> "
    if [[ -n "$img" && -f "$img" ]]; then
        local b="----BotBoundary$(date +%s)"
        { echo "--$b"; echo 'Content-Disposition: form-data; name="payload_json"'; echo 'Content-Type: application/json'; echo ""; echo "{\"content\":\"${ping}\",\"embeds\":[{\"title\":\"$title\",\"description\":\"$desc\",\"color\":$color,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"footer\":{\"text\":\"Roblox Bot\"}}]}"; echo "--$b"; echo 'Content-Disposition: form-data; name="file"; filename="s.png"'; echo 'Content-Type: image/png'; echo ""; cat "$img"; echo ""; echo "--$b--"; } | curl -s -X POST -H "Content-Type: multipart/form-data; boundary=$b" --data-binary @- "$DISCORD_WEBHOOK" >/dev/null 2>&1
    else
        curl -s -H "Content-Type: application/json" -X POST -d "{\"content\":\"${ping}\",\"embeds\":[{\"title\":\"$title\",\"description\":\"$desc\",\"color\":$color,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"footer\":{\"text\":\"Roblox Bot\"}}]}" "$DISCORD_WEBHOOK" >/dev/null 2>&1
    fi
}

ss() {
    local p="/sdcard/rb_$(date +%s).png"
    su -c "screencap -p $p" 2>/dev/null
    [[ -f "$p" ]] && echo "$p" || echo ""
}

# ═══════════════════════════════════════════════════════
#  STATE (JSON, safe parse)
# ═══════════════════════════════════════════════════════

state_load() {
    [[ -f "$STATE_FILE" ]] || return
    # Parse JSON simple: {"key":"value",...}
    local content
    content=$(cat "$STATE_FILE" 2>/dev/null)
    [[ -z "$content" ]] && return
    # Extract values dengan regex
    RESTARTS_TODAY=$(echo "$content" | grep -o '"restarts_[^"]*":"[0-9]*"' | grep "$(date +%Y%m%d)" | grep -o '[0-9]*$' || echo 0)
    LAST_CACHE=$(echo "$content" | grep -o '"last_cache":"[0-9]*"' | grep -o '[0-9]*$' || echo 0)
    CPU_SNAPSHOT=$(echo "$content" | grep -o '"cpu":"[^"]*"' | sed 's/.*:"//;s/"$//' || echo "")
    CPU_TIME=$(echo "$content" | grep -o '"cpu_time":"[0-9]*"' | grep -o '[0-9]*$' || echo 0)
}

state_save() {
    local r="${1:-0}" c="${2:-0}" cpu="${3:-}" ct="${4:-0}"
    echo "{\"restarts_$(date +%Y%m%d)\":\"$r\",\"last_cache\":\"$c\",\"cpu\":\"$cpu\",\"cpu_time\":\"$ct\"}" > "$STATE_FILE"
}

# ═══════════════════════════════════════════════════════
#  CHECKS (reliable)
# ═══════════════════════════════════════════════════════

alive() {
    local pkg="$1"
    # Cek 1: process ada & bukan zombie
    local pids
    pids=$(su -c "ps -A | grep '$pkg' | grep -v grep | awk '{print \$2}'" 2>/dev/null)
    [[ -z "$pids" ]] && return 1
    
    # Cek semua PID, kalau ada yang alive & bukan zombie → running
    local any_alive=0
    for pid in $pids; do
        local st
        st=$(su -c "cat /proc/$pid/stat 2>/dev/null | awk '{print \$3}'" 2>/dev/null)
        [[ "$st" == "Z" ]] && continue
        [[ -d "/proc/$pid" ]] && any_alive=1
    done
    [[ "$any_alive" == "0" ]] && return 1
    
    # Cek 2: activity state (RESUMED/PAUSED/STOPPED, bukan DESTROYED)
    local act
    act=$(su -c "dumpsys activity activities 2>/dev/null | grep -E '$pkg.*(Resumed|Paused|Stopped)' | grep -v ' finishing' | grep -v ' destroyed' | head -1" 2>/dev/null)
    [[ -n "$act" ]] && return 0
    
    # Cek 3: fallback window (kalau activity ga ketemu, cek window)
    su -c "dumpsys window windows 2>/dev/null | grep -q '$pkg'" 2>/dev/null
}

frozen() {
    local pkg="$1"
    local pids
    pids=$(su -c "ps -A | grep '$pkg' | grep -v grep | awk '{print \$2}'" 2>/dev/null)
    [[ -z "$pids" ]] && return 1
    
    # Ambil PID pertama yang bukan zombie
    local pid=""
    for p in $pids; do
        local st=$(su -c "cat /proc/$p/stat 2>/dev/null | awk '{print \$3}'" 2>/dev/null)
        [[ "$st" != "Z" ]] && { pid="$p"; break; }
    done
    [[ -z "$pid" ]] && return 1
    
    local cpu
    cpu=$(su -c "cat /proc/$pid/stat 2>/dev/null | awk '{print \$14+\$15}'" 2>/dev/null)
    [[ -z "$cpu" ]] && return 1
    
    state_load
    if [[ -n "$CPU_SNAPSHOT" && "$CPU_SNAPSHOT" == "$cpu" ]]; then
        [[ $(date +%s) - ${CPU_TIME:-0} -ge $FREEZE_THRESHOLD ]] && return 0
    else
        state_save "$RESTARTS_TODAY" "$LAST_CACHE" "$cpu" "$(date +%s)"
    fi
    return 1
}

# ═══════════════════════════════════════════════════════
#  ACTIONS
# ═══════════════════════════════════════════════════════

launch() {
    local pkg="$1" name="$2"
    alive "$pkg" && { discord "ℹ️ Info" "**$name** sudah running." 3447003; return 0; }
    
    # Kill & clear cache
    su -c "am force-stop $pkg 2>/dev/null"; sleep 2
    su -c "find /data/data/$pkg -maxdepth 1 -type d -iname '*cache*' -exec rm -rf {}/\* 2>/dev/null \;" 2>/dev/null
    [[ -d "/sdcard/Android/data/$pkg/cache" ]] && su -c "rm -rf /sdcard/Android/data/$pkg/cache/*" 2>/dev/null
    
    # Launch
    su -c "am start -a android.intent.action.VIEW -d '$ROBLOX_URL' -p $pkg" >/dev/null 2>&1
    
    # Wait with progress check
    local e=0
    while (( e < LAUNCH_TIMEOUT )); do
        alive "$pkg" && { discord "✅ Launched" "**$name** berhasil dibuka." 3066993; return 0; }
        sleep 3; ((e += 3))
    done
    discord "❌ Failed" "**$name** gagal dibuka dalam ${LAUNCH_TIMEOUT}s." 16711680
    return 1
}

# ═══════════════════════════════════════════════════════
#  MONITOR
# ═══════════════════════════════════════════════════════

monitor() {
    local pkg="$1" name="$2"
    state_load
    local r="${RESTARTS_TODAY:-0}"
    
    # Check crash
    if ! alive "$pkg"; then
        (( r >= MAX_RESTARTS )) && { discord "⚠️ Max" "**$name** skip ($r/$MAX_RESTARTS)." 15158332; return; }
        discord "💀 Crash" "**$name** crash! Restart..." 16711680 "$(ss)"
        launch "$pkg" "$name" && { state_save "$((r+1))" "$LAST_CACHE" "$CPU_SNAPSHOT" "$CPU_TIME"; discord "🚀 Restart" "**$name** ok. ($((r+1))/$MAX_RESTARTS)" 3066993; }
        return
    fi
    
    # Check freeze
    if frozen "$pkg"; then
        (( r >= MAX_RESTARTS )) && { discord "⚠️ Max" "**$name** skip freeze ($r/$MAX_RESTARTS)." 15158332; return; }
        discord "🥶 Freeze" "**$name** freeze! Restart..." 16711680 "$(ss)"
        launch "$pkg" "$name" && { state_save "$((r+1))" "$LAST_CACHE" "$CPU_SNAPSHOT" "$CPU_TIME"; discord "🚀 Restart" "**$name** ok (freeze)." 3066993; }
        return
    fi
    
    # Cache clear
    if [[ "$CACHE_INTERVAL" != "0" ]] && [[ $(date +%s) - ${LAST_CACHE:-0} -ge $CACHE_INTERVAL ]]; then
        discord "🧹 Cache" "**$name** cache clear." 3447003
        launch "$pkg" "$name" && { state_save "$r" "$(date +%s)" "$CPU_SNAPSHOT" "$CPU_TIME"; discord "🚀 Relaunch" "**$name** ok (cache)." 3066993; }
    fi
}

cleanup() {
    for pkg in "${PACKAGES[@]}"; do su -c "am force-stop $pkg 2>/dev/null"; done
    rm -f "$PID_FILE" "$STATE_FILE"
}

# ═══════════════════════════════════════════════════════
#  DAEMON
# ═══════════════════════════════════════════════════════

if [[ "$1" == "daemon" ]]; then
    echo $$ > "$PID_FILE"
    trap 'cleanup; discord "🛑 Stopped" "Bot off." 15158332; exit 0' SIGTERM SIGINT
    
    PACKAGES=()
    while IFS= read -r pkg; do PACKAGES+=("$pkg"); done < <(su -c "pm list packages" | grep "^package:${PACKAGE_PREFIX}" | sed 's/package://')
    [[ ${#PACKAGES[@]} -eq 0 ]] && { discord "❌ Error" "No packages found." 16711680; exit 1; }
    
    discord "🚀 Start" "Bot on: **${#PACKAGES[@]}** instances." 3066993
    
    for i in "${!PACKAGES[@]}"; do
        launch "${PACKAGES[$i]}" "${PACKAGES[$i]##*.}"
        (( i < ${#PACKAGES[@]} - 1 )) && sleep 5
    done
    
    while true; do
        for pkg in "${PACKAGES[@]}"; do monitor "$pkg" "${pkg##*.}"; done
        sleep "$CHECK_INTERVAL"
    done
    exit 0
fi

# ═══════════════════════════════════════════════════════
#  CLI
# ═══════════════════════════════════════════════════════

case "$1" in
    start)
        [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null && { discord "❌ Error" "Already running." 16711680; echo "❌ Running"; exit 1; }
        nohup bash "$0" daemon >/dev/null 2>&1 &
        sleep 1; [[ -f "$PID_FILE" ]] && { discord "✅ Start" "Daemon started." 3066993; echo "✅ Start"; } || { echo "❌ Fail"; exit 1; }
        ;;
    stop)
        [[ -f "$PID_FILE" ]] && { kill "$(cat "$PID_FILE")" 2>/dev/null; sleep 1; kill -9 "$(cat "$PID_FILE")" 2>/dev/null; }
        cleanup; discord "🛑 Stop" "Manual off." 15158332; echo "🛑 Stop"
        ;;
    restart) bash "$0" stop; sleep 2; bash "$0" start ;;
    status)
        [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null || { echo "🔴 Stop"; exit 0; }
        echo "🟢 Running"
        for pkg in "${PACKAGES[@]}"; do
            alive "$pkg" && echo "   🟢 ${pkg##*.}" || echo "   🔴 ${pkg##*.}"
        done
        ;;
    test-webhook)
        [[ -z "$DISCORD_WEBHOOK" ]] && { echo "❌ No webhook"; exit 1; }
        discord "🧪 Test" "Ok." 3447003; echo "✅ Sent"
        ;;
    test-screenshot)
        local s; s=$(ss); [[ -n "$s" ]] && { echo "✅ $s"; discord "🧪 SS" "Test." 3447003 "$s"; } || echo "❌ Fail"
        ;;
    reset-state) rm -f "$STATE_FILE"; echo "✅ Reset" ;;
    *) echo "🎮 RobloxBot | start|stop|restart|status|test-webhook|test-screenshot|reset-state" ;;
esac