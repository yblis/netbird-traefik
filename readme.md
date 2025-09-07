# 🚀 Deploy Netbird & Zitadel with Traefik

This script helps you deploy **Netbird** behind a **Traefik** reverse proxy. It's designed for users who already have a working Traefik stack. The integration relies solely on Traefik labels—no need to modify your existing setup.

---

## 📦 Installation

```bash
git clone https://github.com/yblis/netbird-traefik.git
cd netbird-traefik
```

---

## ⚙️ Configuration

Before running the script, edit the following variables inside `install-netbird-traefik.sh`:

```bash
NETBIRD_DOMAIN="netbird.domain.com"       # Your Netbird domain
TRAEFIK_NETWORK="traefik_traefik"         # Docker network used by Traefik
TRAEFIK_CERTRESOLVER="webssl"             # Traefik certificate resolver (e.g., Let's Encrypt)
```

---

## ▶️ Deployment

```bash
chmod +x install-netbird-traefik.sh
./install-netbird-traefik.sh
```

---

## 🔓 Required Ports

Make sure the following ports are open on your firewall/router:

| Protocol | Port(s)         | Description                  |
|----------|----------------|------------------------------|
| TCP      | 80, 443        | Traefik (HTTP/HTTPS)         |
| TCP      | 10000          | Signal gRPC API              |
| TCP      | 33073          | Management gRPC API          |
| TCP      | 33080          | Relay service                |
| UDP      | 3478           | STUN/TURN (Coturn)           |
| UDP      | 49152–65535    | STUN/TURN (Coturn - RTP)     |

---

## 🧠 Requirements

- Existing Traefik stack (Docker + configured network)
- Valid domain pointing to your server
- Traefik certificate resolver (e.g., Let's Encrypt)

