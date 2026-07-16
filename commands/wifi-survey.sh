#!/usr/bin/env bash

: "${SCRIPT_DIR:?SCRIPT_DIR must be set by entry.sh}"

# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=../lib/platform.sh
. "$SCRIPT_DIR/lib/platform.sh"

wifi_survey_usage() {
    cat <<'EOF'
Usage:
  curl -fsSL https://raw.githubusercontent.com/codevilot/cli/main/entry.sh | bash -s -- wifi-survey [options]

Show Linux Wi-Fi channel utilization from iw survey data.

Options:
  --interface <iface>       Wi-Fi interface, for example wlan0 or wlp2s0
  --channel <channel>       Tune to a channel before measuring, for example 36
  --freq <mhz>              Tune to a frequency before measuring, for example 5180
  --width <width>           Channel width for --freq, for example 20, 40, 80, 160
  --center-freq1 <mhz>      Center frequency for wide channels, for example 5210
  --monitor                 Put the interface in monitor mode before tuning
  --in-use                  Show only the currently active survey entry
  --file <path>             Read saved iw survey output instead of running iw
  --help                    Show this help

Examples:
  wifi-survey --interface wlan0 --channel 36 --monitor
  wifi-survey --interface wlan0 --freq 5180 --width 80 --center-freq1 5210
  wifi-survey --in-use
EOF
}

