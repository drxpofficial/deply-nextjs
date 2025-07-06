# Next.js Production Deployment Script

Automated deployment script for Next.js applications with SSL, Nginx, PM2, and firewall configuration.

## Quick Start

```bash
# Download and run directly
curl -fsSL https://raw.githubusercontent.com/drxpofficial/deply-nextjs/main/deploy-nextjs.sh | bash
```

## What it does

- **One-command deployment** from GitHub, local folder, or new Next.js app
- **Automatic SSL** setup with Let's Encrypt
- **Nginx reverse proxy** configuration
- **PM2 process management** with auto-startup
- **UFW firewall** setup
- **Clean deployment** with automatic cleanup

## Usage

1. Run the script
2. Choose deploy/uninstall
3. Enter your domain
4. Select project source (GitHub/Local/New)
5. Wait for deployment

## Prerequisites

- Ubuntu/Debian server
- Domain pointing to server
- SSH with sudo access

## Management

```bash
pm2 status          # Check app status
pm2 logs nextjs-app # View logs
pm2 restart nextjs-app # Restart app
```

## Uninstall

```bash
./deploy-nextjs.sh
# Choose [2] Uninstall
``` 
