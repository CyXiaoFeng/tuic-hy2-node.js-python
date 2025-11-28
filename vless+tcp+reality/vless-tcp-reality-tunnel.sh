#!/bin/bash
# =========================================
# VLESS + TCP + Reality + Cloudflare Tunnel
# 翼龙面板专用：双通道部署
# Reality 直连 + CF Tunnel 中转
# =========================================
set -uo pipefail

# ========== Cloudflare Tunnel 配置 ==========
TUNNEL_PORT=6868
TUNNEL_UUID="74a91aaf-b506-40e8-9949-361480d38037"
TUNNEL_TOKEN="eyJhIjoiOTFmMzMxNTllZTgwMTI4ZDY1MGZlNTZkMTc3MWVhNzciLCJ0IjoiZjA1YmNhODQtNTM2Ni00ZmViLWI1NzYtZTc1NzEyMTg0ODZmIiwicyI6Ik4ySmxNR1UyWWpBdE1XWmhNUzAwWVdabExUbGxNemt0TUdKaU16UmhaamRrWldFeiJ9"
TUNNEL_DOMAIN="wbtunnel.wai2mini.dpdns.org"

# ========== 自动检测端口（翼龙环境变量优先）==========
if [[ -n "${SERVER_PORT:-}" ]]; then
  PORT="$SERVER_PORT"
  echo "Port (env): $PORT"
elif [[ $# -ge 1 && -n "$1" ]]; then
  PORT="$1"
  echo "Port (arg): $PORT"
else
  PORT=3250
  echo "Port (default): $PORT"
fi

# ========== 文件定义 ==========
MASQ_DOMAIN="www.bing.com"
VLESS_BIN="./xray"
CLOUDFLARED_BIN="./cloudflared"
VLESS_CONFIG="vless-reality.json"
VLESS_LINK="vless_link.txt"
CF_LINK="cf_vless_link.txt"

# ========== 加载已有配置 ==========
load_config() {
  if [[ -f "$VLESS_CONFIG" ]]; then
    VLESS_UUID=$(grep -o '"id": "[^"]*' "$VLESS_CONFIG" | head -1 | cut -d'"' -f4)
    echo "Loaded existing UUID: $VLESS_UUID"
  fi
}

# ========== 下载 Xray ==========
get_xray() {
  if [[ ! -x "$VLESS_BIN" ]]; then
    echo "Downloading Xray v1.8.23..."
    curl -L -o xray.zip "https://github.com/XTLS/Xray-core/releases/download/v1.8.23/Xray-linux-64.zip" --fail --connect-timeout 15
    unzip -j xray.zip xray -d . >/dev/null 2>&1
    rm -f xray.zip
    chmod +x "$VLESS_BIN"
  fi
}

# ========== 下载 Cloudflared ==========
get_cloudflared() {
  if [[ ! -x "$CLOUDFLARED_BIN" ]]; then
    echo "Downloading Cloudflared..."
    local arch=$(uname -m)
    local url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-"
    case "$arch" in
      x86_64) url="${url}amd64" ;;
      aarch64) url="${url}arm64" ;;
      armv7l) url="${url}arm" ;;
      *) echo "Unsupported arch: $arch"; exit 1 ;;
    esac
    curl -L -o "$CLOUDFLARED_BIN" "$url" --fail --connect-timeout 15
    chmod +x "$CLOUDFLARED_BIN"
  fi
}

# ========== 生成 VLESS Reality 配置 ==========
gen_vless_config() {
  local shortId=$(openssl rand -hex 8)
  local keys=$("$VLESS_BIN" x25519 2>/dev/null || echo "Private key: fallbackpriv1234567890abcdef1234567890abcdef
Public key: fallbackpubk1234567890abcdef1234567890abcdef")
  local priv=$(echo "$keys" | grep Private | awk '{print $3}')
  local pub=$(echo "$keys" | grep Public | awk '{print $3}')
  
  cat > "$VLESS_CONFIG" <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$VLESS_UUID", "flow": "xtls-rprx-vision"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$MASQ_DOMAIN:443",
          "xver": 0,
          "serverNames": ["$MASQ_DOMAIN", "www.microsoft.com"],
          "privateKey": "$priv",
          "publicKey": "$pub",
          "shortIds": ["$shortId"],
          "fingerprint": "chrome",
          "spiderX": "/"
        }
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "port": $TUNNEL_PORT,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$TUNNEL_UUID"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/"}
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    }
  ],
  "outbounds": [{"protocol": "freedom"}]
}
EOF
  
  # 保存 Reality 信息
  cat > reality_info.txt <<EOF
Reality Public Key: $pub
Reality Short ID: $shortId
VLESS UUID (Reality): $VLESS_UUID
VLESS UUID (CF Tunnel): $TUNNEL_UUID
Reality Port: $PORT
CF Tunnel Port: $TUNNEL_PORT
CF Tunnel Domain: $TUNNEL_DOMAIN
EOF
}

# ========== 生成客户端链接 ==========
gen_links() {
  local ip="$1"
  local pub=$(grep "Public Key" reality_info.txt | awk '{print $4}')
  local sid=$(grep "Short ID" reality_info.txt | awk '{print $4}')
  
  # Reality 直连链接
  cat > "$VLESS_LINK" <<EOF
vless://$VLESS_UUID@$ip:$PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$MASQ_DOMAIN&fp=chrome&pbk=$pub&sid=$sid&type=tcp&spx=/#VLESS-Reality-Direct
EOF
  
  # CF Tunnel 链接
  cat > "$CF_LINK" <<EOF
vless://$TUNNEL_UUID@$TUNNEL_DOMAIN:443?encryption=none&security=tls&sni=$TUNNEL_DOMAIN&type=ws&host=$TUNNEL_DOMAIN&path=%2F#VLESS-CF-Tunnel
EOF
  
  echo "========================================="
  echo "通道 1: VLESS Reality 直连 (极速)"
  cat "$VLESS_LINK"
  echo ""
  echo "通道 2: Cloudflare Tunnel 中转 (稳定)"
  cat "$CF_LINK"
  echo "========================================="
}

# ========== 启动 Cloudflared ==========
run_cloudflared() {
  echo "Starting Cloudflare Tunnel..."
  while true; do
    "$CLOUDFLARED_BIN" tunnel --no-autoupdate run --token "$TUNNEL_TOKEN" >/dev/null 2>&1 || sleep 5
  done
}

# ========== 启动 VLESS ==========
run_vless() {
  echo "Starting VLESS Reality on :$PORT + CF Tunnel on :$TUNNEL_PORT..."
  while true; do
    "$VLESS_BIN" run -c "$VLESS_CONFIG" >/dev/null 2>&1 || sleep 5
  done
}

# ========== 主函数 ==========
main() {
  echo "Deploying VLESS + TCP + Reality + Cloudflare Tunnel"
  load_config
  [[ -z "${VLESS_UUID:-}" ]] && VLESS_UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16)
  
  get_xray
  get_cloudflared
  gen_vless_config
  
  ip=$(curl -s https://api64.ipify.org || echo "127.0.0.1")
  gen_links "$ip"
  
  # 后台启动 Cloudflared
  run_cloudflared &
  
  # 前台运行 VLESS
  run_vless
}

main "$@"
