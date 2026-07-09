#!/data/data/com.termux/files/usr/bin/bash

# ═══════════════════════════════════════════════════════════════════════
#  CONFIG — EDIT INI AJA
# ═══════════════════════════════════════════════════════════════════════

INSTANCES=(
    "com.roblox.client|roblox://placeID=PLACE_ID&linkCode=CODE|Main"
    # "com.roblox.client2|roblox://placeID=PLACE_ID&linkCode=CODE2|Alt1"
)

CHECK_INTERVAL="5"
CACHE_INTERVAL="3600"
FREEZE_THRESHOLD="30"
MAX_RESTARTS="50"

DISCORD_WEBHOOK="https://discord.com/api/webhooks/1483451715104804964/o0vgYLS-zg4WUXHQM-GiaT0idCfzz-bqPAqRXi4ME0xjEQusxdA3zmEdRQIzUiHovOb3"
DISCORD_PING_USER=""

# ═══════════════════════════════════════════════════════════════════════
#  CORE
# ═══════════════════════════════════════════════════════════════════════

PID_FILE="/data/data/com.termux/files/usr/tmp/roblox_bot.pid"
LOG_FILE="/sdcard/roblox_bot.log"
STATE_FILE="/data/data/com.termux/files/usr/tmp/roblox_state"
SCRIPT_PATH="$(realpath "$0")"

declare -A INSTANCE_STATE

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
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
        } | curl -s -X POST -H "Content-Type: multipart/form-data; boundary=$boundary" \
            --data-binary @- "$DISCORD_WEBHOOK" >/dev/null 2>&1 &
    else
        local json="{\"content\":\"${ping}\",\"embeds\":[{\"title\":\"$title\",\"description\":\"$description\",\"color\":$color,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"footer\":{\"text\":\"Roblox Bot • Termux\"}}]}"
        curl -s -H "Content-Type: application/json" -X POST -d "$json" "$DISCORD_WEBHOOK" >/dev/null 2>&1 &
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
    } > "$STATE_FILE"
}

is_running() {
    su -c "pidof $1" >/dev/null 2>&1
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
    su -c "am start -a android.intent.action.VIEW -d '$url' -p $pkg" >/dev/null 2>&1
}

kill_pkg() {
    su -c "am force-stop $1" >/dev/null 2>&1
}

clear_cache() {
    su -c "pm clear $1" >/dev/null 2>&1
}

