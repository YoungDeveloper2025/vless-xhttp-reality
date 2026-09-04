#!/usr/bin/env bash
set -Eeuo pipefail
DEFAULTS_FILE_NAME="defaults.conf"
DEFAULTS_URL="https://raw.githubusercontent.com/YoungDeveloper2025/vless-xhttp-reality/main/defaults.conf"
TMP_DIR=""
BACKUP_FILE=""
log() {
  printf '%s\n' "$*" >&2
}
die() {
  log "Error: $*"
  exit 1
}
cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf -- "$TMP_DIR"
  fi
}
trap cleanup EXIT
require_root() {
  [[ "$EUID" -eq 0 ]] || die "Run this script as root."
}
load_defaults() {
  local script_path="${BASH_SOURCE[0]:-}"
  local script_dir=""
  local defaults_path=""
  local required
  if [[ -n "$script_path" && "$script_path" != "main" && -f "$script_path" ]]; then
    script_dir="$(cd -- "$(dirname -- "$script_path")" 2>/dev/null && pwd -P || true)"
    if [[ -n "$script_dir" && -f "$script_dir/$DEFAULTS_FILE_NAME" ]]; then
      defaults_path="$script_dir/$DEFAULTS_FILE_NAME"
    fi
  fi
  if [[ -z "$defaults_path" ]]; then
    command -v curl >/dev/null 2>&1 || die "curl is required to download $DEFAULTS_FILE_NAME."
    defaults_path="$TMP_DIR/$DEFAULTS_FILE_NAME"
    curl -fsSL --retry 3 "$DEFAULTS_URL" -o "$defaults_path" || die "Could not download $DEFAULTS_FILE_NAME."
  fi
  bash -n "$defaults_path" || die "$DEFAULTS_FILE_NAME contains invalid Bash syntax."
  # shellcheck disable=SC1090
  . "$defaults_path"
  for required in DEFAULT_SNI DEFAULT_PORT DEFAULT_FINGERPRINT DEFAULT_PATH DEFAULT_MODE DEFAULT_REMARK OUTPUT_TITLE REALITY_TARGET_PORT XRAY_LOG_LEVEL XRAY_LISTEN_ADDRESS XRAY_INSTALL_CHANNEL XRAY_INSTALL_SCRIPT_URL XRAY_CONFIG_FILE APT_LOCK_TIMEOUT; do
    [[ -v "$required" ]] || die "Missing $required in $DEFAULTS_FILE_NAME."
  done
}
validate_ipv4() {
  local ip="$1"
  local octet
  local -a octets
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS='.' read -r -a octets <<< "$ip"
  for octet in "${octets[@]}"; do
    ((10#$octet <= 255)) || return 1
  done
}
validate_settings() {
  [[ "$PORT" =~ ^[0-9]+$ ]] || die "Port must be a number."
  ((PORT >= 1 && PORT <= 65535)) || die "Port must be between 1 and 65535."
  [[ "$REALITY_TARGET_PORT" =~ ^[0-9]+$ ]] || die "REALITY_TARGET_PORT must be a number."
  ((REALITY_TARGET_PORT >= 1 && REALITY_TARGET_PORT <= 65535)) || die "REALITY_TARGET_PORT must be between 1 and 65535."
  [[ "$APT_LOCK_TIMEOUT" =~ ^[0-9]+$ ]] || die "APT_LOCK_TIMEOUT must be a non-negative number."
  [[ "$SNI" =~ ^[A-Za-z0-9.-]+$ && "$SNI" == *.* && "$SNI" != .* && "$SNI" != *. ]] || die "SNI is invalid."
  [[ "$FINGERPRINT" =~ ^[A-Za-z0-9_-]+$ ]] || die "uTLS fingerprint is invalid."
  [[ -n "$CLIENT_PATH" && ! "$CLIENT_PATH" =~ [[:space:]] ]] || die "XHTTP path must be non-empty and contain no spaces."
  [[ "$MODE" =~ ^[A-Za-z0-9_-]+$ ]] || die "XHTTP mode is invalid."
  [[ -n "$OUTPUT_TITLE" && "$OUTPUT_TITLE" != *$'\n'* && "$OUTPUT_TITLE" != *$'\r'* ]] || die "OUTPUT_TITLE is invalid."
  [[ "$XRAY_LOG_LEVEL" =~ ^(debug|info|warning|error|none)$ ]] || die "XRAY_LOG_LEVEL is invalid."
  [[ -n "$XRAY_LISTEN_ADDRESS" && ! "$XRAY_LISTEN_ADDRESS" =~ [[:space:]] ]] || die "XRAY_LISTEN_ADDRESS is invalid."
  [[ "$XRAY_INSTALL_CHANNEL" == "stable" || "$XRAY_INSTALL_CHANNEL" == "beta" ]] || die "XRAY_INSTALL_CHANNEL must be stable or beta."
  [[ "$XRAY_INSTALL_SCRIPT_URL" == https://* ]] || die "XRAY_INSTALL_SCRIPT_URL must use HTTPS."
  [[ "$XRAY_CONFIG_FILE" == /* ]] || die "XRAY_CONFIG_FILE must be an absolute path."
}
get_public_ipv4() {
  local endpoint
  local candidate
  for endpoint in "https://api.ipify.org" "https://ipv4.icanhazip.com" "https://ifconfig.me/ip"; do
    candidate="$(curl -4fsS --connect-timeout 5 --max-time 10 "$endpoint" 2>/dev/null || true)"
    candidate="${candidate//$'\r'/}"
    candidate="${candidate//$'\n'/}"
    if validate_ipv4 "$candidate"; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  candidate="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
  validate_ipv4 "$candidate" || return 1
  printf '%s' "$candidate"
}
port_is_listening() {
  command -v ss >/dev/null 2>&1 || return 1
  ss -H -ltn | awk -v suffix=":$1" '$4 ~ suffix "$" {found=1} END {exit !found}'
}
uri_encode() {
  jq -rn --arg value "$1" '$value|@uri'
}
install_latest_xray() {
  local installer="$TMP_DIR/install-release.sh"
  local -a install_args=(install)
  curl -fsSL --retry 3 "$XRAY_INSTALL_SCRIPT_URL" -o "$installer"
  if [[ "$XRAY_INSTALL_CHANNEL" == "beta" ]]; then
    install_args+=(--beta)
  fi
  bash "$installer" "${install_args[@]}" >&2
}
generate_config() {
  local output_file="$1"
  jq -n \
    --arg uuid "$UUID" \
    --arg sni "$SNI" \
    --arg target "$SNI:$REALITY_TARGET_PORT" \
    --arg log_level "$XRAY_LOG_LEVEL" \
    --arg listen "$XRAY_LISTEN_ADDRESS" \
    --arg private_key "$PRIVATE_KEY" \
    --arg short_id "$SHORT_ID" \
    --arg host "$SERVER_IP" \
    --arg path "$SERVER_PATH" \
    --arg mode "$MODE" \
    --argjson port "$PORT" \
    '{
      log: {
        loglevel: $log_level
      },
      inbounds: [
        {
          tag: "vless-xhttp-reality",
          listen: $listen,
          port: $port,
          protocol: "vless",
          settings: {
            clients: [
              {
                id: $uuid
              }
            ],
            decryption: "none"
          },
          streamSettings: {
            network: "xhttp",
            security: "reality",
            xhttpSettings: {
              host: $host,
              path: $path,
              mode: $mode
            },
            realitySettings: {
              show: false,
              target: $target,
              xver: 0,
              serverNames: [
                $sni
              ],
              privateKey: $private_key,
              shortIds: [
                $short_id
              ]
            }
          },
          sniffing: {
            enabled: true,
            routeOnly: true,
            destOverride: [
              "http",
              "tls",
              "quic"
            ]
          }
        }
      ],
      outbounds: [
        {
          tag: "direct",
          protocol: "freedom"
        },
        {
          tag: "block",
          protocol: "blackhole"
        },
        {
          tag: "IPv4",
          protocol: "freedom",
          settings: {
            domainStrategy: "UseIPv4"
          }
        }
      ],
      routing: {
        rules: [
          {
            type: "field",
            domain: [
              "geosite:apple",
              "geosite:meta",
              "geosite:google",
              "geosite:openai",
              "geosite:spotify",
              "geosite:netflix",
              "geosite:reddit",
              "geosite:speedtest"
            ],
            outboundTag: "IPv4"
          }
        ],
        domainStrategy: "AsIs"
      }
    }' > "$output_file"
}
write_config() {
  local source_file="$1"
  local xray_user
  local xray_group
  mkdir -p "$(dirname "$XRAY_CONFIG_FILE")"
  if [[ -f "$XRAY_CONFIG_FILE" ]]; then
    BACKUP_FILE="$XRAY_CONFIG_FILE.bak.$(date -u +%Y%m%dT%H%M%SZ).$$"
    cp -a -- "$XRAY_CONFIG_FILE" "$BACKUP_FILE"
  fi
  xray_user="$(awk -F= '/^[[:space:]]*User[[:space:]]*=/{gsub(/[[:space:]]/,"",$2); user=$2} END{print user}' /etc/systemd/system/xray.service 2>/dev/null || true)"
  xray_user="${xray_user:-root}"
  if ! id "$xray_user" >/dev/null 2>&1; then
    xray_user="root"
  fi
  xray_group="$(id -gn "$xray_user")"
  install -o root -g "$xray_group" -m 0640 "$source_file" "$XRAY_CONFIG_FILE"
}
rollback_config() {
  if [[ -n "$BACKUP_FILE" && -f "$BACKUP_FILE" ]]; then
    cp -a -- "$BACKUP_FILE" "$XRAY_CONFIG_FILE"
    systemctl restart xray >/dev/null 2>&1 || true
  fi
}
main() {
  require_root
  TMP_DIR="$(mktemp -d)"
  load_defaults
  SNI="$DEFAULT_SNI"
  PORT="$DEFAULT_PORT"
  FINGERPRINT="${DEFAULT_FINGERPRINT,,}"
  CLIENT_PATH="$DEFAULT_PATH"
  MODE="$DEFAULT_MODE"
  REMARK="$DEFAULT_REMARK"
  validate_settings
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "22.04" ]]; then
      log "Warning: This script is designed for Ubuntu 22.04."
    fi
  fi
  export DEBIAN_FRONTEND=noninteractive
  log "Installing required packages..."
  apt-get -o DPkg::Lock::Timeout="$APT_LOCK_TIMEOUT" update >&2
  apt-get -o DPkg::Lock::Timeout="$APT_LOCK_TIMEOUT" install -y ca-certificates curl unzip jq openssl iproute2 >&2
  log "Installing or updating Xray-core from the official XTLS installer..."
  install_latest_xray
  [[ -x /usr/local/bin/xray ]] || die "Xray installation failed."
  SERVER_IP="$(get_public_ipv4)" || die "Could not detect the server public IPv4 address."
  [[ "$CLIENT_PATH" == /* ]] || CLIENT_PATH="/$CLIENT_PATH"
  SERVER_PATH="${CLIENT_PATH%%\?*}"
  [[ -n "$SERVER_PATH" ]] || SERVER_PATH="/"
  UUID="$(/usr/local/bin/xray uuid 2>/dev/null)" || die "Could not generate a UUID."
  KEY_OUTPUT="$(/usr/local/bin/xray x25519 2>&1)" || die "Could not generate REALITY keys."
  PRIVATE_KEY="$(awk -F: '{label=tolower($1); gsub(/[[:space:]]/, "", label); if (label=="privatekey") {value=$2; sub(/^[[:space:]]*/, "", value); sub(/[[:space:]]*$/, "", value); print value; exit}}' <<< "$KEY_OUTPUT")"
  CLIENT_KEY="$(awk -F: '{label=tolower($1); gsub(/[[:space:]]/, "", label); if (label=="password" || label=="password(publickey)" || label=="publickey") {value=$2; sub(/^[[:space:]]*/, "", value); sub(/[[:space:]]*$/, "", value); print value; exit}}' <<< "$KEY_OUTPUT")"
  SHORT_ID="$(openssl rand -hex 8)"
  [[ -n "$UUID" ]] || die "Xray returned an empty UUID."
  [[ -n "$PRIVATE_KEY" ]] || die "Could not parse PrivateKey from the Xray x25519 output."
  [[ -n "$CLIENT_KEY" ]] || die "Could not parse Password (PublicKey) from the Xray x25519 output."
  [[ -n "$SHORT_ID" ]] || die "Could not generate a REALITY short ID."
  TEMP_CONFIG="$TMP_DIR/config.json"
  generate_config "$TEMP_CONFIG"
  log "Validating the Xray configuration..."
  /usr/local/bin/xray run -test -config "$TEMP_CONFIG" >&2
  write_config "$TEMP_CONFIG"
  systemctl stop xray >/dev/null 2>&1 || true
  if port_is_listening "$PORT"; then
    rollback_config
    die "TCP port $PORT is already in use by another service."
  fi
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw allow "$PORT/tcp" >/dev/null 2>&1 || log "Warning: Could not add the UFW rule for TCP port $PORT."
  fi
  systemctl reset-failed xray >/dev/null 2>&1 || true
  if ! systemctl restart xray; then
    rollback_config
    journalctl -u xray -n 30 --no-pager >&2 || true
    die "Xray failed to start; the previous configuration was restored."
  fi
  systemctl enable xray >/dev/null 2>&1
  sleep 1
  if ! systemctl is-active --quiet xray; then
    rollback_config
    journalctl -u xray -n 30 --no-pager >&2 || true
    die "Xray did not stay active; the previous configuration was restored."
  fi
  ENCODED_SNI="$(uri_encode "$SNI")"
  ENCODED_FINGERPRINT="$(uri_encode "$FINGERPRINT")"
  ENCODED_CLIENT_KEY="$(uri_encode "$CLIENT_KEY")"
  ENCODED_SHORT_ID="$(uri_encode "$SHORT_ID")"
  ENCODED_HOST="$(uri_encode "$SERVER_IP")"
  ENCODED_PATH="$(uri_encode "$CLIENT_PATH")"
  ENCODED_MODE="$(uri_encode "$MODE")"
  ENCODED_REMARK="$(uri_encode "$REMARK")"
  VLESS_LINK="vless://$UUID@$SERVER_IP:$PORT?encryption=none&security=reality&sni=$ENCODED_SNI&fp=$ENCODED_FINGERPRINT&pbk=$ENCODED_CLIENT_KEY&sid=$ENCODED_SHORT_ID&type=xhttp&host=$ENCODED_HOST&path=$ENCODED_PATH&mode=$ENCODED_MODE#$ENCODED_REMARK"
  printf '\n%s\n\n%s\n\n' "$OUTPUT_TITLE" "$VLESS_LINK"
}
main "$@"
