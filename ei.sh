#!/data/data/com.termux/files/usr/bin/bash

INSTANCES=(
   "free.nokaA|https://www.roblox.com/share?code=c398b5696d26e0449bb9c8e35be72152&type=Server|Bot1"
   "free.nokaB|https://www.roblox.com/share?code=c398b5696d26e0449bb9c8e35be72152&type=Server|Bot2"
)

CHECK_INTERVAL="10"
CACHE_INTERVAL="3600"
FREEZE_THRESHOLD="60"
MAX_RESTARTS="50"
LOG_MAX_SIZE="5242880"  # 5MB
DISCORD_TIMEOUT="5"     # 5 detik

DISCORD_WEBHOOK="https://discord.com/api/webhooks/1483451715104804964/o0vgYLS-zg4WUXHQM-GiaT0idCfzz-bqPAqRXi4ME0xjEQusxdA3zmEdRQIzUiHovOb3"
DISCORD_PING_USER=""

PID_FILE="/data/data/com.termux/files/usr/tmp/roblox_bot.pid"
LOG_FILE="/sdcard/roblox_bot.log"
STATE_FILE="/data/data/com.termux/files/usr/tmp/roblox_state"
SCRIPT_PATH="$(realpath "$0")"

declare -A INSTANCE_STATE
declare -A LAST_FOREGROUND_TIME

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
    
    # 🔧 Auto-rotate log kalau sudah > 5MB
    [[ -f "$LOG_FILE" ]] && {
        local size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null)
        if (( size > LOG_MAX_SIZE )); then
            mv "$LOG_FILE" "$LOG_FILE.$(date +%s)"
            log "📋 Log rotated"
        fi
    }
}

discord_send() {
    local title="$1"
    local description="$2"
    local color="$3"
    local image_path="$4"
    [[ -z "$DISCORD_WEBHOOK" ]] && return
    local ping=""
    [[ -n "$DISCORD_PING_USER" ]] && ping="<@$DISCORD_PING_USER> "
    
    if [[ -n "$image_path" && -f "$image_path" ]]; then
        local boundary="----BotBoundary$(date +%s)"
        {
            echo "--$boundary"
            echo 'Content-Disposition: form-data; name="payload_json"'
            echo 'Content-Type: application/json'
            echo ""
            echo "{\"content\":\"${ping}\",\"embeds\":[{\"title\":\"$title\",\"description\":\"$description\",\"color\":$color,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"footer\":{\"text\":\"Roblox Bot • Termux\"}}]}"
            echo "--$boundary"
            echo 'Content-Disposition: form-data; name="file"; filename="screenshot.png"'
            echo 'Content-Type: image/png'
            echo ""
            cat "$image_path"
            echo ""
            echo "--$boundary--"
        } | timeout "$DISCORD_TIMEOUT" curl -s -X POST -H "Content-Type: multipart/form-data; boundary=$boundary" --data-binary @- "$DISCORD_WEBHOOK" >/dev/null 2>&1 &
    else
        local json="{\"content\":\"${ping}\",\"embeds\":[{\"title\":\"$title\",\"description\":\"$description\",\"color\":$color,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"footer\":{\"text\":\"Roblox Bot • Termux\"}}]}"
        timeout "$DISCORD_TIMEOUT" curl -s -H "Content-Type: application/json" -X POST -d "$json" "$DISCORD_WEBHOOK" >/dev/null 2>&1 &
    fi
}

take_screenshot() {
    local path="/sdcard/roblox_crash_$(date +%s).png"
    su -c "screencap -p $path" 2>/dev/null
    [[ -f "$path" ]] && echo "$path" || echo ""
}

if ! su -c "id" >/dev/null 2>&1; then
    echo "❌ Root access denied!"
    exit 1
fi

load_state() {
    [[ -f "$STATE_FILE" ]] && source "$STATE_FILE" 2>/dev/null
}

save_state() {
    {
        echo "# Roblox Bot State — $(date)"
        for key in "${!INSTANCE_STATE[@]}"; do
            echo "INSTANCE_STATE[$key]=\"${INSTANCE_STATE[$key]}\""
        done
        # 🔧 Save foreground time tracking
        for key in "${!LAST_FOREGROUND_TIME[@]}"; do
            echo "LAST_FOREGROUND_TIME[$key]=\"${LAST_FOREGROUND_TIME[$key]}\""
        done
    } > "$STATE_FILE"
}

