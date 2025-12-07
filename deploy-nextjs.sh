#!/bin/bash

# ============================================
# Deployment Script v2.0
# ============================================

set -e
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

print_header() {
    echo -e "${CYAN}${BOLD}============================================${NC}"
    echo -e "${CYAN}${BOLD}$1${NC}"
    echo -e "${CYAN}${BOLD}============================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_step() {
    echo -e "${MAGENTA}→${NC} $1"
}

show_progress() {
    local pid=$1
    local message=$2
    local spin='-\|/'
    local i=0
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r${BLUE}${spin:$i:1}${NC} $message"
        sleep 0.1
    done
    printf "\r"
}

validate_domain() {
    local domain=$1
    if [[ ! $domain =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid domain name format"
        return 1
    fi
    return 0
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

first_time_setup() {
    if [[ ! -f "/tmp/drxps_first_run_complete" ]]; then
        clear
        print_header "First-time Setup"
        
        print_step "Updating system packages..."
        sudo apt update && sudo apt upgrade -y
        
        print_step "Installing essential system packages..."
        sudo apt install -y curl wget git unzip software-properties-common \
            apt-transport-https ca-certificates gnupg lsb-release
        
        print_step "Setting up system services..."
        sudo systemctl enable nginx 2>/dev/null || true
        sudo systemctl enable ufw 2>/dev/null || true
        
        touch /tmp/drxps_first_run_complete
        print_success "First-time setup complete!"
        echo ""
    fi
}

show_menu() {
    clear
    print_header "Next.js Deployment Manager"
    echo -e "${BOLD}Choose an action:${NC}"
    echo ""
    echo -e "  ${GREEN}[1]${NC} Deploy New Application"
    echo -e "  ${GREEN}[2]${NC} Update Existing Application"
    echo -e "  ${GREEN}[3]${NC} Check Application Status"
    echo -e "  ${GREEN}[4]${NC} View Application Logs"
    echo -e "  ${GREEN}[5]${NC} Restart Application"
    echo -e "  ${GREEN}[6]${NC} Uninstall Application"
    echo -e "  ${RED}[0]${NC} Exit"
    echo ""
    read -p "$(echo -e ${CYAN}Enter choice [0-6]:${NC} ) " ACTION
}

get_pm2_name() {
    local domain=$1
    echo "nextjs-$(echo $domain | tr '.' '-')"
}

deploy_app() {
    print_header "Deploying Next.js Application"
    
    read -p "$(echo -e ${CYAN}Enter domain name (e.g. example.com):${NC} ) " DOMAIN
    
    if ! validate_domain "$DOMAIN"; then
        exit 1
    fi
    
    PM2_NAME=$(get_pm2_name "$DOMAIN")
    
    read -p "$(echo -e ${CYAN}Choose project source:${NC} [1] GitHub Repo, [2] Local Folder, [3] New Next.js App: ) " SOURCE
    
    case $SOURCE in
        1)
            read -p "$(echo -e ${CYAN}GitHub repo URL:${NC} ) " REPO_URL
            print_step "Cloning repository..."
            git clone "$REPO_URL" || {
                print_error "Failed to clone repository"
                exit 1
            }
            APP_DIR=$(basename "$REPO_URL" .git)
            cd "$APP_DIR"
            ;;
        2)
            read -p "$(echo -e ${CYAN}Full path to your local project folder:${NC} ) " LOCAL_PATH
            if [[ ! -d "$LOCAL_PATH" ]]; then
                print_error "Directory not found: $LOCAL_PATH"
                exit 1
            fi
            APP_DIR="next-app-$(date +%s)"
            mkdir -p "$APP_DIR"
            cp -r "$LOCAL_PATH"/* "$APP_DIR"/ 2>/dev/null || cp -r "$LOCAL_PATH"/. "$APP_DIR"/ 2>/dev/null
            cd "$APP_DIR"
            ;;
        3)
            read -p "$(echo -e ${CYAN}New project name:${NC} ) " APP_DIR
            print_step "Creating new Next.js app..."
            npx create-next-app@latest "$APP_DIR" --typescript --eslint --tailwind --app --src-dir --import-alias "@/*" --yes
            cd "$APP_DIR"
            ;;
        *)
            print_error "Invalid source choice"
            exit 1
            ;;
    esac
    
    print_step "Checking system dependencies..."
    
    if ! command_exists node; then
        print_step "Installing Node.js..."
        curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
        sudo apt install -y nodejs
        print_success "Node.js installed: $(node --version)"
    else
        print_info "Node.js already installed: $(node --version)"
    fi
    
    if ! command_exists pm2; then
        print_step "Installing PM2..."
        sudo npm install -g pm2
        print_success "PM2 installed: $(pm2 --version)"
    else
        print_info "PM2 already installed: $(pm2 --version)"
    fi
    
    print_step "Installing application dependencies..."
    if npm install; then
        print_success "Dependencies installed"
    else
        print_error "Failed to install dependencies"
        exit 1
    fi
    
    print_step "Building application..."
    if npm run build; then
        print_success "Build completed successfully"
    else
        print_error "Build failed. Please check the errors above."
        exit 1
    fi
    
    if pm2 describe "$PM2_NAME" >/dev/null 2>&1; then
        print_warning "Stopping existing PM2 process..."
        pm2 stop "$PM2_NAME" 2>/dev/null || true
        pm2 delete "$PM2_NAME" 2>/dev/null || true
    fi
    
    print_step "Starting application with PM2..."
    if pm2 start npm --name "$PM2_NAME" -- run start; then
        pm2 save
        print_success "PM2 process started: $PM2_NAME"
    else
        print_error "Failed to start PM2 process"
        exit 1
    fi
    
    print_step "Configuring PM2 startup script..."
    pm2 startup systemd -u "$USER" --hp "$HOME" 2>/dev/null || true
    print_success "PM2 startup configured"
    
    print_step "Configuring Nginx reverse proxy..."
    NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
    
    if [[ -f "$NGINX_CONF" ]]; then
        print_warning "Nginx config already exists. Backing up..."
        sudo cp "$NGINX_CONF" "${NGINX_CONF}.backup.$(date +%s)"
    fi
    
    sudo bash -c "cat > $NGINX_CONF" <<EOL
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }
}
EOL
    
    sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
    
    if sudo nginx -t && sudo systemctl reload nginx; then
        print_success "Nginx configuration applied"
    else
        print_error "Nginx configuration failed"
        exit 1
    fi
    
    print_step "Setting up SSL certificate..."
    if ! command_exists certbot; then
        sudo apt install -y certbot python3-certbot-nginx
    fi
    
    read -p "$(echo -e ${CYAN}Enter email for SSL certificate (optional):${NC} ) " EMAIL
    EMAIL=${EMAIL:-admin@$DOMAIN}
    
    if sudo certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect; then
        print_success "SSL certificate installed"
    else
        print_warning "SSL certificate installation failed. You can set it up manually later."
    fi
    
    print_step "Configuring firewall..."
    sudo ufw allow OpenSSH 2>/dev/null || true
    sudo ufw allow 'Nginx Full' 2>/dev/null || true
    sudo ufw --force enable 2>/dev/null || true
    print_success "Firewall configured"
    
    if [[ ! -f .env.production ]]; then
        print_step "Creating .env.production file..."
        cat > .env.production <<EOL
NODE_ENV=production
NEXT_PUBLIC_API_URL=https://api.$DOMAIN
EOL
        print_success ".env.production created"
    fi
    
    print_step "Testing deployment..."
    sleep 5
    
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$DOMAIN" 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" =~ ^(200|301|302)$ ]]; then
        print_success "Deployment test successful! (HTTP $HTTP_CODE)"
    else
        print_warning "Deployment test returned HTTP $HTTP_CODE. Site may still be starting..."
    fi
    
    echo ""
    print_header "Deployment Complete!"
    echo -e "${GREEN}${BOLD}Your Next.js app is now live at:${NC} https://$DOMAIN"
    echo ""
    echo -e "${CYAN}${BOLD}Management Commands:${NC}"
    echo -e "  pm2 status $PM2_NAME          - Check app status"
    echo -e "  pm2 logs $PM2_NAME            - View app logs"
    echo -e "  pm2 restart $PM2_NAME         - Restart the app"
    echo -e "  pm2 monit                     - Monitor resources"
    echo ""
    echo -e "${YELLOW}${BOLD}Note:${NC} If the site doesn't load, wait a few minutes for DNS propagation"
    echo ""
}

update_app() {
    print_header "Update Application"
    
    read -p "$(echo -e ${CYAN}Enter domain name:${NC} ) " DOMAIN
    PM2_NAME=$(get_pm2_name "$DOMAIN")
    
    if ! pm2 describe "$PM2_NAME" >/dev/null 2>&1; then
        print_error "Application not found: $PM2_NAME"
        return 1
    fi
    
    print_step "Stopping application..."
    pm2 stop "$PM2_NAME"
    
    print_step "Pulling latest changes..."
    if [[ -d .git ]]; then
        git pull || print_warning "Git pull failed, continuing anyway..."
    else
        print_warning "Not a git repository, skipping pull"
    fi
    
    print_step "Installing dependencies..."
    npm install
    
    print_step "Building application..."
    npm run build
    
    print_step "Restarting application..."
    pm2 restart "$PM2_NAME"
    
    print_success "Application updated successfully!"
}

check_status() {
    print_header "Application Status"
    
    read -p "$(echo -e ${CYAN}Enter domain name (or press Enter for all):${NC} ) " DOMAIN
    
    if [[ -z "$DOMAIN" ]]; then
        pm2 list
    else
        PM2_NAME=$(get_pm2_name "$DOMAIN")
        pm2 describe "$PM2_NAME" || print_error "Application not found"
    fi
}

view_logs() {
    print_header "Application Logs"
    
    read -p "$(echo -e ${CYAN}Enter domain name:${NC} ) " DOMAIN
    PM2_NAME=$(get_pm2_name "$DOMAIN")
    
    if pm2 describe "$PM2_NAME" >/dev/null 2>&1; then
        pm2 logs "$PM2_NAME"
    else
        print_error "Application not found: $PM2_NAME"
    fi
}

restart_app() {
    print_header "Restart Application"
    
    read -p "$(echo -e ${CYAN}Enter domain name:${NC} ) " DOMAIN
    PM2_NAME=$(get_pm2_name "$DOMAIN")
    
    if pm2 restart "$PM2_NAME"; then
        print_success "Application restarted: $PM2_NAME"
    else
        print_error "Failed to restart application"
    fi
}

uninstall_app() {
    print_header "Uninstall Application"
    
    read -p "$(echo -e ${CYAN}Enter domain name:${NC} ) " DOMAIN
    
    if ! validate_domain "$DOMAIN"; then
        exit 1
    fi
    
    PM2_NAME=$(get_pm2_name "$DOMAIN")
    
    read -p "$(echo -e ${RED}Are you sure you want to uninstall $DOMAIN? [y/N]:${NC} ) " CONFIRM
    
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        print_info "Uninstall cancelled"
        return
    fi
    
    print_step "Stopping PM2 process..."
    pm2 stop "$PM2_NAME" 2>/dev/null || true
    pm2 delete "$PM2_NAME" 2>/dev/null || true
    
    print_step "Removing Nginx configuration..."
    sudo rm -f "/etc/nginx/sites-enabled/$DOMAIN"
    sudo rm -f "/etc/nginx/sites-available/$DOMAIN"
    sudo nginx -t && sudo systemctl reload nginx
    
    print_step "Removing SSL certificate..."
    sudo certbot delete --cert-name "$DOMAIN" --non-interactive 2>/dev/null || true
    
    print_step "Removing application directory..."
    if [[ -d "$APP_DIR" ]]; then
        read -p "$(echo -e ${YELLOW}Remove application directory? [y/N]:${NC} ) " REMOVE_DIR
        if [[ "$REMOVE_DIR" =~ ^[Yy]$ ]]; then
            cd ..
            rm -rf "$APP_DIR" 2>/dev/null || true
        fi
    fi
    
    print_success "Uninstall complete!"
}

main() {
    first_time_setup
    
    while true; do
        show_menu
        
        case $ACTION in
            1)
                deploy_app
                read -p "$(echo -e ${CYAN}Press Enter to continue...${NC} ) "
                ;;
            2)
                update_app
                read -p "$(echo -e ${CYAN}Press Enter to continue...${NC} ) "
                ;;
            3)
                check_status
                read -p "$(echo -e ${CYAN}Press Enter to continue...${NC} ) "
                ;;
            4)
                view_logs
                read -p "$(echo -e ${CYAN}Press Enter to continue...${NC} ) "
                ;;
            5)
                restart_app
                read -p "$(echo -e ${CYAN}Press Enter to continue...${NC} ) "
                ;;
            6)
                uninstall_app
                read -p "$(echo -e ${CYAN}Press Enter to continue...${NC} ) "
                ;;
            0)
                print_info "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid choice"
                sleep 2
                ;;
        esac
    done
}

main
