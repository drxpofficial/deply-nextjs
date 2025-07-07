#!/bin/bash

set -e

echo "============================================"
echo "Next.js Production Deployment Script"
echo "============================================"

if [[ ! -f "/tmp/nextjs_deploy_first_run_complete" ]]; then
  clear
  echo "============================================"
  echo "First-time setup detected..."
  echo "============================================"
  
  echo "Updating system packages..."
  sudo apt update && sudo apt upgrade -y
  
  echo "Installing essential system packages..."
  sudo apt install -y curl wget git unzip software-properties-common apt-transport-https ca-certificates gnupg lsb-release
  
  echo "Setting up system for deployment..."
  sudo systemctl enable ufw
  
  echo "Creating first run marker..."
  touch /tmp/nextjs_deploy_first_run_complete
  
  echo "First-time setup complete!"
  echo "============================================"
fi

echo "Choose action: [1] Deploy, [2] Uninstall"
read -p "Enter your choice (1 or 2): " ACTION

if [[ "$ACTION" == "2" ]]; then
  echo "============================================"
  echo "Uninstalling Next.js Application"
  echo "============================================"
  
  echo "Enter the domain name to uninstall (e.g. example.com)"
  read -p "Domain: " DOMAIN
  
  echo "Stopping PM2 process..."
  pm2 stop nextjs-app 2>/dev/null || true
  pm2 delete nextjs-app 2>/dev/null || true
  
  echo "Removing Nginx configuration..."
  if [[ -n "$DOMAIN" ]]; then
    sudo rm -f "/etc/nginx/sites-enabled/$DOMAIN"
    sudo rm -f "/etc/nginx/sites-available/$DOMAIN"
    sudo nginx -t && sudo systemctl reload nginx
  fi
  
  echo "Removing SSL certificates..."
  if [[ -n "$DOMAIN" ]]; then
    sudo certbot delete --cert-name "$DOMAIN" --non-interactive 2>/dev/null || true
  fi
  
  echo "Removing application directory..."
  cd ..
  rm -rf next-app 2>/dev/null || true
  
  echo "Uninstall complete!"
  exit 0
fi

echo "Enter your domain name (e.g. example.com)"
read -p "Domain: " DOMAIN
echo "Choose project source:"
echo "[1] GitHub Repo"
echo "[2] Local Folder" 
echo "[3] New Next.js App"
read -p "Enter your choice (1, 2, or 3): " SOURCE

if [[ "$SOURCE" == "1" ]]; then
  echo "Enter your GitHub repository URL"
  read -p "Repo URL: " REPO_URL
  git clone "$REPO_URL"
  APP_DIR=$(basename "$REPO_URL" .git)
  cd "$APP_DIR"
elif [[ "$SOURCE" == "2" ]]; then
  echo "Enter the full path to your local project folder"
  read -p "Local path: " LOCAL_PATH
  APP_DIR="next-app"
  mkdir "$APP_DIR"
  cp -r "$LOCAL_PATH"/* "$APP_DIR"/
  cd "$APP_DIR"
elif [[ "$SOURCE" == "3" ]]; then
  echo "Enter a name for your new Next.js project"
  read -p "Project name: " APP_DIR
  npx create-next-app@latest "$APP_DIR" --typescript --eslint --tailwind --app --src-dir --import-alias "@/*"
  cd "$APP_DIR"
else
  echo "Invalid source choice. Exiting."
  exit 1
fi

echo "Installing system dependencies..."
sudo apt update
sudo apt install -y nginx curl git ufw

if ! command -v node &> /dev/null; then
  echo "Installing Node.js..."
  curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
  sudo apt install -y nodejs
  echo "Node.js installed successfully"
else
  echo "Node.js already installed"
fi

if ! command -v pm2 &> /dev/null; then
  echo "Installing PM2..."
  sudo npm install -g pm2
  echo "PM2 installed successfully"
else
  echo "PM2 already installed"
fi

echo "Installing app dependencies..."
npm install
echo "Dependencies installed"

echo "Building the application..."
if npm run build; then
  echo "Build completed successfully"
else
  echo "Build failed. Please check the errors above and try again."
  exit 1
fi

echo "Starting app with PM2..."
if pm2 start npm --name "nextjs-app" -- run start; then
  echo "PM2 process started successfully"
  pm2 save
  echo "PM2 configuration saved"
else
  echo "Failed to start PM2 process"
  exit 1
fi

echo "Setting up PM2 startup script..."
pm2 startup
sudo env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u root --hp /root
echo "PM2 startup script configured"

echo "Setting up Nginx reverse proxy..."
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
sudo bash -c "cat > $NGINX_CONF" <<EOL
server {
  listen 80;
  server_name $DOMAIN;

  location / {
    proxy_pass http://localhost:3000;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_cache_bypass \$http_upgrade;
  }
}
EOL

sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
if sudo nginx -t && sudo systemctl reload nginx; then
  echo "Nginx configuration applied successfully"
else
  echo "Nginx configuration failed"
  exit 1
fi

echo "Setting up HTTPS with Certbot..."
sudo apt install -y certbot python3-certbot-nginx
if sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m admin@$DOMAIN; then
  echo "SSL certificate installed successfully"
else
  echo "SSL certificate installation failed"
  exit 1
fi

echo "Configuring UFW firewall..."
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw --force enable
echo "Firewall configured successfully"

echo "Creating .env.production file..."
cat > .env.production <<EOL
NODE_ENV=production
NEXT_PUBLIC_API_URL=https://api.$DOMAIN
EOL

echo "Testing deployment..."
sleep 5
if curl -s -o /dev/null -w "%{http_code}" https://$DOMAIN | grep -q "200\|301\|302"; then
  echo "Deployment test successful!"
else
  echo "Deployment test failed. Please check manually."
fi

echo ""
echo "Deployment complete!"
echo "============================================"
echo "Your Next.js app is now live at: https://$DOMAIN"
echo "============================================"
echo ""
echo "Management Commands:"
echo "  pm2 status          - Check app status"
echo "  pm2 logs nextjs-app - View app logs"
echo "  pm2 restart nextjs-app - Restart the app"
echo "  pm2 monit           - Monitor resources"
echo ""
echo "🔧 Troubleshooting:"
echo "  If the site doesn't load, wait a few minutes for DNS propagation"
echo "  Check logs: pm2 logs nextjs-app"
echo "  Check Nginx: sudo nginx -t"
echo ""
echo "Your deployment is ready!"
