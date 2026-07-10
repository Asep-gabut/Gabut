#!/data/data/com.termux/files/usr/bin/bash

################################################################################
# ROBLOX BOT v2 - Advanced Instance Manager
# Auto-detect, launch, monitor, dan restart multiple Roblox instances
# dengan Discord notifications dan crash detection
################################################################################

set -o pipefail

# =============================================================================
# CONFIG SECTION
# =============================================================================

# Package detection (auto-detect packages dengan prefix free.no)
PACKAGE_PREFIX="free.no"
ROBLOX_URL="https://www.roblox.com/share?code=c398b5696d26e0449bb9c8e35be72152&type=Server"

# Monitoring intervals & thresholds
CHECK_INTERVAL=10           # Detik - interval monitoring
CACHE_INTERVAL=3600         # Detik - interval cache clear (0 = disable)
FREEZE_THRESHOLD=60         # Detik - time tanpa CPU activity baru considered frozen
LAUNCH_TIMEOUT=45           # Detik - timeout untuk wait app open
MAX_RESTARTS=50             # Max restart per hari

# Discord configuration
DISCORD_WEBHOOK="${DISCORD_WEBHOOK:-}"
DISCORD_PING_USER="${DISCORD_PING_USER:-}"

# File paths
TERMUX_DIR="/data/data/com.termux/files/usr"
TMP_DIR="${TERMUX_DIR}/tmp"
PID_FILE="${TMP_DIR}/roblox_bot.pid"
STATE_DIR="${TMP_DIR}/roblox_bot_state"
CONFIG_FILE="${TMP_DIR}/roblox_bot.conf"
SCRIPT_PATH="$(realpath "$0")"

# Screenshot path
SCREENSHOT_DIR="/sdcard"

# Logging
VERBOSE=0  # Set to 1 untuk debug output

# =============================================================================
# CORE UTILITIES
# =============================================================================

# Color codes untuk output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log() {
    local level="$1"
    shift
    local msg="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        ERROR)   echo -e "${RED}[ERROR]${NC} [$timestamp] $msg" >&2 ;;
        WARN)    echo -e "${YELLOW}[WARN]${NC}  [$timestamp] $msg" ;;
        INFO)    echo -e "${GREEN}[INFO]${NC}  [$timestamp] $msg" ;;
        DEBUG)   [[ $VERBOSE -eq 1 ]] && echo -e "${BLUE}[DEBUG]${NC} [$timestamp] $msg" ;;
        *)       echo "[$timestamp] $msg" ;;
    esac
}

die() {
    log ERROR "$@"
    exit 1
}

# Safely execute commands dengan root
exec_su() {
    su -c "$@" 2>/dev/null
}

# Safely execute commands dengan root dan error checking
exec_su_safe() {
    local cmd="$1"
    local error_msg="${2:-Command failed: $cmd}"
    
    if ! output=$(exec_su "$cmd" 2>&1); then
        log ERROR "$error_msg"
        return 1
    fi
    echo "$output"
    return 0
}

# =============================================================================
# DISCORD NOTIFICATIONS
# =============================================================================

discord_send() {
    local title="$1"
    local description="$2"
    local color="${3:-3447003}"  # Default cyan
    local image_path="${4:-}"
    
    [[ -z "$DISCORD_WEBHOOK" ]] && return 0
    
    local ping=""
    [[ -n "$DISCORD_PING_USER" ]] && ping="<@$DISCORD_PING_USER> "
    
    if [[ -n "$image_path" ]] && [[ -f "$image_path" ]]; then
        # Send dengan image
        _discord_send_with_image "$ping" "$title" "$description" "$color" "$image_path"
    else
        # Send tanpa image
        _discord_send_simple "$ping" "$title" "$description" "$color"
    fi
}

_discord_send_simple() {
    local ping="$1"
    local title="$2"
    local description="$3"
    local color="$4"
    
    local json="{\"content\":\"${ping}\",\"embeds\":[{\"title\":\"$title\",\"description\":\"$description\",\"color\":$color,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"footer\":{\"text\":\"Roblox Bot • Termux\"}}]}"
    
    curl -s -H "Content-Type: application/json" -X POST -d "$json" "$DISCORD_WEBHOOK" >/dev/null 2>&1 &
}