process_instance() {
    local idx="$1"
    local line="$2"

    IFS='|' read -r pkg url name <<< "$line"

    local state="${INSTANCE_STATE[$idx]:-0|0|0|0}"
    local last_cache restarts last_restart uptime
    IFS='|' read -r last_cache restarts last_restart uptime <<< "$state"

    local now_epoch=$(date +%s)
    local today=$(date +%Y%m%d)
    local today_key="day_${idx}_${today}"
    local today_restarts="${INSTANCE_STATE[$today_key]:-0}"

    if is_frozen "$pkg"; then
        log "[$name] 🥶 FROZEN/ANR detected!"
        discord_send "🥶 Instance Frozen" "**$name** \`$pkg\` freeze/ANR terdeteksi. Restarting..." 16711680 "$(take_screenshot)"

        kill_pkg "$pkg"
        sleep 2
        clear_cache "$pkg"
        sleep 0.5
        launch "$pkg" "$url"

        ((restarts++))
        ((today_restarts++))
        INSTANCE_STATE["$idx"]="$now_epoch|$restarts|$now_epoch|$uptime"
        INSTANCE_STATE["$today_key"]="$today_restarts"
        save_state

        log "[$name] 🚀 Restarted after freeze (total: $restarts, today: $today_restarts)"
        discord_send "🚀 Instance Restarted" "**$name** \`$pkg\` restart setelah freeze. Total restart: $restarts" 3066993
        sleep 10
        return
    fi

    if ! is_running "$pkg"; then
        log "[$name] 💀 Crash/mati detected!"
        discord_send "💀 Instance Crash" "**$name** \`$pkg\` crash/mati. Restarting..." 16711680 "$(take_screenshot)"

        kill_pkg "$pkg"
        sleep 1
        clear_cache "$pkg"
        sleep 0.5
        launch "$pkg" "$url"

        ((restarts++))
        ((today_restarts++))
        INSTANCE_STATE["$idx"]="$now_epoch|$restarts|$now_epoch|$uptime"
        INSTANCE_STATE["$today_key"]="$today_restarts"
        save_state

        log "[$name] 🚀 Restarted after crash (total: $restarts, today: $today_restarts)"
        discord_send "🚀 Instance Restarted" "**$name** \`$pkg\` restart setelah crash. Total restart: $restarts" 3066993
        sleep 10
        return
    fi

    if (( today_restarts >= MAX_RESTARTS )); then
        log "[$name] ⚠️ MAX RESTARTS ($MAX_RESTARTS) reached today! Instance di-skip."
        discord_send "⚠️ Max Restarts Reached" "**$name** \`$pkg\` udah restart $today_restarts kali hari ini. Bot skip instance ini biar ga infinite loop." 15158332
        INSTANCE_STATE["$idx"]="$last_cache|$restarts|$last_restart|$uptime"
        save_state
        return
    fi

    if [[ "$CACHE_INTERVAL" != "0" ]] && (( now_epoch - last_cache >= CACHE_INTERVAL )); then
        log "[$name] 🧹 Auto clear cache..."
        discord_send "🧹 Auto Cache Clear" "**$name** \`$pkg\` cache di-clear otomatis." 3447003

        kill_pkg "$pkg"
        sleep 1
        clear_cache "$pkg"
        launch "$pkg" "$url"

        INSTANCE_STATE["$idx"]="$now_epoch|$restarts|$last_restart|$uptime"
        save_state

        log "[$name] ✅ Cache cleared & relaunched"
        discord_send "🚀 Cache Cleared & Restarted" "**$name** \`$pkg\` berhasil restart setelah cache clear." 3066993
        sleep 10
        return
    fi

    if (( last_restart > 0 )); then
        INSTANCE_STATE["$idx"]="$last_cache|$restarts|$last_restart|$((uptime + CHECK_INTERVAL))"
    fi
}

cleanup_all() {
    log "🧹 Cleaning up all instances..."
    for line in "${INSTANCES[@]}"; do
        IFS='|' read -r pkg _ name <<< "$line"
        log "   Killing $name ($pkg)..."
        kill_pkg "$pkg"
    done
    rm -f "$PID_FILE" "$STATE_FILE"
}

# ═══════════════════════════════════════════════════════════════════════
#  DAEMON MODE
# ═══════════════════════════════════════════════════════════════════════

if [[ "$1" == "--daemon" ]]; then
    echo $$ > "$PID_FILE"
    load_state

    trap 'cleanup_all; discord_send "🛑 Bot Stopped" "Roblox Bot dimatikan (graceful shutdown)." 15158332; exit 0' SIGTERM SIGINT

    log "🚀 Bot started | Instances: ${#INSTANCES[@]} | PID: $$"
    discord_send "🚀 Bot Started" "Roblox Bot aktif dengan **${#INSTANCES[@]}** instance.\n\n**Config:**\n• Check interval: ${CHECK_INTERVAL}s\n• Cache interval: ${CACHE_INTERVAL}s\n• Freeze threshold: ${FREEZE_THRESHOLD}s\n• Max restarts/day: ${MAX_RESTARTS}" 3066993

    for line in "${INSTANCES[@]}"; do
        IFS='|' read -r pkg url name <<< "$line"
        log "   📦 $name → $pkg"
    done

    while true; do
        local i=0
        for line in "${INSTANCES[@]}"; do
            process_instance "$i" "$line"
            ((i++))
        done
        save_state
        sleep "$CHECK_INTERVAL"
    done

    exit 0
fi

# ═══════════════════════════════════════════════════════════════════════
#  CLI
# ═══════════════════════════════════════════════════════════════════════