# 🔧 Helper untuk check + reset daily counter
get_today_restarts() {
    local idx="$1"
    local today=$(date +%Y%m%d)
    local today_key="day_${idx}_${today}"
    echo "${INSTANCE_STATE[$today_key]:-0}"
}

set_today_restarts() {
    local idx="$1"
    local count="$2"
    local today=$(date +%Y%m%d)
    local today_key="day_${idx}_${today}"
    INSTANCE_STATE["$today_key"]="$count"
}

is_running() {
    local pkg="$1"
    local pid
    pid=$(su -c "pidof $pkg" 2>/dev/null)
    
    [[ -z "$pid" ]] && return 1
    
    local state
    state=$(su -c "cat /proc/$pid/stat 2>/dev/null | awk '{print \$3}'" 2>/dev/null)
    [[ "$state" == "Z" ]] && return 1
    
    local foreground_pid
    foreground_pid=$(su -c "dumpsys window windows 2>/dev/null | grep -i 'mCurrentFocus' | grep -o 'u0 $pkg' | head -1" 2>/dev/null)
    
    if [[ -z "$foreground_pid" ]]; then
        local now=$(date +%s)
        local last_fg="${LAST_FOREGROUND_TIME[$pkg]:-$((now - 180))}"
        
        if (( now - last_fg > 60 )); then
            return 1
        fi
    else
        LAST_FOREGROUND_TIME["$pkg"]=$(date +%s)
    fi
    
    return 0
}

is_frozen() {
    local pkg="$1"
    local pid
    pid=$(su -c "pidof $pkg" 2>/dev/null)
    [[ -z "$pid" ]] && return 1
    local stat_file="/proc/$pid/stat"
    [[ ! -f "$stat_file" ]] && return 1
    local cpu_time
    cpu_time=$(su -c "cat $stat_file" 2>/dev/null | awk '{print $14+$15}')
    [[ -z "$cpu_time" ]] && return 1
    local cache_key="cpu_${pkg}"
    local last_cpu="${INSTANCE_STATE[$cache_key]:-0}"
    if [[ "$last_cpu" == "$cpu_time" ]]; then
        local frozen_since="${INSTANCE_STATE[${cache_key}_time]:-$(( $(date +%s) - FREEZE_THRESHOLD - 1 ))}"
        local now=$(date +%s)
        if (( now - frozen_since >= FREEZE_THRESHOLD )); then
            return 0
        fi
    else
        INSTANCE_STATE["$cache_key"]="$cpu_time"
        INSTANCE_STATE["${cache_key}_time"]="$(date +%s)"
    fi
    return 1
}

launch() {
    local pkg="$1"
    local url="$2"
    local name="$3"

    log "[$name] Launching $pkg..."

    if is_running "$pkg"; then
        log "[$name] Already running"
        return 0
    fi

    su -c "am force-stop $pkg" >/dev/null 2>&1
    sleep 1

    su -c "am start -a android.intent.action.VIEW -d '$url' -p $pkg" >/dev/null 2>&1
    sleep 15

    local pid
    pid=$(su -c "pidof $pkg" 2>/dev/null)

    if [[ -n "$pid" ]]; then
        LAST_FOREGROUND_TIME["$pkg"]=$(date +%s)
        log "[$name] ✅ Launched (PID: $pid)"
        return 0
    else
        log "[$name] ❌ Failed to launch"
        return 1
    fi
}

kill_pkg() {
    su -c "am force-stop $1" >/dev/null 2>&1
}

clear_cache() {
    local pkg="$1"
    local pkg_dir="/data/data/$pkg"
    local cache_dirs
    cache_dirs=$(su -c "find $pkg_dir -maxdepth 1 -type d -iname '*cache*' 2>/dev/null")
    if [[ -z "$cache_dirs" ]]; then
        log "[$pkg] ⚠️ No cache dirs found"
        return
    fi
    while IFS= read -r dir; do
        [[ -n "$dir" ]] && su -c "rm -rf $dir/*" 2>/dev/null && log "[$pkg] Cleared: $dir"
    done <<< "$cache_dirs"
    local ext_cache="/sdcard/Android/data/$pkg/cache"
    [[ -d "$ext_cache" ]] && su -c "rm -rf $ext_cache/*" 2>/dev/null
    log "[$pkg] ✅ Cache cleared"
}