_discord_send_with_image() {
    local ping="$1"
    local title="$2"
    local description="$3"
    local color="$4"
    local image_path="$5"
    
    local boundary="----BotBoundary$(date +%s%N | md5sum | cut -c1-8)"
    
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
    } | curl -s -X POST -H "Content-Type: multipart/form-data; boundary=$boundary" --data-binary @- "$DISCORD_WEBHOOK" >/dev/null 2>&1 &
}

# =============================================================================
# PACKAGE & PROCESS MANAGEMENT
# =============================================================================

detect_packages() {
    # Auto-detect packages dengan prefix yang specified
    local packages
    packages=$(exec_su "pm list packages" | grep -E "^package:${PACKAGE_PREFIX}[a-zA-Z0-9]*" | sed 's/package://')
    
    if [[ -z "$packages" ]]; then
        return 1
    fi
    
    echo "$packages"
}

get_process_pid() {
    local pkg="$1"
    exec_su "pidof $pkg 2>/dev/null" | awk '{print $1}'
}

is_process_alive() {
    local pid="$1"
    [[ -z "$pid" ]] && return 1
    exec_su "kill -0 $pid 2>/dev/null" && return 0 || return 1
}

is_process_zombie() {
    local pid="$1"
    [[ -z "$pid" ]] && return 1
    
    local state
    state=$(exec_su "cat /proc/$pid/stat 2>/dev/null" | awk '{print $3}')
    [[ "$state" == "Z" ]] && return 0 || return 1
}

is_app_running() {
    local pkg="$1"
    
    local pid
    pid=$(get_process_pid "$pkg") || return 1
    
    is_process_zombie "$pid" && return 1
    is_process_alive "$pid" || return 1
    
    # Verify window is visible
    exec_su "dumpsys window windows 2>/dev/null" | grep -q "mCurrentFocus.*$pkg" && return 0
    
    return 1
}

get_cpu_time() {
    local pid="$1"
    [[ -z "$pid" ]] && return 1
    
    local cpu_time
    cpu_time=$(exec_su "cat /proc/$pid/stat 2>/dev/null" | awk '{print $14+$15}')
    [[ -n "$cpu_time" ]] && echo "$cpu_time"
}

is_app_frozen() {
    local pkg="$1"
    local state_key="frozen_cpu_${pkg}"
    local state_time_key="frozen_time_${pkg}"
    
    local pid
    pid=$(get_process_pid "$pkg") || return 1
    
    local current_cpu
    current_cpu=$(get_cpu_time "$pid") || return 1
    
    local last_cpu="${APP_STATE[$state_key]:-0}"
    local last_time="${APP_STATE[$state_time_key]:-0}"
    
    if [[ "$last_cpu" == "$current_cpu" ]]; then
        local now=$(date +%s)
        if [[ $last_time -gt 0 ]] && (( now - last_time >= FREEZE_THRESHOLD )); then
            log DEBUG "$pkg frozen: CPU $current_cpu tidak berubah selama $FREEZE_THRESHOLD detik"
            return 0
        fi
    else
        # CPU time changed, update state
        APP_STATE["$state_key"]="$current_cpu"
        APP_STATE["$state_time_key"]="$(date +%s)"
    fi
    
    return 1
}

force_stop_app() {
    local pkg="$1"
    log DEBUG "Force stopping $pkg"
    exec_su "am force-stop $pkg 2>/dev/null" >/dev/null
}

clear_app_cache() {
    local pkg="$1"
    log DEBUG "Clearing cache untuk $pkg"
    
    local pkg_dir="/data/data/$pkg"
    
    # Internal cache
    local cache_dirs
    cache_dirs=$(exec_su "find $pkg_dir -maxdepth 1 -type d -iname '*cache*' 2>/dev/null" | head -5)
    
    if [[ -n "$cache_dirs" ]]; then
        while IFS= read -r dir; do
            [[ -n "$dir" ]] && exec_su "rm -rf $dir/* 2>/dev/null" >/dev/null 2>&1
        done <<< "$cache_dirs"
    fi
    
    # External cache
    local ext_cache="/sdcard/Android/data/$pkg/cache"
    [[ -d "$ext_cache" ]] && exec_su "rm -rf $ext_cache/* 2>/dev/null" >/dev/null 2>&1
}

