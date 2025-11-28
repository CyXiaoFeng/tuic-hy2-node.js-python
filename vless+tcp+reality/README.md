此部署方案仅供参考！

# Vless+tcp+reality一键脚本+cf隧道极简部署

* 更新自适应端口，无需再手动设置

```
curl -Ls https://raw.githubusercontent.com/cyxiaofeng/tuic-hy2-node.js-python/main/vless+tcp+reality/vless+tcp+reality.sh | sed 's/\r$//' | bash

```
```
curl -Ls https://raw.githubusercontent.com/cyxiaofeng/tuic-hy2-node.js-python/main/vless+tcp+reality/vless-tcp-reality-tunnel.sh | sed 's/\r$//' | bash

```
## CF隧道所有支持的环境变量说明：

| 环境变量 | 说明 | 示例值 | 默认值 |
|---------|------|--------|--------|
| `REALITY_PORT` | Reality 直连端口 | `8443` | `3250` |
| `TUNNEL_PORT` | CF Tunnel 本地监听端口 | `6868` | `6868` |
| `TUNNEL_UUID` | CF Tunnel 客户端 UUID | `74a91aaf-...` | 自动生成 |
| `TUNNEL_TOKEN` | CF Tunnel Token（**必需**） | `eyJhIjoiOTFm...` | - |
| `TUNNEL_DOMAIN` | CF Tunnel 域名（**必需**） | `wbtunnel.example.com` | - |

## 端口说明：

- **REALITY_PORT**：外部访问的 Reality 端口（直连用）
- **TUNNEL_PORT**：Xray 本地监听端口（给 cloudflared 转发用，不对外暴露）
```
curl -Ls https://raw.githubusercontent.com/cyxiaofeng/tuic-hy2-node.js-python/main/vless+tcp+reality/vless-tcp-reality-tunnel.sh | sed 's/\r$//' | TUNNEL_TOKEN="真实TOKEN" TUNNEL_DOMAIN="真实隧道的域名" bash

```