process_instance() {
    local idx="$1"
    local line="$2"
    IFS='|' read -r pkg url name <<< "$line"
    local state="${INSTANCE_STATE[$idx]:-0|0|0|0}"
    local last_cache restarts last_restart uptime
    IFS='|' read -r last_cache restarts last_restart uptime <<< "$state"
    local now_epoch=$(date +%s)
    
    local today_restarts
    today_restarts=$(get_today_restarts "$idx")
    
    local grace_key="grace_${idx}"
    local grace_until="${INSTANCE_STATE[$grace_key]:-0}"

    if (( now_epoch < grace_until )); then
        return
    fi

    if ! is_running "$pkg"; then
        log "[$name] 💀 Crash/closed! (hari ini: $today_restarts/$MAX_RESTARTS)"
        if (( today_restarts >= MAX_RESTARTS )); then
            log "[$name] ⚠️ MAX RESTARTS reached ($today_restarts kali)"
            discord_send "⚠️ Max Restarts" "**$name** skip (udah $today_restarts kali hari ini)." 15158332
            return
        fi
        local screenshot
        screenshot=$(take_screenshot)
        discord_send "💀 Crash" "**$name** close/crash. Restarting..." 16711680 "$screenshot"
        launch "$pkg" "$url" "$name"
        INSTANCE_STATE["$grace_key"]="$((now_epoch + 30))"
        ((restarts++))
        ((today_restarts++))
        INSTANCE_STATE["$idx"]="$now_epoch|$restarts|$now_epoch|$uptime"
        set_today_restarts "$idx" "$today_restarts"
        save_state
        log "[$name] 🚀 Restarted ($restarts total, hari ini: $today_restarts)"
        discord_send "🚀 Restarted" "**$name** rejoin. Total: $restarts | Hari ini: $today_restarts" 3066993
        return
    fi

    if is_frozen "$pkg"; then
        log "[$name] 🥶 Frozen! (hari ini: $today_restarts/$MAX_RESTARTS)"
        if (( today_restarts >= MAX_RESTARTS )); then
            log "[$name] ⚠️ MAX RESTARTS reached"
            return
        fi
        local screenshot
        screenshot=$(take_screenshot)
        discord_send "🥶 Frozen" "**$name** freeze. Restarting..." 16711680 "$screenshot"
        kill_pkg "$pkg"
        sleep 2
        clear_cache "$pkg"
        sleep 1
        launch "$pkg" "$url" "$name"
        ((restarts++))
        ((today_restarts++))
        INSTANCE_STATE["$idx"]="$now_epoch|$restarts|$now_epoch|$uptime"
        set_today_restarts "$idx" "$today_restarts"
        save_state
        log "[$name] 🚀 Restarted after freeze"
        discord_send "🚀 Restarted" "**$name** restart setelah freeze." 3066993
        return
    fi

    if [[ "$CACHE_INTERVAL" != "0" ]] && (( now_epoch - last_cache >= CACHE_INTERVAL )); then
        log "[$name] 🧹 Cache clear..."
        discord_send "🧹 Cache Clear" "**$name** cache clear." 3447003
        kill_pkg "$pkg"
        sleep 2
        clear_cache "$pkg"
        sleep 1
        launch "$pkg" "$url" "$name"
        INSTANCE_STATE["$idx"]="$now_epoch|$restarts|$last_restart|$uptime"
        save_state
        log "[$name] ✅ Cache cleared"
        discord_send "🚀 Relaunched" "**$name** restart setelah cache clear." 3066993
        return
    fi

    if (( last_restart > 0 )); then
        INSTANCE_STATE["$idx"]="$last_cache|$restarts|$last_restart|$((uptime + CHECK_INTERVAL))"
    fi
}

cleanup_all() {
    log "🧹 Cleaning up..."
    for line in "${INSTANCES[@]}"; do
        IFS='|' read -r pkg _ name <<< "$line"
        kill_pkg "$pkg"
    done
    rm -f "$PID_FILE" "$STATE_FILE"
}