launch_app() {
    local pkg="$1"
    local url="$2"
    local name="$3"
    
    # Skip if sudah running
    if is_app_running "$pkg"; then
        log DEBUG "$name sudah running"
        return 0
    fi
    
    log INFO "🚀 Launching $name ($pkg)..."
    
    # Force stop & clear cache untuk fresh start
    force_stop_app "$pkg"
    sleep 2
    clear_app_cache "$pkg"
    sleep 1
    
    # Launch dengan intent
    if ! exec_su "am start -a android.intent.action.VIEW -d '$url' -p $pkg 2>/dev/null" >/dev/null; then
        log ERROR "Failed to start intent untuk $pkg"
        return 1
    fi
    
    # Wait sampai app terbuka dengan timeout
    local elapsed=0
    while (( elapsed < LAUNCH_TIMEOUT )); do
        if is_app_running "$pkg"; then
            log INFO "✅ $name successfully launched"
            return 0
        fi
        sleep 3
        ((elapsed += 3))
        log DEBUG "⏳ Waiting for $name... ($elapsed/$LAUNCH_TIMEOUT)"
    done
    
    log ERROR "❌ Timeout launching $name after ${LAUNCH_TIMEOUT}s"
    return 1
}

take_screenshot() {
    local filename="roblox_crash_$(date +%s).png"
    local filepath="${SCREENSHOT_DIR}/${filename}"
    
    if ! exec_su "screencap -p $filepath 2>/dev/null" >/dev/null; then
        log DEBUG "Screenshot failed"
        return 1
    fi
    
    if [[ -f "$filepath" ]]; then
        echo "$filepath"
        return 0
    fi
    
    return 1
}

# =============================================================================
# STATE MANAGEMENT
# =============================================================================

declare -A APP_STATE

init_state_storage() {
    mkdir -p "$STATE_DIR" 2>/dev/null
    
    # Load existing state
    if [[ -f "${STATE_DIR}/app_state.sh" ]]; then
        source "${STATE_DIR}/app_state.sh" 2>/dev/null
    fi
}

save_app_state() {
    local pkg="$1"
    local key="$2"
    local value="$3"
    
    APP_STATE["$key"]="$value"
}

get_app_state() {
    local key="$1"
    echo "${APP_STATE[$key]:-}"
}

persist_state() {
    # Persist state to disk (atomic write)
    {
        echo "# Roblox Bot State - $(date)"
        echo "# DO NOT EDIT MANUALLY"
        echo ""
        for key in "${!APP_STATE[@]}"; do
            # Escape quotes dalam value
            local value="${APP_STATE[$key]//\"/\\\"}"
            echo "APP_STATE[\"$key\"]=\"$value\""
        done
    } > "${STATE_DIR}/app_state.sh.tmp" 2>/dev/null && \
    mv "${STATE_DIR}/app_state.sh.tmp" "${STATE_DIR}/app_state.sh" 2>/dev/null
}

get_daily_restart_count() {
    local pkg="$1"
    local today=$(date +%Y%m%d)
    local key="restarts_${pkg}_${today}"
    echo "${APP_STATE[$key]:-0}"
}

increment_daily_restart() {
    local pkg="$1"
    local today=$(date +%Y%m%d)
    local key="restarts_${pkg}_${today}"
    local count=$(get_daily_restart_count "$pkg")
    ((count++))
    APP_STATE["$key"]="$count"
    return $count
}

get_total_restart_count() {
    local pkg="$1"
    local key="restarts_total_${pkg}"
    echo "${APP_STATE[$key]:-0}"
}

increment_total_restart() {
    local pkg="$1"
    local key="restarts_total_${pkg}"
    local count=$(get_total_restart_count "$pkg")
    ((count++))
    APP_STATE["$key"]="$count"
}

get_grace_until() {
    local pkg="$1"
    local key="grace_until_${pkg}"
    echo "${APP_STATE[$key]:-0}"
}

set_grace_period() {
    local pkg="$1"
    local seconds="${2:-30}"
    local key="grace_until_${pkg}"
    APP_STATE["$key"]="$(($(date +%s) + seconds))"
}

is_in_grace_period() {
    local pkg="$1"
    local grace_until=$(get_grace_until "$pkg")
    local now=$(date +%s)
    [[ $now -lt $grace_until ]]
}

get_last_cache_clear() {
    local pkg="$1"
    local key="last_cache_clear_${pkg}"
    echo "${APP_STATE[$key]:-0}"
}

