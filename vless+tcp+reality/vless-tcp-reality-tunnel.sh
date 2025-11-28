#!/bin/bash
# =========================================
# 纯 VLESS + TCP + Reality 单节点 + Cloudflare 隧道
# 翼龙面板专用：自动检测端口 + 固定 Cloudflare Tunnel
# =========================================
set -uo pipefail

# ===================== 隧道常量 =====================
TUNNEL_PORT=6868
TUNNEL_UUID="74a91aaf-b506-40e8-9949-361480d38037"
TUNNEL_TOKEN="eyJhIjoiOTFmMzMxNTllZTgwMTI4ZDY1MGZlNTZkMTc3MWVhNzciLCJ0IjoiZjA1YmNhODQtNTM2Ni00ZmViLWI1NzYtZTc1NzEyMTg0ODZmIiwicyI6Ik4ySmxNR1UyWWpBdE1XWmhNUzAwWVdabExUbGxNemt0TUdKaU16UmhaamRrWldFeiJ9"
TUNNEL_DOMAIN="wbtunnel.wai2mini.dpdns.org"

# Reality 伪装域
MASQ_DOMAIN="www.bing.com"

# 文件名定义
VLESS_BIN="./xray"
VLESS_CONFIG="vless-reality.json"
VLESS_LINK="vless_link.txt"

CF_BIN="./cloudflared"
CF_LOG="cf.log"

# ===================== 自动检测端口 =====================
if [[ -n "${SERVER_PORT:-}" ]]; then
  PORT="$SERVER_PORT"
  echo "Port (env): $PORT"
elif [[ $# -ge 1 && -n "$1" ]]; then
  PORT="$1"
  echo "Port (arg): $PORT"
else
  PORT="$TUNNEL_PORT"
  echo "Port (const): $PORT"
fi

# ===================== 加载已有配置 =====================
load_config() {
  if [[ -f "$VLESS_CONFIG" ]]; then
    VLESS_UUID=$(grep -o '"id": "[^"]*' "$VLESS_CONFIG" | head -1 | cut -d'"' -f4)
    echo "Loaded existing UUID: $VLESS_UUID"
  fi
}

# ===================== 下载 Xray =====================
get_xray() {
  if [[ ! -x "$VLESS_BIN" ]]; then
    echo "Downloading Xray v1.8.23..."
    curl -L -o xray.zip "https://github.com/XTLS/Xray-core/releases/download/v1.8.23/Xray-linux-64.zip" --fail --connect-timeout 15
    unzip -j xray.zip xray -d . >/dev/null 2>&1
    rm -f xray.zip
    chmod +x "$VLESS_BIN"
  fi
}

# ===================== 下载 Cloudflared =====================
get_cloudflared() {
  if [[ -x "$CF_BIN" ]]; then
    echo "cloudflared already exists, skip download."
    return
  fi

  echo "Downloading cloudflared..."
  curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" -o "$CF_BIN" --fail --connect-timeout 15
  chmod +x "$CF_BIN"
}

# ===================== 启动 Cloudflare 命名 Tunnel =====================
start_cf_tunnel() {
  echo "Starting Cloudflare Named Tunnel with fixed domain: $TUNNEL_DOMAIN"
  # 使用固定 TUNNEL_TOKEN 运行已在 Cloudflare 面板配置好的命名隧道
  nohup "$CF_BIN" tunnel --no-autoupdate run --token "$TUNNEL_TOKEN" >"$CF_LOG" 2>&1 &
}

# ===================== 生成 VLESS Reality 配置 =====================
gen_vless_config() {
  echo "[XRAY] Generating VLESS Reality config..."

  local shortId
  shortId=$(openssl rand -hex 8)

  local keys priv pub
  keys=$("$VLESS_BIN" x25519)
  priv=$(echo "$keys" | grep "Private" | awk '{print $3}')
  pub=$(echo "$keys"  | grep "Public"  | awk '{print $3}')

  # 优先使用写死的 TUNNEL_UUID，如果已有配置中读取到 VLESS_UUID，则以已有为准
  if [[ -z "${VLESS_UUID:-}" ]]; then
    VLESS_UUID="$TUNNEL_UUID"
  fi

  cat > "$VLESS_CONFIG" <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [{
    "port": $PORT,
    "listen": "127.0.0.1",
    "protocol": "vless",
    "settings": {
      "clients": [{"id": "$VLESS_UUID", "flow": "xtls-rprx-vision"}],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",  // 使用 TCP 协议
      "security": "reality",  // Reality 协议
      "realitySettings": {
        "show": false,
        "dest": "$MASQ_DOMAIN:443",  // 伪装目标域名
        "xver": 0,
        "serverNames": ["$MASQ_DOMAIN", "www.microsoft.com"],
        "privateKey": "$priv",
        "publicKey": "$pub",
        "shortIds": ["$shortId"],
        "fingerprint": "chrome",
        "spiderX": "/",
        "tls": false  // 禁用 TLS 验证
      }
    },
    "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
  }],
  "outbounds": [{"protocol": "freedom"}]
}
EOF

  # 保存 Reality 信息
  cat > reality_info.txt <<EOF
Reality Public Key: $pub
Reality Short ID: $shortId
VLESS UUID: $VLESS_UUID
Port: $PORT
EOF
}

# ===================== 生成客户端链接（单行输出节点）==========
gen_link() {
  local ip="$1"
  local pub sid

  pub=$(grep "Public Key" reality_info.txt | awk '{print $4}')
  sid=$(grep "Short ID" reality_info.txt | awk '{print $4}')

  {
    echo "========================================="
    echo "VLESS + TCP + Reality 节点信息"
    echo "（已写死 Cloudflare 隧道域名，下面链接为单行）"
    echo "========================================="
    echo "直连 IP 节点（如环境支持直连，可使用）："
    local direct_link="vless://${VLESS_UUID}@${ip}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${MASQ_DOMAIN}&fp=chrome&pbk=${pub}&sid=${sid}&type=tcp&spx=/#VLESS-Reality-IP"
    echo "$direct_link"
    echo
    echo "Cloudflare 隧道节点（推荐使用）："
    local cf_link="vless://${VLESS_UUID}@${TUNNEL_DOMAIN}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${MASQ_DOMAIN}&fp=chrome&pbk=${pub}&sid=${sid}&type=tcp&spx=/#VLESS-Reality-CF"
    echo "$cf_link"
    echo "========================================="
  } > "$VLESS_LINK"

  cat "$VLESS_LINK"
}

# ===================== 启动服务 =====================
run_vless() {
  echo "Starting VLESS Reality on :$PORT (XTLS-Vision)..."
  while true; do
    "$VLESS_BIN" run -c "$VLESS_CONFIG" >/dev/null 2>&1 || sleep 5
  done
}

# ===================== 主函数 =====================
main() {
  echo "Deploying VLESS + TCP + Reality (Single Node) + CF Named Tunnel"

  load_config
  [[ -z "${VLESS_UUID:-}" ]] && VLESS_UUID="$TUNNEL_UUID"

  get_xray
  gen_vless_config

  get_cloudflared
  start_cf_tunnel

  ip=$(curl -s https://api64.ipify.org || echo "127.0.0.1")
  gen_link "$ip"

  run_vless
}

main "$@"
