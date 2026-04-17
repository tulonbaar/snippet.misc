#!/bin/bash

# Let's Encrypt Certificate Renewal Script with DNS Challenge
# This script uses certbot with Cloudflare DNS challenge to generate certificates

set -e  # Exit on any error

# Get script directory to work with relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
CERT_OUTPUT_DIR="$SCRIPT_DIR/cert"
DOMAINS_FILE="$SCRIPT_DIR/domains.conf"
CLOUDFLARE_CREDENTIALS="$SCRIPT_DIR/cloudflare.ini"
EMAIL="email@example.com"
PRIMARY_DOMAIN="example.com"
RENEWAL_THRESHOLD=30  # Days before expiry to renew

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# Function to display help
show_help() {
    echo "Let's Encrypt Certificate Renewal Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -f, --force     Force certificate renewal regardless of expiry date"
    echo "  -h, --help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Check expiry and renew if needed"
    echo "  $0 --force      # Force renewal regardless of expiry"
    echo "  $0 -f           # Same as --force"
}

# Parse command line arguments
FORCE_RENEWAL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE_RENEWAL=true
            log "Force renewal mode enabled"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1. Use -h for help."
            ;;
    esac
done

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root"
fi

# Function to clean old certificates
clean_letsencrypt_directory() {
    local letsencrypt_live_dir="/etc/letsencrypt/live"
    local letsencrypt_archive_dir="/etc/letsencrypt/archive"
    local letsencrypt_renewal_dir="/etc/letsencrypt/renewal"
    
    log "Cleaning Let's Encrypt directories..."
    
    # Only clean if we're forcing renewal or if there are multiple certificate directories
    if [ "$FORCE_RENEWAL" = true ] || [ $(find "$letsencrypt_live_dir" -maxdepth 1 -name "$PRIMARY_DOMAIN*" -type d 2>/dev/null | wc -l) -gt 1 ]; then
        
        log "Removing old certificate directories for domain: $PRIMARY_DOMAIN"
        
        # Remove live directories
        if [ -d "$letsencrypt_live_dir" ]; then
            find "$letsencrypt_live_dir" -maxdepth 1 -name "$PRIMARY_DOMAIN*" -type d -exec rm -rf {} \; 2>/dev/null || true
            log "Cleaned live certificate directories"
        fi
        
        # Remove archive directories
        if [ -d "$letsencrypt_archive_dir" ]; then
            find "$letsencrypt_archive_dir" -maxdepth 1 -name "$PRIMARY_DOMAIN*" -type d -exec rm -rf {} \; 2>/dev/null || true
            log "Cleaned archive certificate directories"
        fi
        
        # Remove renewal configuration files
        if [ -d "$letsencrypt_renewal_dir" ]; then
            find "$letsencrypt_renewal_dir" -maxdepth 1 -name "$PRIMARY_DOMAIN*.conf" -type f -exec rm -f {} \; 2>/dev/null || true
            log "Cleaned renewal configuration files"
        fi
        
        log "Let's Encrypt directory cleanup completed"
    else
        log "Skipping directory cleanup (not in force mode and no duplicate directories found)"
    fi
}

# Create output directory if it doesn't exist
mkdir -p "$CERT_OUTPUT_DIR"

# Check if required files exist
if [ ! -f "$DOMAINS_FILE" ]; then
    error "Domains file not found: $DOMAINS_FILE"
fi

if [ ! -f "$CLOUDFLARE_CREDENTIALS" ]; then
    error "Cloudflare credentials file not found: $CLOUDFLARE_CREDENTIALS"
fi

# Install required packages if not present
log "Checking and installing required packages..."
if ! command -v certbot &> /dev/null; then
    log "Installing certbot..."
    apt-get update
    apt-get install -y certbot python3-certbot-dns-cloudflare
fi

if ! command -v openssl &> /dev/null; then
    log "Installing openssl..."
    apt-get install -y openssl
fi