# 🔧 Daemon mode dengan proper signal handling
if [[ "$1" == "--daemon" ]]; then
    mkdir -p "$(dirname "$PID_FILE")" "$(dirname "$LOG_FILE")"
    echo $$ > "$PID_FILE"
    load_state
    trap 'cleanup_all; discord_send "🛑 Stopped" "Bot dimatikan." 15158332; exit 0' SIGTERM SIGINT EXIT
    log "🚀 Bot started | ${#INSTANCES[@]} instances"
    discord_send "🚀 Started" "Bot aktif: **${#INSTANCES[@]}** instance." 3066993

    log "📦 Launching all instances..."
    local i=0
    for line in "${INSTANCES[@]}"; do
        IFS='|' read -r pkg url name <<< "$line"
        launch "$pkg" "$url" "$name"
        ((i++))
        (( i < ${#INSTANCES[@]} )) && sleep 5
    done
    log "✅ All launched"

    while true; do
        i=0
        for line in "${INSTANCES[@]}"; do
            process_instance "$i" "$line"
            ((i++))
        done
        save_state
        sleep "$CHECK_INTERVAL"
    done
    exit 0
fi

case "$1" in
    start)
        [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null && echo "❌ Already running" && exit 1
        nohup bash "$SCRIPT_PATH" --daemon > /dev/null 2>&1 &
        sleep 2
        [[ -f "$PID_FILE" ]] && echo "✅ Started (PID: $(cat "$PID_FILE"))" || echo "❌ Failed to start"
        ;;
    stop)
        if [[ -f "$PID_FILE" ]]; then
            local pid=$(cat "$PID_FILE")
            kill "$pid" 2>/dev/null
            sleep 1
            kill -9 "$pid" 2>/dev/null
            rm -f "$PID_FILE"
        fi
        for line in "${INSTANCES[@]}"; do IFS='|' read -r pkg _ _ <<< "$line"; kill_pkg "$pkg"; done
        rm -f "$STATE_FILE"
        log "🛑 Stopped"
        discord_send "🛑 Stopped" "Bot dimatikan manual." 15158332
        echo "🛑 Stopped"
        ;;
    restart) bash "$SCRIPT_PATH" stop; sleep 2; bash "$SCRIPT_PATH" start ;;
    status)
        if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "🟢 Running (PID: $(cat "$PID_FILE"))"
            load_state
            local i=0
            for line in "${INSTANCES[@]}"; do
                IFS='|' read -r pkg _ name <<< "$line"
                local state="${INSTANCE_STATE[$i]:-0|0|0|0}"
                local _c restarts _r uptime
                IFS='|' read -r _c restarts _r uptime <<< "$state"
                if is_running "$pkg"; then
                    echo "   🟢 $name | Restarts: $restarts | Uptime: $((uptime/3600))h $(((uptime%3600)/60))m | Today: $(get_today_restarts "$i")/$MAX_RESTARTS"
                else
                    echo "   🔴 $name | Restarts: $restarts | Today: $(get_today_restarts "$i")/$MAX_RESTARTS"
                fi
                ((i++))
            done
        else
            echo "🔴 Stopped"
        fi
        ;;
    log) [[ -f "$LOG_FILE" ]] && tail -f "$LOG_FILE" || echo "No log" ;;
    test-webhook)
        [[ -z "$DISCORD_WEBHOOK" ]] && echo "❌ Webhook not set" && exit 1
        discord_send "🧪 Test" "Webhook OK.\n**Device:** $(getprop ro.product.model)" 3447003
        echo "✅ Sent"
        ;;
    test-screenshot)
        local ss; ss=$(take_screenshot)
        [[ -n "$ss" ]] && echo "✅ $ss" && discord_send "🧪 Screenshot" "Test." 3447003 "$ss" || echo "❌ Failed"
        ;;
    test-launch)
        IFS='|' read -r pkg url name <<< "${INSTANCES[0]}"
        launch "$pkg" "$url" "$name"
        ;;
    reset-state) rm -f "$STATE_FILE"; echo "✅ State reset"; log "✅ State reset" ;;
    *) echo "🎮 Roblox Bot v2 | Usage: start|stop|restart|status|log|test-webhook|test-screenshot|test-launch|reset-state" ;;
esac