set_last_cache_clear() {
    local pkg="$1"
    local key="last_cache_clear_${pkg}"
    APP_STATE["$key"]="$(date +%s)"
}

# =============================================================================
# MONITORING & MAINTENANCE
# =============================================================================

handle_crashed_app() {
    local pkg="$1"
    local name="$2"
    
    log WARN "💀 $name ($pkg) crashed!"
    
    local daily_count=$(get_daily_restart_count "$pkg")
    if (( daily_count >= MAX_RESTARTS )); then
        log WARN "⚠️ Max restarts reached untuk $name ($daily_count/$MAX_RESTARTS)"
        discord_send "⚠️ Max Restarts" "**$name** sudah di-restart $daily_count kali hari ini" 15158332
        return 1
    fi
    
    # Send crash notification dengan screenshot
    local screenshot
    screenshot=$(take_screenshot)
    discord_send "💀 Crash Detected" "**$name** crash! Restarting...\nDaily restarts: $((daily_count + 1))/$MAX_RESTARTS" 16711680 "$screenshot"
    
    # Attempt restart
    if launch_app "$pkg" "$ROBLOX_URL" "$name"; then
        increment_daily_restart "$pkg"
        increment_total_restart "$pkg"
        set_grace_period "$pkg" 30
        
        local new_count=$(get_daily_restart_count "$pkg")
        local total=$(get_total_restart_count "$pkg")
        discord_send "🚀 Restarted" "**$name** successfully restarted\n✓ Daily: $new_count/$MAX_RESTARTS\n✓ Total: $total" 3066993
        
        return 0
    else
        discord_send "❌ Restart Failed" "**$name** gagal di-restart setelah crash" 16711680
        return 1
    fi
}

handle_frozen_app() {
    local pkg="$1"
    local name="$2"
    
    log WARN "🥶 $name ($pkg) frozen (CPU not progressing)!"
    
    local daily_count=$(get_daily_restart_count "$pkg")
    if (( daily_count >= MAX_RESTARTS )); then
        log WARN "⚠️ Max restarts reached, skipping frozen app restart"
        return 1
    fi
    
    # Send frozen notification dengan screenshot
    local screenshot
    screenshot=$(take_screenshot)
    discord_send "🥶 App Frozen" "**$name** frozen! Restarting...\nDaily restarts: $((daily_count + 1))/$MAX_RESTARTS" 16711680 "$screenshot"
    
    # Kill, clear cache, restart
    force_stop_app "$pkg"
    sleep 2
    clear_app_cache "$pkg"
    sleep 1
    
    if launch_app "$pkg" "$ROBLOX_URL" "$name"; then
        increment_daily_restart "$pkg"
        increment_total_restart "$pkg"
        set_grace_period "$pkg" 30
        
        local new_count=$(get_daily_restart_count "$pkg")
        discord_send "🚀 Unfrozen" "**$name** successfully restarted after frozen state\n✓ Daily: $new_count/$MAX_RESTARTS" 3066993
        
        return 0
    else
        discord_send "❌ Restart Failed" "**$name** gagal di-restart setelah frozen" 16711680
        return 1
    fi
}

handle_cache_clear() {
    local pkg="$1"
    local name="$2"
    
    log INFO "🧹 Periodic cache clear untuk $name"
    discord_send "🧹 Cache Clear" "**$name** cache clear (periodic maintenance)" 3447003
    
    force_stop_app "$pkg"
    sleep 2
    clear_app_cache "$pkg"
    sleep 1
    
    if launch_app "$pkg" "$ROBLOX_URL" "$name"; then
        set_last_cache_clear "$pkg"
        set_grace_period "$pkg" 30
        discord_send "🚀 Relaunched" "**$name** relaunched setelah cache clear" 3066993
        return 0
    else
        discord_send "❌ Relaunch Failed" "**$name** gagal di-relaunch setelah cache clear" 16711680
        return 1
    fi
}