case "$1" in
    start)
        if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "❌ Bot already running (PID: $(cat "$PID_FILE"))"
            exit 1
        fi
        nohup bash "$SCRIPT_PATH" --daemon > /dev/null 2>&1 &
        sleep 1
        if [[ -f "$PID_FILE" ]]; then
            echo "✅ Bot started (PID: $(cat "$PID_FILE"))"
            echo "📋 Log: $LOG_FILE"
            echo "📊 State: $STATE_FILE"
        else
            echo "❌ Failed to start"
        fi
        ;;
    stop)
        if [[ -f "$PID_FILE" ]]; then
            local pid
            pid=$(cat "$PID_FILE")
            kill "$pid" 2>/dev/null
            sleep 1
            kill -9 "$pid" 2>/dev/null
            rm -f "$PID_FILE"
            for line in "${INSTANCES[@]}"; do
                IFS='|' read -r pkg _ name <<< "$line"
                kill_pkg "$pkg"
            done
            rm -f "$STATE_FILE"
            log "🛑 Bot stopped (manual)"
            discord_send "🛑 Bot Stopped" "Roblox Bot dimatikan secara manual." 15158332
            echo "🛑 Bot stopped"
        else
            echo "Bot not running"
        fi
        ;;
    restart)
        bash "$SCRIPT_PATH" stop
        sleep 2
        bash "$SCRIPT_PATH" start
        ;;
    status)
        if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "🟢 Running (PID: $(cat "$PID_FILE"))"
            echo ""
            load_state
            echo "📦 Instances:"
            local i=0
            for line in "${INSTANCES[@]}"; do
                IFS='|' read -r pkg _ name <<< "$line"
                local state="${INSTANCE_STATE[$i]:-0|0|0|0}"
                local last_cache restarts last_restart uptime
                IFS='|' read -r last_cache restarts last_restart uptime <<< "$state"
                local status_emoji="🔴"
                is_running "$pkg" && status_emoji="🟢"
                local uptime_str="$((uptime / 3600))h $(( (uptime % 3600) / 60 ))m"
                echo "   $status_emoji $name | $pkg"
                echo "      Restarts: $restarts | Uptime: $uptime_str"
                ((i++))
            done
            echo ""
            echo "🌐 Webhook: $([[ -n "$DISCORD_WEBHOOK" ]] && echo "✅ Configured" || echo "❌ Not set")"
        else
            echo "🔴 Stopped"
        fi
        ;;
    log)
        [[ -f "$LOG_FILE" ]] && tail -f "$LOG_FILE" || echo "No log yet"
        ;;
    test-webhook)
        [[ -z "$DISCORD_WEBHOOK" ]] && echo "❌ DISCORD_WEBHOOK belum di-set!" && exit 1
        echo "Testing webhook..."
        discord_send "🧪 Test Webhook" "Webhook berhasil dikirim dari Termux!\n\n**Device:** $(getprop ro.product.model)\n**Android:** $(getprop ro.build.version.release)" 3447003
        echo "✅ Test webhook sent! Cek Discord lu."
        ;;
    test-screenshot)
        echo "Taking screenshot..."
        local ss
        ss=$(take_screenshot)
        [[ -n "$ss" ]] && echo "✅ Screenshot: $ss" && discord_send "🧪 Test Screenshot" "Screenshot test." 3447003 "$ss" || echo "❌ Failed"
        ;;
    test-launch)
        echo "Testing launch instance 0..."
        IFS='|' read -r pkg url name <<< "${INSTANCES[0]}"
        echo "Package: $pkg | URL: $url"
        sleep 3
        launch "$pkg" "$url"
        echo "✅ Launched"
        ;;
    reset-state)
        rm -f "$STATE_FILE"
        echo "✅ State file cleared. Restart counter reset."
        ;;
    *)
        echo "🎮 Roblox Auto Bot"
        echo ""
        echo "Usage:"
        echo "  bash roblox_bot.sh start"
        echo "  bash roblox_bot.sh stop"
        echo "  bash roblox_bot.sh restart"
        echo "  bash roblox_bot.sh status"
        echo "  bash roblox_bot.sh log"
        echo "  bash roblox_bot.sh test-webhook"
        echo "  bash roblox_bot.sh test-screenshot"
        echo "  bash roblox_bot.sh test-launch"
        echo "  bash roblox_bot.sh reset-state"
        ;;
esac