#!/usr/bin/env bash

# Terminal Caffeine - NerdHUD v3.2
# A terminal-based system sleep inhibitor for Linux/Wayland

set -euo pipefail

# === GLOBALS ===
SESSION_ID=""
START_TIME=0
CAFFEINE_ACTIVE=1
TIMER_MODE="infinite"
TIMER_REMAINING=0
TIMER_PAUSED_AT=0
INHIBIT_PID=0
INITIAL_MINUTES=0

# Colors
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_CYAN='\033[96m'
C_GREEN='\033[92m'
C_YELLOW='\033[93m'
C_RED='\033[91m'
C_BLUE='\033[94m'
C_MAGENTA='\033[95m'

# Box drawing constants
BOX_WIDTH=64
CONTENT_WIDTH=62

# === UTILITY FUNCTIONS ===

generate_session_id() {
    printf "%04X" $((RANDOM % 65536))
}

get_uptime() {
    local elapsed=$(($(date +%s) - START_TIME))
    printf "%02d:%02d" $((elapsed/3600)) $(((elapsed%3600)/60))
}

format_time() {
    local seconds=$1
    printf "%02d:%02d" $((seconds/3600)) $(((seconds%3600)/60))
}

print_line() {
    local content="$1"
    local display_len=${#content}
    local padding=$((CONTENT_WIDTH - display_len))
    printf "║ %s%*s ║\n" "$content" "$padding" ""
}

print_colored_line() {
    local content="$1"
    local plain_content=$(echo -e "$content" | sed 's/\x1B\[[0-9;]*[JKmsu]//g')
    local display_len=${#plain_content}
    local padding=$((CONTENT_WIDTH - display_len))
    printf "║ %b%*s ║\n" "$content" "$padding" ""
}

draw_border() {
    local char="$1"
    local left="$2"
    local right="$3"
    printf "%b" "$C_CYAN"
    printf "%s" "$left"
    for ((i=0; i<CONTENT_WIDTH+2; i++)); do printf "%s" "$char"; done
    printf "%s\n" "$right"
    printf "%b" "$C_RESET"
}

# === STARTUP SCREEN ===

show_startup_prompt() {
    clear
    printf "${C_BOLD}${C_YELLOW}    ☕ Terminal Caffeine${C_RESET}\n\n" >&2
    
    local BOX_W=49
    
    print_startup_line() {
        local content="$1"
        local plain_content=$(echo -e "$content" | sed 's/\x1B\[[0-9;]*[JKmsu]//g')
        local display_len=${#plain_content}
        local padding=$((BOX_W - display_len))
        printf "${C_CYAN}║${C_RESET} %b%*s ${C_CYAN}║${C_RESET}\n" "$content" "$padding" "" >&2
    }
    
    printf "${C_CYAN}╔" >&2
    for ((i=0; i<BOX_W+2; i++)); do printf "═"; done >&2
    printf "╗${C_RESET}\n" >&2
    
    print_startup_line "Select timer duration:"
    print_startup_line ""
    print_startup_line "      ${C_YELLOW})  (${C_RESET}        ${C_GREEN}1${C_RESET} → 15 minutes"
    print_startup_line "     ${C_YELLOW}(   ) )${C_RESET}      ${C_GREEN}2${C_RESET} → 30 minutes"
    print_startup_line "      ${C_YELLOW}) ( (${C_RESET}       ${C_GREEN}3${C_RESET} → 45 minutes"
    print_startup_line "    ${C_YELLOW}_______)_${C_RESET}     ${C_GREEN}4${C_RESET} → 60 minutes"
    print_startup_line " ${C_YELLOW}.-'---------|${C_RESET}    ${C_YELLOW}0${C_RESET} → Infinite"
    print_startup_line "${C_YELLOW}( C|/\\/\\/\\/\\/|${C_RESET}    ${C_BLUE}6${C_RESET} → Custom"
    print_startup_line " ${C_YELLOW}'-./\\/\\/\\/\\/|${C_RESET}"
    print_startup_line "   ${C_YELLOW}'_________'${C_RESET}     ${C_BOLD}Press key:${C_RESET}"
    print_startup_line "    ${C_YELLOW}'-------'${C_RESET}"
    
    printf "${C_CYAN}╚" >&2
    for ((i=0; i<BOX_W+2; i++)); do printf "═"; done >&2
    printf "╝${C_RESET}\n" >&2
    
    local choice
    read -n 1 -r choice >&2
    echo "" >&2
    
    case "$choice" in
        1) INITIAL_MINUTES=15 ;;
        2) INITIAL_MINUTES=30 ;;
        3) INITIAL_MINUTES=45 ;;
        4) INITIAL_MINUTES=60 ;;
        0) INITIAL_MINUTES=0 ;;
        6)
            echo "" >&2
            printf "${C_BOLD}Enter custom duration (minutes): ${C_RESET}" >&2
            read -r custom >&2
            INITIAL_MINUTES="${custom:-0}"
            ;;
        *) INITIAL_MINUTES=0 ;;
    esac
}

# === INHIBITION CONTROL ===