monitor_app() {
    local pkg="$1"
    local name="$2"
    
    # Skip jika dalam grace period
    if is_in_grace_period "$pkg"; then
        log DEBUG "⏳ $name dalam grace period, skip monitoring"
        return 0
    fi
    
    # Check if crashed
    if ! is_app_running "$pkg"; then
        handle_crashed_app "$pkg" "$name"
        return
    fi
    
    # Check if frozen
    if is_app_frozen "$pkg"; then
        handle_frozen_app "$pkg" "$name"
        return
    fi
    
    # Check if cache clear diperlukan
    if [[ "$CACHE_INTERVAL" != "0" ]]; then
        local last_clear=$(get_last_cache_clear "$pkg")
        local now=$(date +%s)
        if (( now - last_clear >= CACHE_INTERVAL )); then
            handle_cache_clear "$pkg" "$name"
            return
        fi
    fi
}

# =============================================================================
# DAEMON & PROCESS MANAGEMENT
# =============================================================================

cleanup_daemon() {
    log INFO "🛑 Cleanup daemon..."
    
    # Kill all instances
    for pkg in $(detect_packages); do
        force_stop_app "$pkg"
    done
    
    # Remove PID file
    rm -f "$PID_FILE"
    
    # Save state before exit
    persist_state
}

run_daemon() {
    log INFO "🚀 Starting daemon..."
    
    # Initialize
    init_state_storage
    
    # Write PID
    echo $$ > "$PID_FILE" 2>/dev/null || die "Cannot write PID file"
    
    # Setup signal handlers
    trap 'cleanup_daemon; discord_send "🛑 Stopped" "Roblox Bot dimatikan" 15158332; exit 0' SIGTERM SIGINT
    
    # Get packages
    local packages
    packages=$(detect_packages) || die "No packages found dengan prefix '$PACKAGE_PREFIX'"
    
    local pkg_count=$(echo "$packages" | wc -l)
    log INFO "📦 Found $pkg_count Roblox instances"
    
    # Send startup notification
    discord_send "🚀 Bot Started" "Monitoring **$pkg_count** Roblox instances\n• Interval: ${CHECK_INTERVAL}s\n• Max restarts/hari: $MAX_RESTARTS" 3066993
    
    # Launch all instances initially
    local i=0
    while IFS= read -r pkg; do
        local name="${pkg##*.}"
        launch_app "$pkg" "$ROBLOX_URL" "$name"
        ((i++))
        (( i < pkg_count )) && sleep 5
    done <<< "$packages"
    
    # Main monitoring loop
    log INFO "📊 Entering monitoring loop (CHECK_INTERVAL=${CHECK_INTERVAL}s)..."
    
    while true; do
        while IFS= read -r pkg; do
            local name="${pkg##*.}"
            monitor_app "$pkg" "$name"
        done <<< "$packages"
        
        persist_state
        sleep "$CHECK_INTERVAL"
    done
}

# =============================================================================
# CLI COMMANDS
# =============================================================================

cmd_start() {
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
        log ERROR "Already running (PID: $(cat "$PID_FILE"))"
        return 1
    fi
    
    log INFO "Starting Roblox Bot daemon..."
    nohup bash "$SCRIPT_PATH" daemon > /dev/null 2>&1 &
    sleep 1
    
    if [[ -f "$PID_FILE" ]]; then
        log INFO "✅ Daemon started successfully (PID: $(cat "$PID_FILE"))"
        return 0
    else
        log ERROR "Failed to start daemon"
        return 1
    fi
}

cmd_stop() {
    if [[ ! -f "$PID_FILE" ]]; then
        log ERROR "Daemon not running"
        return 1
    fi
    
    local pid=$(cat "$PID_FILE" 2>/dev/null)
    log INFO "Stopping daemon (PID: $pid)..."
    
    kill "$pid" 2>/dev/null
    sleep 1
    kill -9 "$pid" 2>/dev/null
    
    rm -f "$PID_FILE"
    log INFO "✅ Daemon stopped"
    
    return 0
}

cmd_restart() {
    cmd_stop
    sleep 2
    cmd_start
}

cmd_status() {
    if [[ ! -f "$PID_FILE" ]] || ! kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
        log INFO "🔴 Daemon not running"
        return 1
    fi
    
    local pid=$(cat "$PID_FILE")
    log INFO "🟢 Daemon running (PID: $pid)"
    
    # Load state
    init_state_storage
    
    local packages
    packages=$(detect_packages)
    
    log INFO ""
    log INFO "📦 Instances:"
    while IFS= read -r pkg; do
        local name="${pkg##*.}"
        local daily_count=$(get_daily_restart_count "$pkg")
        local total_count=$(get_total_restart_count "$pkg")
        
        if is_app_running "$pkg"; then
            log INFO "   🟢 $name ($pkg)"
            log INFO "      └─ Daily restarts: $daily_count/$MAX_RESTARTS | Total: $total_count"
        else
            log INFO "   🔴 $name ($pkg)"
            log INFO "      └─ Daily restarts: $daily_count/$MAX_RESTARTS | Total: $total_count"
        fi
    done <<< "$packages"
    
    return 0
}

