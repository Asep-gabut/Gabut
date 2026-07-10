#!/data/data/com.termux/files/usr/bin/bash

set -o pipefail

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
STATE_FILE="${TMP_DIR}/roblox_state.db"

declare -A PACKAGES

# --- DISCORD ---

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

# --- SQLITE ---

db() { su -c "sqlite3 $STATE_FILE '$1' 2>/dev/null"; }

init_db() {
    [[ -f "$STATE_FILE" ]] || db "CREATE TABLE state(key TEXT PRIMARY KEY, value TEXT);"
}

get() { db "SELECT value FROM state WHERE key='$1';" || echo ""; }
set() { db "INSERT OR REPLACE INTO state(key,value) VALUES('$1','$2');" }

# --- THERMAL ---

thermal_off() {
    su -c "stop thermal-engine 2>/dev/null"
    su -c "stop thermald 2>/dev/null"
    su -c "stop vendor.thermal-engine 2>/dev/null"
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq; do
        su -c "echo performance > $cpu/scaling_governor 2>/dev/null"
    done
    su -c "echo 0 > /sys/class/kgsl/kgsl-3d0/throttling 2>/dev/null"
    su -c "echo 0 > /sys/class/kgsl/kgsl-3d0/bus_split 2>/dev/null"
    su -c "echo 1 > /sys/class/kgsl/kgsl-3d0/force_clk_on 2>/dev/null"
    su -c "echo 1 > /sys/class/kgsl/kgsl-3d0/force_bus_on 2>/dev/null"
    su -c "echo 1 > /sys/class/kgsl/kgsl-3d0/force_rail_on 2>/dev/null"
    su -c "stop power-hal-1-0 2>/dev/null"
    su -c "stop vendor.power-hal-1-0 2>/dev/null"
}

thermal_on() {
    su -c "start thermal-engine 2>/dev/null"
    su -c "start thermald 2>/dev/null"
    su -c "start vendor.thermal-engine 2>/dev/null"
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq; do
        su -c "echo schedutil > $cpu/scaling_governor 2>/dev/null"
    done
    su -c "echo 1 > /sys/class/kgsl/kgsl-3d0/throttling 2>/dev/null"
    su -c "echo 1 > /sys/class/kgsl/kgsl-3d0/bus_split 2>/dev/null"
    su -c "echo 0 > /sys/class/kgsl/kgsl-3d0/force_clk_on 2>/dev/null"
    su -c "echo 0 > /sys/class/kgsl/kgsl-3d0/force_bus_on 2>/dev/null"
    su -c "echo 0 > /sys/class/kgsl/kgsl-3d0/force_rail_on 2>/dev/null"
    su -c "start power-hal-1-0 2>/dev/null"
    su -c "start vendor.power-hal-1-0 2>/dev/null"
}

# --- CHECKS ---

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

frozen() {
    local pkg="$1" pid
    pid=$(su -c "pidof $pkg 2>/dev/null | awk '{print $1}'")
    [[ -z "$pid" ]] && return 1
    local cpu=$(su -c "cat /proc/$pid/stat 2>/dev/null | awk '{print \$14+\$15}'" 2>/dev/null)
    [[ -z "$cpu" ]] && return 1
    local last=$(get "cpu_$pkg")
    local last_t=$(get "cpu_t_$pkg")
    if [[ -n "$last" && "$last" == "$cpu" ]]; then
        local now=$(date +%s)
        local diff=$(( now - ${last_t:-0} ))
        [[ $diff -ge $FREEZE_THRESHOLD ]] && return 0
    else
        set "cpu_$pkg" "$cpu"
        set "cpu_t_$pkg" "$(date +%s)"
    fi
    return 1
}

# --- ACTIONS ---

launch() {
    local pkg="$1" name="$2"
    alive "$pkg" && { discord "ℹ️ Info" "**$name** sudah running." 3447003; return 0; }
    su -c "am force-stop $pkg 2>/dev/null"; sleep 2
    su -c "find /data/data/$pkg -maxdepth 1 -type d -iname '*cache*' -exec rm -rf {}/\* 2>/dev/null \;" 2>/dev/null
    [[ -d "/sdcard/Android/data/$pkg/cache" ]] && su -c "rm -rf /sdcard/Android/data/$pkg/cache/*" 2>/dev/null
    su -c "am start -a android.intent.action.VIEW -d '$ROBLOX_URL' -p $pkg" >/dev/null 2>&1
    local e=0
    while (( e < LAUNCH_TIMEOUT )); do
        alive "$pkg" && { discord "✅ Launched" "**$name** berhasil dibuka." 3066993; return 0; }
        sleep 3; ((e += 3))
    done
    discord "❌ Failed" "**$name** gagal dibuka." 16711680
    return 1
}