start_inhibit() {
    if [[ $INHIBIT_PID -eq 0 ]]; then
        if ! command -v systemd-inhibit &>/dev/null; then
            echo "ERROR: systemd-inhibit not found. This tool requires systemd." >&2
            exit 1
        fi
        
        systemd-inhibit --what=idle:sleep:shutdown \
                        --who="Terminal Caffeine" \
                        --why="User requested system stay awake" \
                        --mode=block \
                        sleep infinity &
        INHIBIT_PID=$!
        CAFFEINE_ACTIVE=1
    fi
}

stop_inhibit() {
    if [[ $INHIBIT_PID -ne 0 ]]; then
        kill $INHIBIT_PID 2>/dev/null || true
        wait $INHIBIT_PID 2>/dev/null || true
        INHIBIT_PID=0
        CAFFEINE_ACTIVE=0
    fi
}

# === TIMER FUNCTIONS ===

set_timer() {
    local minutes=$1
    if [[ $minutes -eq 0 ]]; then
        TIMER_MODE="infinite"
        TIMER_REMAINING=0
    else
        TIMER_MODE="running"
        TIMER_REMAINING=$((minutes * 60))
    fi
}

pause_timer() {
    if [[ "$TIMER_MODE" == "running" ]]; then
        TIMER_MODE="paused"
        TIMER_PAUSED_AT=$(date +%s)
    elif [[ "$TIMER_MODE" == "paused" ]]; then
        TIMER_MODE="running"
    fi
}

reset_timer() {
    TIMER_MODE="infinite"
    TIMER_REMAINING=0
}

update_timer() {
    if [[ "$TIMER_MODE" == "running" && $TIMER_REMAINING -gt 0 ]]; then
        ((TIMER_REMAINING--)) || true
        
        if [[ $TIMER_REMAINING -eq 0 ]]; then
            timer_expired
        fi
    fi
}

timer_expired() {
    stop_inhibit
    printf '\a'
    
    if command -v notify-send &>/dev/null; then
        notify-send -u critical "Terminal Caffeine" "Timer expired - system will sleep normally"
    fi
    
    clear
    printf "${C_YELLOW}⏰ Timer expired!${C_RESET} Press any key to exit...\n"
    read -n 1 -r -s
    cleanup_and_exit
}

# === UI RENDERING ===

draw_ui() {
    printf '\033c'
    
    local state_text="${C_GREEN}● ACTIVE${C_RESET}"
    local idle_text="${C_GREEN}BLOCKED${C_RESET}"
    
    if [[ $CAFFEINE_ACTIVE -eq 0 ]]; then
        state_text="${C_RED}○ INACTIVE${C_RESET}"
        idle_text="${C_RED}NOT BLOCKED${C_RESET}"
    fi
    
    local uptime_str=$(get_uptime)
    local start_time_str=$(date -d "@$START_TIME" +%H:%M 2>/dev/null || date -r "$START_TIME" +%H:%M)
    local ends_at_str="∞"
    if [[ "$TIMER_MODE" != "infinite" ]]; then
        local ends_at=$(($(date +%s) + TIMER_REMAINING))
        ends_at_str=$(date -d "@$ends_at" +%H:%M 2>/dev/null || date -r "$ends_at" +%H:%M)
    fi
    local remaining_str="∞"
    if [[ "$TIMER_MODE" != "infinite" ]]; then
        remaining_str=$(format_time $TIMER_REMAINING)
    fi
    
    # Header
    draw_border "═" "╔" "╗"
    print_colored_line "${C_BOLD}${C_CYAN}TERMINAL CAFFEINE${C_RESET}                   ${C_DIM}Session #${C_MAGENTA}$SESSION_ID${C_RESET}"
    draw_border "─" "╟" "╢"
    print_colored_line "${C_BOLD}${C_BLUE}STATUS${C_RESET} ${C_DIM}→${C_RESET} $state_text ${C_DIM}|${C_RESET} ${C_DIM}Up:${C_RESET}${C_CYAN}$uptime_str${C_RESET} ${C_DIM}|${C_RESET} ${C_DIM}Idle:${C_RESET}$idle_text"
    draw_border "─" "╟" "╢"

    # Timer section with coffee cup and status centered in empty space
    local timer_status=""
    case "$TIMER_MODE" in
        infinite)
            timer_status="${C_YELLOW}∞ INFINITE${C_RESET}"
            ;;
        running)
            timer_status="${C_GREEN}▶ RUNNING${C_RESET}"
            ;;
        paused)
            timer_status="${C_YELLOW}⏸ PAUSED${C_RESET}"
            ;;
    esac
    
    local inhibit_status="${C_GREEN}SUCCESS${C_RESET}"
    [[ $CAFFEINE_ACTIVE -eq 0 ]] && inhibit_status="${C_RED}FAILED${C_RESET}"
    
    print_line ""
    print_colored_line "     ${C_YELLOW})  (${C_RESET}                 ${C_BOLD}${C_BLUE}TIMER${C_RESET} ${C_DIM}→${C_RESET} $timer_status"
    print_colored_line "    ${C_YELLOW}(   ) )${C_RESET}"
    print_colored_line "     ${C_YELLOW}) ( (${C_RESET}                 ${C_BOLD}Started:${C_RESET}  ${C_CYAN}$start_time_str${C_RESET}"
    print_colored_line "   ${C_YELLOW}_______)_${C_RESET}               ${C_BOLD}Ends at:${C_RESET}  ${C_CYAN}$ends_at_str${C_RESET}"
    print_colored_line "${C_YELLOW}.-'---------|${C_RESET}              ${C_BOLD}Remain:${C_RESET}   ${C_YELLOW}$remaining_str${C_RESET}"
    print_colored_line "${C_YELLOW}( C|/\\/\\/\\/\\/|${C_RESET}             ${C_BOLD}Inhibit:${C_RESET} $inhibit_status"
    print_colored_line "${C_YELLOW}'-./\\/\\/\\/\\/|${C_RESET}"
    print_colored_line "  ${C_YELLOW}'_________'${C_RESET}"
    print_colored_line "   ${C_YELLOW}'-------'${C_RESET}"
    
    draw_border "─" "╟" "╢"
    print_colored_line "${C_GREEN}Q${C_RESET} Quit ${C_GREEN}T${C_RESET} Timer ${C_GREEN}P${C_RESET} Pause ${C_GREEN}R${C_RESET} Reset ${C_GREEN}H${C_RESET} Help ${C_GREEN}0-4${C_RESET} Presets"
    draw_border "═" "╚" "╝"
}