# Function to check certificate validity
check_certificate() {
    local cert_path="$1"
    
    if [ ! -f "$cert_path" ]; then
        log "No existing certificate found at $cert_path"
        return 1
    fi
    
    log "Checking existing certificate validity..."
    
    # Get expiry date and calculate days remaining
    local expiry_date=$(openssl x509 -enddate -noout -in "$cert_path" | cut -d= -f 2)
    local expiry_timestamp=$(date -d "$expiry_date" +%s)
    local current_timestamp=$(date +%s)
    local days_left=$(( (expiry_timestamp - current_timestamp) / 86400 ))
    
    log "Certificate has $days_left days remaining"
    
    if [ "$days_left" -gt "$RENEWAL_THRESHOLD" ]; then
        log "Certificate still valid for more than $RENEWAL_THRESHOLD days. Skipping renewal."
        return 0
    else
        log "Certificate expires in $days_left days. Renewal needed."
        return 1
    fi
}

# Function to generate certificate
generate_certificate() {
    log "Starting certificate generation/renewal..."
    
    # Read domains from file and prepare domain arguments
    local domains=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
            domains="$domains -d $line"
        fi
    done < "$DOMAINS_FILE"
    
    if [ -z "$domains" ]; then
        error "No domains found in $DOMAINS_FILE"
    fi
    
    log "Using domains:$domains"
    
    # Prepare certbot command with optional force renewal
    local certbot_args="certonly --dns-cloudflare --dns-cloudflare-credentials $CLOUDFLARE_CREDENTIALS --non-interactive --agree-tos --email $EMAIL --expand"
    
    # Add force renewal flag if needed
    if [ "$FORCE_RENEWAL" = true ]; then
        certbot_args="$certbot_args --force-renewal"
        log "Adding --force-renewal flag to certbot command"
    fi
    
    # Run certbot
    certbot $certbot_args $domains
    
    if [ $? -eq 0 ]; then
        log "Certificate generation successful"
        return 0
    else
        error "Certificate generation failed"
    fi
}

# Function to copy certificates to output directory
copy_certificates() {
    local letsencrypt_live_dir="/etc/letsencrypt/live/$PRIMARY_DOMAIN"
    
    if [ ! -d "$letsencrypt_live_dir" ]; then
        error "Certificate directory not found: $letsencrypt_live_dir"
    fi
    
    log "Copying certificates to $CERT_OUTPUT_DIR..."
    
    # Copy individual certificate files
    cp "$letsencrypt_live_dir/cert.pem" "$CERT_OUTPUT_DIR/"
    cp "$letsencrypt_live_dir/chain.pem" "$CERT_OUTPUT_DIR/"
    cp "$letsencrypt_live_dir/fullchain.pem" "$CERT_OUTPUT_DIR/"
    cp "$letsencrypt_live_dir/privkey.pem" "$CERT_OUTPUT_DIR/"
    
    # Create combined certificate for HAProxy/other services
    cat "$letsencrypt_live_dir/fullchain.pem" "$letsencrypt_live_dir/privkey.pem" > "$CERT_OUTPUT_DIR/haproxy.pem"
    
    # Set appropriate permissions
    chmod 600 "$CERT_OUTPUT_DIR"/*.pem
    
    log "Certificates copied successfully to $CERT_OUTPUT_DIR"
    
    # List copied files
    log "Available certificate files:"
    ls -la "$CERT_OUTPUT_DIR"/*.pem
}

# Main execution
log "Starting Let's Encrypt certificate renewal process..."

# Check if certificate needs renewal
CERT_PATH="$CERT_OUTPUT_DIR/fullchain.pem"
NEEDS_RENEWAL=true

if [ "$FORCE_RENEWAL" = true ]; then
    log "Force renewal mode: Skipping certificate validity check"
    warn "Certificate will be renewed regardless of expiry date"
    NEEDS_RENEWAL=true
else
    if check_certificate "$CERT_PATH"; then
        NEEDS_RENEWAL=false
    fi
fi

# Generate certificate if needed
if [ "$NEEDS_RENEWAL" = true ]; then
    if [ "$FORCE_RENEWAL" = true ]; then
        log "Forcing certificate renewal..."
    else
        log "Certificate needs renewal based on expiry date..."
    fi
    
    # Clean old certificates before generating new ones
    clean_letsencrypt_directory
    
    generate_certificate
    copy_certificates
    log "Certificate renewal process completed successfully"
else
    log "Certificate is still valid. No renewal needed."
    log "Use --force or -f to force renewal regardless of expiry date"
fi

log "Script execution completed"