wifi_survey_parse_args() {
    WIFI_SURVEY_IFACE=""
    WIFI_SURVEY_CHANNEL=""
    WIFI_SURVEY_FREQ=""
    WIFI_SURVEY_WIDTH=""
    WIFI_SURVEY_CENTER_FREQ1=""
    WIFI_SURVEY_MONITOR=0
    WIFI_SURVEY_IN_USE=0
    WIFI_SURVEY_FILE=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --interface|-i)
                [[ $# -ge 2 ]] || die "--interface requires a value"
                WIFI_SURVEY_IFACE="$2"
                shift 2
                ;;
            --channel|-c)
                [[ $# -ge 2 ]] || die "--channel requires a value"
                WIFI_SURVEY_CHANNEL="$2"
                shift 2
                ;;
            --freq|-f)
                [[ $# -ge 2 ]] || die "--freq requires a value"
                WIFI_SURVEY_FREQ="$2"
                shift 2
                ;;
            --width)
                [[ $# -ge 2 ]] || die "--width requires a value"
                WIFI_SURVEY_WIDTH="$2"
                shift 2
                ;;
            --center-freq1)
                [[ $# -ge 2 ]] || die "--center-freq1 requires a value"
                WIFI_SURVEY_CENTER_FREQ1="$2"
                shift 2
                ;;
            --monitor)
                WIFI_SURVEY_MONITOR=1
                shift
                ;;
            --in-use)
                WIFI_SURVEY_IN_USE=1
                shift
                ;;
            --file)
                [[ $# -ge 2 ]] || die "--file requires a value"
                WIFI_SURVEY_FILE="$2"
                shift 2
                ;;
            --help|-h)
                wifi_survey_usage
                exit 0
                ;;
            *)
                die "Unknown option for wifi-survey: $1"
                ;;
        esac
    done

    [[ -z "$WIFI_SURVEY_CHANNEL" || -z "$WIFI_SURVEY_FREQ" ]] || die "Use either --channel or --freq, not both"
}

wifi_survey_iw() {
    wifi_survey_priv iw "$@"
}

wifi_survey_priv() {
    if [[ "$(id -u 2>/dev/null || printf 1)" == "0" ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

wifi_survey_detect_iface() {
    iw dev 2>/dev/null | awk '/^[[:space:]]*Interface[[:space:]]+/ { print $2; exit }'
}

wifi_survey_normalize_width() {
    local width="$1"
    case "$width" in
        20|40|80|160|80+80) printf '%s' "$width" ;;
        20MHz|40MHz|80MHz|160MHz) printf '%s' "${width%MHz}" ;;
        *) die "--width must be one of 20, 40, 80, 160, 80+80" ;;
    esac
}

wifi_survey_prepare_radio() {
    local iface="$1" width

    if [[ -n "$WIFI_SURVEY_CHANNEL" ]]; then
        wifi_survey_iw dev "$iface" set channel "$WIFI_SURVEY_CHANNEL"
    elif [[ -n "$WIFI_SURVEY_FREQ" ]]; then
        if [[ -n "$WIFI_SURVEY_WIDTH" ]]; then
            width="$(wifi_survey_normalize_width "$WIFI_SURVEY_WIDTH")"
            [[ -n "$WIFI_SURVEY_CENTER_FREQ1" ]] || die "--center-freq1 is required when --freq uses --width"
            wifi_survey_iw dev "$iface" set freq "$WIFI_SURVEY_FREQ" "$width" "$WIFI_SURVEY_CENTER_FREQ1"
        else
            wifi_survey_iw dev "$iface" set freq "$WIFI_SURVEY_FREQ"
        fi
    fi
}

wifi_survey_print_table() {
    local only_in_use="$1"
    awk -v only_in_use="$only_in_use" '
        function reset() {
            iface = ""; freq = ""; in_use = ""; noise = "-"
            active = ""; busy = ""; rx = ""; tx = ""
        }
        function pct(value, total) {
            if (value == "" || total == "" || total == 0) {
                return "-"
            }
            return sprintf("%.1f%%", (value * 100.0) / total)
        }
        function emit() {
            if (freq == "" || active == "") {
                return
            }
            if (only_in_use == "1" && in_use != "yes") {
                return
            }
            printf "%-10s %-9s %-7s %-8s %-10s %-10s %-10s %-10s %-10s\n", \
                iface, freq, (in_use == "yes" ? "yes" : "no"), noise, \
                pct(busy, active), pct(rx, active), pct(tx, active), active, busy
            rows++
        }
        BEGIN {
            reset()
            printf "%-10s %-9s %-7s %-8s %-10s %-10s %-10s %-10s %-10s\n", \
                "IFACE", "FREQ", "IN_USE", "NOISE", "BUSY", "RX", "TX", "ACTIVE_MS", "BUSY_MS"
            printf "%-10s %-9s %-7s %-8s %-10s %-10s %-10s %-10s %-10s\n", \
                "----------", "---------", "-------", "--------", "----------", "----------", "----------", "----------", "----------"
        }
        /^Survey data from / {
            emit()
            reset()
            iface = $4
            next
        }
        /^[[:space:]]*frequency:/ {
            freq = $2
            if ($0 ~ /\[in use\]/) {
                in_use = "yes"
            }
            next
        }
        /^[[:space:]]*noise:/ { noise = $2 " " $3; next }
        /^[[:space:]]*channel active time:/ { active = $4; next }
        /^[[:space:]]*channel busy time:/ { busy = $4; next }
        /^[[:space:]]*channel receive time:/ { rx = $4; next }
        /^[[:space:]]*channel transmit time:/ { tx = $4; next }
        END {
            emit()
            if (rows == 0) {
                printf "No survey rows found.\n" > "/dev/stderr"
                exit 1
            }
        }
    '
}

wifi_survey_main() {
    local iface
    wifi_survey_parse_args "$@"

    if [[ -n "$WIFI_SURVEY_FILE" ]]; then
        [[ -r "$WIFI_SURVEY_FILE" ]] || die "Cannot read survey file: $WIFI_SURVEY_FILE"
        wifi_survey_print_table "$WIFI_SURVEY_IN_USE" <"$WIFI_SURVEY_FILE"
        return 0
    fi

    is_linux || die "wifi-survey requires Linux because it uses iw survey data"
    have_command iw || die "iw command not found. Install the iw package first."
    have_command sudo || [[ "$(id -u 2>/dev/null || printf 1)" == "0" ]] || die "sudo command not found"
    if [[ "$WIFI_SURVEY_MONITOR" == "1" ]]; then
        have_command ip || die "ip command not found. Install the iproute2 package first."
    fi

    iface="$WIFI_SURVEY_IFACE"
    if [[ -z "$iface" ]]; then
        iface="$(wifi_survey_detect_iface)"
        [[ -n "$iface" ]] || die "No Wi-Fi interface found from: iw dev"
    fi

    if [[ "$WIFI_SURVEY_MONITOR" == "1" || -n "$WIFI_SURVEY_CHANNEL" || -n "$WIFI_SURVEY_FREQ" ]]; then
        if [[ "$WIFI_SURVEY_MONITOR" == "1" ]]; then
            wifi_survey_priv ip link set "$iface" down
            wifi_survey_iw dev "$iface" set type monitor
            wifi_survey_priv ip link set "$iface" up
        else
            wifi_survey_prepare_radio "$iface"
        fi
        if [[ "$WIFI_SURVEY_MONITOR" == "1" ]] && [[ -n "$WIFI_SURVEY_CHANNEL" || -n "$WIFI_SURVEY_FREQ" ]]; then
            wifi_survey_prepare_radio "$iface"
        fi
    fi

    wifi_survey_iw dev "$iface" survey dump | wifi_survey_print_table "$WIFI_SURVEY_IN_USE"
}
