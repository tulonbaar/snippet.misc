#!/bin/bash

# Setup script for Let's Encrypt certificate automation

set -e

# Get script directory to work with relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root"
fi

log "Setting up Let's Encrypt certificate automation..."

# Update package list
log "Updating package list..."
apt-get update

# Install required packages
log "Installing required packages..."
apt-get install -y \
    certbot \
    python3-certbot-dns-cloudflare \
    openssl \
    cron

# Create cert directory
log "Creating certificate output directory..."
mkdir -p "$SCRIPT_DIR/cert"

# Set permissions on configuration files
log "Setting proper permissions..."
chmod +x "$SCRIPT_DIR/letsencrypt-renewal.sh"
chmod 600 "$SCRIPT_DIR/cloudflare.ini"
chmod 644 "$SCRIPT_DIR/domains.conf"

# Create cron job for automatic renewal
log "Setting up automatic renewal cron job..."
CRON_JOB="0 2 * * 0 $SCRIPT_DIR/letsencrypt-renewal.sh >> /var/log/letsencrypt-renewal.log 2>&1"

# Check if cron job already exists
if ! crontab -l 2>/dev/null | grep -q "$SCRIPT_DIR/letsencrypt-renewal.sh"; then
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    log "Cron job added: Certificate renewal will run every Sunday at 2 AM"
else
    log "Cron job already exists"
fi

# Create log file
touch /var/log/letsencrypt-renewal.log
chmod 644 /var/log/letsencrypt-renewal.log

log "Setup completed successfully!"
echo
warn "IMPORTANT: Before running the renewal script, you need to:"
echo "1. Edit $SCRIPT_DIR/cloudflare.ini with your Cloudflare API credentials"
echo "2. Edit $SCRIPT_DIR/domains.conf with your actual domains"
echo "3. Update the PRIMARY_DOMAIN and EMAIL in $SCRIPT_DIR/letsencrypt-renewal.sh if needed"
echo
log "To test the setup, run: $SCRIPT_DIR/letsencrypt-renewal.sh"
log "Logs will be written to: /var/log/letsencrypt-renewal.log"