cmd_test_webhook() {
    [[ -z "$DISCORD_WEBHOOK" ]] && die "DISCORD_WEBHOOK not configured"
    log INFO "Testing Discord webhook..."
    discord_send "🧪 Test" "Webhook configuration OK ✓" 3447003
    log INFO "✅ Test message sent"
}

cmd_test_screenshot() {
    log INFO "Testing screenshot..."
    local ss
    ss=$(take_screenshot)
    
    if [[ -n "$ss" ]]; then
        log INFO "✅ Screenshot taken: $ss"
        discord_send "🧪 Screenshot Test" "Screenshot capability OK ✓" 3447003 "$ss"
    else
        log ERROR "Failed to take screenshot"
        return 1
    fi
}

cmd_test_launch() {
    local packages
    packages=$(detect_packages) || die "No packages found"
    
    local pkg=$(echo "$packages" | head -1)
    local name="${pkg##*.}"
    
    log INFO "Testing launch untuk $name ($pkg)..."
    if launch_app "$pkg" "$ROBLOX_URL" "$name"; then
        log INFO "✅ Launch test successful"
        return 0
    else
        log ERROR "Launch test failed"
        return 1
    fi
}

cmd_reset_state() {
    log INFO "Resetting state..."
    rm -rf "$STATE_DIR" 2>/dev/null
    mkdir -p "$STATE_DIR" 2>/dev/null
    log INFO "✅ State reset"
}

cmd_help() {
    cat << 'EOF'
╔════════════════════════════════════════════════════════════════╗
║          ROBLOX BOT v2 - Advanced Instance Manager             ║
╚════════════════════════════════════════════════════════════════╝

🎮 COMMANDS:
  start              - Start daemon
  stop               - Stop daemon
  restart            - Restart daemon
  status             - Show status & instance info
  
🧪 TESTING:
  test-webhook       - Test Discord webhook
  test-screenshot    - Test screenshot capture
  test-launch        - Test launch functionality
  
⚙️ MAINTENANCE:
  reset-state        - Reset all state data
  help               - Show this help message

📋 CONFIGURATION:
  Edit variables di bagian CONFIG SECTION script ini

🚀 QUICK START:
  1. Edit ROBLOX_URL & DISCORD_WEBHOOK (optional)
  2. Run: ./roblox_bot.sh start
  3. Monitor: ./roblox_bot.sh status

💡 FEATURES:
  ✓ Auto-detect packages dengan prefix 'free.no'
  ✓ Multi-instance support
  ✓ Crash detection & automatic restart
  ✓ Frozen app detection (CPU-based)
  ✓ Periodic cache clearing
  ✓ Discord notifications
  ✓ Screenshot on crash
  ✓ Daily restart limits
  ✓ Grace period handling
  ✓ Persistent state management

📊 MONITORING:
  - Interval: 10 detik
  - Frozen threshold: 60 detik
  - Cache clear interval: 1 jam (0 = disabled)
  - Max restarts/hari: 50

EOF
}

# =============================================================================
# MAIN ENTRY POINT
# =============================================================================

main() {
    # Verify root access
    if ! exec_su "id" >/dev/null 2>&1; then
        die "❌ Root access required! Run: su"
    fi
    
    case "${1:-help}" in
        daemon)         run_daemon ;;
        start)          cmd_start ;;
        stop)           cmd_stop ;;
        restart)        cmd_restart ;;
        status)         cmd_status ;;
        test-webhook)   cmd_test_webhook ;;
        test-screenshot)cmd_test_screenshot ;;
        test-launch)    cmd_test_launch ;;
        reset-state)    cmd_reset_state ;;
        -v|--verbose)   VERBOSE=1; cmd_status ;;
        help|--help|-h) cmd_help ;;
        *)              log ERROR "Unknown command: $1"; cmd_help; exit 1 ;;
    esac
}

main "$@"