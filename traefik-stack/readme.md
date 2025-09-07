# Traefik Reverse Proxy Setup

A simple Docker Compose setup for Traefik reverse proxy with automatic HTTPS certificates.

## Quick Start

1. **Clone and configure**
   ```bash
   git clone https://github.com/yblis/netbird-traefik
   cd netbird-traefil/traefik-setup
   ```

2. **Edit configuration files**
   - In `docker-compose.yml`: Replace `traefik.domain.com` with your domain
   - In `data/traefik.toml`: Replace `admin@domain.com` with your email
   - In `docker-compose.yml`: Replace `YOURHASHBASICPASSWORD` with your hashed password

3. **Set up DNS**
   - Create an A record pointing your domain to your server IP
   - Example: `traefik.yourdomain.com` → `your.server.ip`

4. **Create required files**
   ```bash
   mkdir -p data
   touch data/acme.json
   chmod 600 data/acme.json
   ```

5. **Start Traefik**
   ```bash
   docker-compose up -d
   ```

## Configuration Details

### Domain Setup
Replace these values in the configuration files:
- `traefik.domain.com` → Your actual domain
- `admin@domain.com` → Your email for Let's Encrypt
- `YOURHASHBASICPASSWORD` → Your hashed password (see below)

### Generate Password Hash
```bash
echo $(htpasswd -nb admin yourpassword) | sed -e s/\\$/\\$\\$/g
```

### Access Points
- **Traefik Dashboard**: `https://traefik.yourdomain.com`
- **HTTP**: Port 80 (redirects to HTTPS)
- **HTTPS**: Port 443
- **Dashboard Direct**: Port 8001 (HTTP only)

## Features

- ✅ Automatic HTTPS with Let's Encrypt
- ✅ HTTP to HTTPS redirection
- ✅ Basic authentication for dashboard
- ✅ Docker integration
- ✅ File-based service configuration

## File Structure

```
.
├── docker-compose.yml
└── data/
    ├── traefik.toml
    ├── services.toml
    └── acme.json
```

## Adding Services

To add a new service behind Traefik, add these labels to your service in docker-compose:

```yaml
labels:
  - "traefik.http.routers.myapp.rule=Host(`myapp.yourdomain.com`)"
  - "traefik.http.routers.myapp.entrypoints=https"
  - "traefik.http.routers.myapp.tls.certresolver=webssl"
  - "traefik.http.services.myapp.loadbalancer.server.port=80"
```

## Troubleshooting

- Check logs: `docker-compose logs traefik`
- Verify DNS resolution: `nslookup traefik.yourdomain.com`
- Ensure ports 80 and 443 are open
- Check acme.json permissions: `ls -la data/acme.json` (should be 600)
