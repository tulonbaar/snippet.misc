# Let's Encrypt Certificate Automation with Certbot

This repository contains scripts for automating SSL/TLS certificate generation and renewal using Let's Encrypt and Cloudflare DNS challenge.

## Overview

The setup includes two main scripts:
- **setup-letsencrypt.sh** - Initial setup and configuration
- **letsencrypt-renewal.sh** - Certificate generation and renewal

## Prerequisites

- Root/sudo access
- Cloudflare account with API credentials
- Domain(s) configured in Cloudflare DNS
- Ubuntu/Debian-based Linux distribution

## Files Description

- `setup-letsencrypt.sh` - Setup script that installs dependencies and configures automation
- `letsencrypt-renewal.sh` - Main renewal script that generates/renews certificates
- `cloudflare.ini` - Cloudflare API credentials configuration
- `domains.conf` - List of domains to include in the certificate
- `cert/` - Directory where generated certificates are stored

## Setup Script (setup-letsencrypt.sh)

### Purpose
The setup script automates the initial installation and configuration of the certificate renewal system.

### What it does:
1. **Updates package list** and ensures the system is ready for installation
2. **Installs required packages**:
   - certbot - Let's Encrypt client
   - python3-certbot-dns-cloudflare - Cloudflare DNS plugin
   - openssl - Certificate inspection tools
   - cron - Task scheduler for automatic renewals
3. **Creates directory structure** for certificate storage (`cert/` directory)
4. **Sets proper file permissions**:
   - Makes renewal script executable (755)
   - Secures Cloudflare credentials (600)
   - Sets domain list as readable (644)
5. **Configures automatic renewal** by adding a cron job that runs every Sunday at 2 AM
6. **Creates log file** at `/var/log/letsencrypt-renewal.log`

### Usage:
```bash
# Run as root
sudo ./setup-letsencrypt.sh
```

### After running setup:
1. Edit `cloudflare.ini` with your actual Cloudflare API credentials
2. Edit `domains.conf` with your domain(s)
3. Update EMAIL and PRIMARY_DOMAIN in `letsencrypt-renewal.sh` if needed
4. Test the renewal script manually before relying on automatic execution

---

## Renewal Script (letsencrypt-renewal.sh)

### Purpose
The renewal script handles certificate generation and renewal using Cloudflare DNS challenge method.

### Features:
- **Smart renewal** - Only renews when certificate expires within 30 days
- **Force renewal option** - Allows manual renewal regardless of expiry date
- **Automatic cleanup** - Removes old certificate directories before renewal
- **Multiple output formats** - Generates certificates in various formats for different services
- **Detailed logging** - Color-coded output with timestamps

### What it does:
1. **Validates prerequisites**:
   - Checks for root privileges
   - Verifies required files exist (domains.conf, cloudflare.ini)
   - Installs missing packages if needed

2. **Certificate validity check** (unless force mode):
   - Examines existing certificate expiry date
   - Calculates days remaining until expiration
   - Skips renewal if more than 30 days remain

3. **Certificate generation**:
   - Reads domain list from `domains.conf`
   - Uses Cloudflare DNS-01 challenge for validation
   - Supports wildcard certificates
   - Handles multiple domains and subdomains

4. **Cleanup operations** (in force mode or when needed):
   - Removes old certificate directories from `/etc/letsencrypt/live/`
   - Cleans archive directories from `/etc/letsencrypt/archive/`
   - Removes old renewal configuration files

5. **Certificate deployment**:
   - Copies certificates to `cert/` directory
   - Creates combined certificate file (`haproxy.pem`) for HAProxy and similar services
   - Sets secure permissions (600) on all certificate files

### Generated Certificate Files:
- `cert.pem` - Server certificate only
- `chain.pem` - Intermediate certificates
- `fullchain.pem` - Server certificate + intermediate chain
- `privkey.pem` - Private key
- `haproxy.pem` - Combined fullchain + private key (for HAProxy)

### Usage:

**Normal mode** (checks expiry, renews if needed):
```bash
sudo ./letsencrypt-renewal.sh
```

**Force renewal mode** (renews regardless of expiry):
```bash
sudo ./letsencrypt-renewal.sh --force
# or
sudo ./letsencrypt-renewal.sh -f
```

**Show help**:
```bash
./letsencrypt-renewal.sh --help
```

### Configuration Options:

Edit the following variables in the script header:
- `EMAIL` - Email address for Let's Encrypt notifications
- `PRIMARY_DOMAIN` - Main domain name (used for certificate storage)
- `RENEWAL_THRESHOLD` - Days before expiry to trigger renewal (default: 30)

### Automatic Execution:

After running the setup script, certificates are automatically renewed via cron:
- **Schedule**: Every Sunday at 2:00 AM
- **Log location**: `/var/log/letsencrypt-renewal.log`

To view renewal logs:
```bash
tail -f /var/log/letsencrypt-renewal.log
```

---

## Configuration

### Cloudflare API Credentials (cloudflare.ini)

You can use either **Global API Key** (legacy) or **API Token** (recommended):

**Option 1: Global API Key**
```ini
dns_cloudflare_email = your-email@example.com
dns_cloudflare_api_key = your-global-api-key
```

**Option 2: API Token (Recommended)**
```ini
dns_cloudflare_api_token = your-api-token
```

To create an API Token:
1. Go to https://dash.cloudflare.com/profile/api-tokens
2. Create Token with permissions:
   - Zone → DNS → Edit
   - Zone → Zone → Read
3. Select specific zones or all zones

### Domain Configuration (domains.conf)

List each domain on a separate line. Supports:
- Root domains: `example.com`
- Wildcard domains: `*.example.com`
- Subdomains: `sub.example.com`

Example:
```
example.com
*.example.com
subdomain.example.com
*.subdomain.example.com
```

**Note**: All domains must be managed by Cloudflare for DNS challenge to work.

---

## Troubleshooting

### Permission Errors
Ensure proper file permissions:
```bash
chmod 600 cloudflare.ini
chmod 644 domains.conf
chmod +x setup-letsencrypt.sh letsencrypt-renewal.sh
```

### Certificate Not Renewing
- Check if cron service is running: `systemctl status cron`
- Verify cron job exists: `crontab -l`
- Check logs: `cat /var/log/letsencrypt-renewal.log`

### DNS Challenge Failures
- Verify Cloudflare API credentials are correct
- Ensure domains are active in Cloudflare
- Check API token has correct permissions
- Wait a few minutes for DNS propagation

### Force Renewal When Needed
If you need to regenerate certificates immediately:
```bash
sudo ./letsencrypt-renewal.sh --force
```

---

## Security Notes

1. **Protect credentials**: The `cloudflare.ini` file contains sensitive API credentials. Never commit it to public repositories.
2. **File permissions**: Keep certificate files with 600 permissions (owner read/write only).
3. **API Token over API Key**: Use Cloudflare API Token instead of Global API Key when possible for better security.
4. **Regular updates**: Keep certbot and plugins updated for security patches.

---

## License

This script collection is provided as-is for automating Let's Encrypt certificate management.
