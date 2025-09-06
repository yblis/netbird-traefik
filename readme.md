# NetBird avec Traefik

Déploiement simplifié de NetBird avec des labels Traefik pour une intégration facile dans votre stack existante.

## 🎯 Prérequis

- Docker et Docker Compose installés
- Stack Traefik déjà configurée et fonctionnelle
- Nom de domaine pointant vers votre serveur
- Ports nécessaires disponibles (voir section [Ports](#ports))

## 🚀 Installation rapide

### 1. Cloner le repository
```bash
git clone https://github.com/yblis/netbird-traefik.git
cd netbird-traefik
```

### 2. Configuration
Éditez le script `install-netbird-traefik.sh` et modifiez les variables suivantes :

```bash
NETBIRD_DOMAIN="netbird.votre-domaine.fr"    # your NetBird domain
TRAEFIK_NETWORK="traefik_traefik"            # your Traefik network
TRAEFIK_CERTRESOLVER="webssl"                # your Traefik's certresolver
```

### 3. Exécution
```bash
chmod +x install-netbird-traefik.sh
./install-netbird-traefik.sh
```

## 🔧 Configuration des ports

Assurez-vous que les ports suivants sont ouverts sur votre serveur :

### TCP
| Port | Service | Description |
|------|---------|-------------|
| 80 | Traefik | HTTP (redirect to HTTPS) |
| 443 | Traefik | HTTPS |
| 10000 | NetBird | Signal gRPC API |
| 33073 | NetBird | Management gRPC API |
| 33080 | NetBird | Relay service |

### UDP
| Port | Service | Description |
|------|---------|-------------|
| 3478 | Coturn | STUN/TURN |
| 49152-65535 | Coturn | Dynamic STUN/TURN range |

### Example iptables configuration
```bash
# TCP
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p tcp --dport 10000 -j ACCEPT
iptables -A INPUT -p tcp --dport 33073 -j ACCEPT
iptables -A INPUT -p tcp --dport 33080 -j ACCEPT

# UDP
iptables -A INPUT -p udp --dport 3478 -j ACCEPT
iptables -A INPUT -p udp --dport 49152:65535 -j ACCEPT
```

## 📁 Project Structure

```
netbird-traefik/
├── install-netbird-traefik.sh    # Installation script
├── docker-compose.yml            # Docker Compose config with Traefik labels
├── README.md                     # This documentation
└── configs/                     # Configuration files
```

## ⚙️ Features

- ✅ Automatic Traefik integration
- ✅ Automatic SSL certificates (Let's Encrypt)
- ✅ Optimized network configuration
- ✅ Pre-configured Traefik labels
- ✅ Automatic NetBird services management

## 🔍 Installation Verification

After installation, verify that services are running:

```bash
docker-compose ps
```

Access your NetBird interface at: `https://netbird.your-domain.com`

## 🆘 Support

If you encounter issues:

1. Check logs: `docker-compose logs -f`
2. Ensure your Traefik network exists: `docker network ls`
3. Verify DNS resolution for your domain

## 📝 Important Notes

- This script is designed for installations with Traefik already configured
- SSL certificates are automatically managed by Traefik
- Make sure your domain points to your server before installation

---

**Contributing:** Contributions are welcome! Feel free to open an issue or pull request.