monitor() {
    local pkg="$1" name="$2"
    local r=$(get "r_$(date +%Y%m%d)_$pkg")
    r=${r:-0}
    
    if ! alive "$pkg"; then
        (( r >= MAX_RESTARTS )) && { discord "⚠️ Max" "**$name** skip ($r/$MAX_RESTARTS)." 15158332; return; }
        discord "💀 Crash" "**$name** crash! Restart..." 16711680 "$(ss)"
        launch "$pkg" "$name" && { set "r_$(date +%Y%m%d)_$pkg" "$((r+1))"; discord "🚀 Restart" "**$name** ok. ($((r+1))/$MAX_RESTARTS)" 3066993; }
        return
    fi
    
    if frozen "$pkg"; then
        (( r >= MAX_RESTARTS )) && { discord "⚠️ Max" "**$name** skip freeze ($r/$MAX_RESTARTS)." 15158332; return; }
        discord "🥶 Freeze" "**$name** freeze! Restart..." 16711680 "$(ss)"
        launch "$pkg" "$name" && { set "r_$(date +%Y%m%d)_$pkg" "$((r+1))"; discord "🚀 Restart" "**$name** ok (freeze)." 3066993; }
        return
    fi
    
    if [[ "$CACHE_INTERVAL" != "0" ]]; then
        local now=$(date +%s)
        local last_c=$(get "c_$pkg")
        local diff=$(( now - ${last_c:-0} ))
        if [[ $diff -ge $CACHE_INTERVAL ]]; then
            discord "🧹 Cache" "**$name** cache clear." 3447003
            launch "$pkg" "$name" && { set "c_$pkg" "$(date +%s)"; discord "🚀 Relaunch" "**$name** ok (cache)." 3066993; }
        fi
    fi
}

cleanup() {
    for pkg in "${!PACKAGES[@]}"; do su -c "am force-stop $pkg 2>/dev/null"; done
    thermal_on
    rm -f "$PID_FILE"
}

# --- DAEMON ---

if [[ "$1" == "daemon" ]]; then
    echo $$ > "$PID_FILE"
    init_db
    thermal_off
    trap 'cleanup; discord "🛑 Stopped" "Bot off. Thermal restored." 15158332; exit 0' SIGTERM SIGINT
    
    while IFS= read -r pkg; do PACKAGES["$pkg"]="${pkg##*.}"; done < <(su -c "pm list packages" | grep "^package:${PACKAGE_PREFIX}" | sed 's/package://')
    [[ ${#PACKAGES[@]} -eq 0 ]] && { discord "❌ Error" "No packages found." 16711680; exit 1; }
    
    discord "🚀 Start" "Bot on: **${#PACKAGES[@]}** instances.\n🔥 Thermal: DISABLED" 3066993
    
    local i=0
    for pkg in "${!PACKAGES[@]}"; do
        launch "$pkg" "${PACKAGES[$pkg]}"
        (( i++ )); (( i < ${#PACKAGES[@]} )) && sleep 5
    done
    
    while true; do
        for pkg in "${!PACKAGES[@]}"; do monitor "$pkg" "${PACKAGES[$pkg]}"; done
        sleep "$CHECK_INTERVAL"
    done
    exit 0
fi

# --- CLI ---

case "$1" in
    start)
        [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null && { echo "❌ Running"; exit 1; }
        nohup bash "$0" daemon >/dev/null 2>&1 &
        sleep 1; [[ -f "$PID_FILE" ]] && echo "✅ Start" || echo "❌ Fail"
        ;;
    stop)
        [[ -f "$PID_FILE" ]] && { kill "$(cat "$PID_FILE")" 2>/dev/null; sleep 1; kill -9 "$(cat "$PID_FILE")" 2>/dev/null; }
        cleanup; discord "🛑 Stop" "Manual off. Thermal restored." 15158332; echo "🛑 Stop"
        ;;
    restart) bash "$0" stop; sleep 2; bash "$0" start ;;
    status)
        [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null || { echo "🔴 Stop"; exit 0; }
        echo "🟢 Running"
        for pkg in "${!PACKAGES[@]}"; do alive "$pkg" && echo "   🟢 ${PACKAGES[$pkg]}" || echo "   🔴 ${PACKAGES[$pkg]}"; done
        ;;
    thermal-off) thermal_off; echo "🔥 Thermal disabled" ;;
    thermal-on) thermal_on; echo "❄️ Thermal restored" ;;
    test-webhook) [[ -z "$DISCORD_WEBHOOK" ]] && { echo "❌ No webhook"; exit 1; }; discord "🧪 Test" "Ok." 3447003; echo "✅ Sent" ;;
    test-screenshot) local s; s=$(ss); [[ -n "$s" ]] && { echo "✅ $s"; discord "🧪 SS" "Test." 3447003 "$s"; } || echo "❌ Fail" ;;
    reset-state) rm -f "$STATE_FILE"; echo "✅ Reset" ;;
    *) echo "🎮 RobloxBot | start|stop|restart|status|thermal-off|thermal-on|test-webhook|test-screenshot|reset-state" ;;
esac