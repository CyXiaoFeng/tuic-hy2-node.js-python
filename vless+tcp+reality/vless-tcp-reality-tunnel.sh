#!/bin/bash
# ============================================================
# 纯 VLESS + TCP + Reality（XTLS Vision）+ 固定 Cloudflare Tunnel
# 翼龙面板 / 无 Root 环境可直接运行
# 隧道域名固定：wbtunnel.wai2mini.dpdns.org
# ============================================================
set -uo pipefail

# ===================== 固定 Tunnel 常量 =====================
TUNNEL_PORT=6868
TUNNEL_UUID="74a91aaf-b506-40e8-9949-361480d38037"
TUNNEL_TOKEN="eyJhIjoiOTFmMzMxNTllZTgwMTI4ZDY1MGZlNTZkMTc3MWVhNzciLCJ0IjoiZjA1YmNhODQtNTM2Ni00ZmViLWI1NzYtZTc1NzEyMTg0ODZmIiwicyI6Ik4ySmxNR1UyWWpBdE1XWmhNUzAwWVdabExUbGxNemt0TUdKaU16UmhaamRrWldFeiJ9"
TUNNEL_DOMAIN="wbtunnel.wai2mini.dpdns.org"

# Reality 伪装域
MASQ_DOMAIN="www.bing.com"

# 文件名定义
XRAY_BIN="./xray"
XRAY_CONFIG="vless-reality.json"
CF_BIN="./cloudflared"

# ------------------- 自动检测端口（翼龙） -------------------
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

# ===================== 下载 Xray =====================
get_xray() {
  if [[ ! -x "$XRAY_BIN" ]]; then
    echo "[XRAY] Downloading..."
    curl -L -o xray.zip "https://github.com/XTLS/Xray-core/releases/download/v1.8.23/Xray-linux-64.zip"
    unzip -j xray.zip xray -d . >/dev/null 2>&1
    rm -f xray.zip
    chmod +x "$XRAY_BIN"
  fi
}

# ===================== 下载 Cloudflared =====================
get_cloudflared() {
  if [[ ! -x "$CF_BIN" ]]; then
    echo "[CF] Downloading cloudflared..."
    curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" -o "$CF_BIN"
    chmod +x "$CF_BIN"
  fi
}

# ===================== 启动 Cloudflare 命名 Tunnel =====================
start_cf_tunnel() {
  echo "[CF] Starting Cloudflare Tunnel (固定域名: $TUNNEL_DOMAIN)..."

  # 直接运行固定隧道（Cloudflare 已在后台配置端口）
  nohup "$CF_BIN" tunnel --no-autoupdate run --token "$TUNNEL_TOKEN" > cf.log 2>&1 &

  echo "[CF] Cloudflared 已后台运行"
}

# ===================== 生成 Reality 配置 =====================
gen_vless_config() {
  echo "[XRAY] Generating VLESS Reality config..."

  local shortId
  shortId=$(openssl rand -hex 8)

  local keys priv pub
  keys=$("$XRAY_BIN" x25519)
  priv=$(echo "$keys" | grep "Private" | awk '{print $3}')
  pub=$(echo "$keys"  | grep "Public"  | awk '{print $3}')

  cat > "$XRAY_CONFIG" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": $PORT,
    "protocol": "vless",
    "settings": {
      "clients": [
        { "id": "$TUNNEL_UUID", "flow": "xtls-rprx-vision" }
      ],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "$MASQ_DOMAIN:443",
        "xver": 0,
        "serverNames": ["$MASQ_DOMAIN"],
        "privateKey": "$priv",
        "publicKey": "$pub",
        "shortIds": ["$shortId"],
        "fingerprint": "chrome",
        "spiderX": "/"
      }
    }
  }],
  "outbounds": [
    { "protocol": "freedom" }
  ]
}
EOF

  # 保存 Reality 参数
  echo "$pub"  > reality_pub.txt
  echo "$shortId" > reality_sid.txt
}

# ===================== 输出客户端节点 =====================
print_link() {

  local pub sid
  pub=$(cat reality_pub.txt)
  sid=$(cat reality_sid.txt)

  echo "================================================="
  echo " 固定 Cloudflare Tunnel 入口节点"
  echo "================================================="

  echo "
vless://$TUNNEL_UUID@$TUNNEL_DOMAIN:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$MASQ_DOMAIN&fp=chrome&pbk=$pub&sid=$sid&type=tcp&spx=/#CF-Reality
" | sed 's/ //g'

  echo "================================================="
}

# ===================== 启动 Xray =====================
run_xray() {
  echo "[XRAY] Starting Xray Reality on $PORT ..."

  while true; do
    "$XRAY_BIN" run -c "$XRAY_CONFIG" >/dev/null 2>&1 || sleep 5
  done
}

# ===================== 主流程 =====================
main() {
  echo "============== 启动 Reality + CF 隧道 =============="

  get_xray
  get_cloudflared

  gen_vless_config
  start_cf_tunnel
  print_link

  run_xray
}

main "$@"