show_help() {
    printf '\033c'
    printf "${C_CYAN}"
    draw_border "═" "╔" "╗"
    printf "${C_RESET}"
    print_colored_line "${C_BOLD}${C_YELLOW}HELP${C_RESET}"
    draw_border "─" "╟" "╢"
    print_colored_line "${C_GREEN}Q${C_RESET}       Quit and exit"
    print_colored_line "${C_GREEN}T${C_RESET}       Set custom timer (minutes)"
    print_colored_line "${C_GREEN}P${C_RESET}       Pause / resume timer"
    print_colored_line "${C_GREEN}R${C_RESET}       Reset timer to infinite"
    print_colored_line "${C_GREEN}H${C_RESET}       Toggle this help"
    print_line ""
    print_colored_line "${C_YELLOW}Quick Presets:${C_RESET}"
    print_colored_line "${C_GREEN}1${C_RESET}       15 minutes"
    print_colored_line "${C_GREEN}2${C_RESET}       30 minutes"
    print_colored_line "${C_GREEN}3${C_RESET}       45 minutes"
    print_colored_line "${C_GREEN}4${C_RESET}       60 minutes"
    print_colored_line "${C_GREEN}0${C_RESET}       Infinite (no timer)"
    printf "${C_CYAN}"
    draw_border "═" "╚" "╝"
    printf "${C_RESET}\n"
    printf "${C_DIM}Press any key to return...${C_RESET}\n"
    read -n 1 -r -s
}

# === INPUT HANDLING ===

handle_input() {
    local key=""
    if read -t 0.05 -n 1 -r -s key 2>/dev/null; then
        case "$key" in
            q|Q) cleanup_and_exit ;;
            t|T)
                printf "\n${C_BOLD}Enter timer duration (minutes): ${C_RESET}"
                read -r minutes
                set_timer "${minutes:-0}"
                ;;
            p|P) pause_timer ;;
            r|R) reset_timer ;;
            h|H) show_help ;;
            1) set_timer 15 ;;
            2) set_timer 30 ;;
            3) set_timer 45 ;;
            4) set_timer 60 ;;
            0) reset_timer ;;
        esac
    fi
}

# === STATUS COMMAND ===

print_status() {
    if [[ $CAFFEINE_ACTIVE -eq 1 ]]; then
        echo "ACTIVE"
        echo "uptime=$(get_uptime)"
        if [[ "$TIMER_MODE" == "infinite" ]]; then
            echo "timer=infinite"
        else
            echo "timer=$(format_time $TIMER_REMAINING)"
        fi
    else
        echo "INACTIVE"
    fi
}

# === CLEANUP ===

cleanup_and_exit() {
    stop_inhibit
    printf '\033c'
    exit 0
}

# === MAIN LOOP ===

main_loop() {
    tput civis 2>/dev/null || true
    
    local last_draw=$(date +%s)
    draw_ui
    
    while true; do
        handle_input
        update_timer
        
        local now=$(date +%s)
        if [[ $((now - last_draw)) -ge 60 ]]; then
            draw_ui
            last_draw=$now
        fi
        
        sleep 0.2
    done
}

# === ENTRY POINT ===

main() {
    if [[ "${1:-}" == "--status" ]]; then
        print_status
        exit 0
    fi
    
    trap cleanup_and_exit EXIT INT TERM
    SESSION_ID=$(generate_session_id)
    START_TIME=$(date +%s)
    
    show_startup_prompt
    set_timer "$INITIAL_MINUTES"
    start_inhibit
    main_loop
}

main "$@"