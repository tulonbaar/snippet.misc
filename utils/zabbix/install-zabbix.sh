#!/bin/bash

################################################################################
# Zabbix Agent 2 Installation Script for Ubuntu
# Zabbix Version: 7.4 (latest release)
# Author: System
# Date: 2025-10-28
# Requirements: Ubuntu 20.04/22.04/24.04, root/sudo privileges
# Documentation: https://www.zabbix.com/download
################################################################################

set -e  # Exit script on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to display messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check root privileges
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        log_error "This script requires root privileges. Run with sudo or as root."
        exit 1
    fi
}

# Display help
show_help() {
    cat << EOF
Usage: $0 -s <SERVER_IP> -a <SERVER_ACTIVE_IP>

Parameters:
    -s, --server         Zabbix server IP address (required)
    -a, --active         Zabbix Active server IP address (required)
    -h, --help           Display this help

Example:
    $0 -s 192.168.1.10 -a 192.168.1.10
    $0 --server 10.0.0.5 --active 10.0.0.5

EOF
    exit 0
}

# Parse parameters
parse_args() {
    SERVER_IP=""
    SERVER_ACTIVE_IP=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--server)
                SERVER_IP="$2"
                shift 2
                ;;
            -a|--active)
                SERVER_ACTIVE_IP="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                ;;
            *)
                log_error "Unknown parameter: $1"
                show_help
                ;;
        esac
    done

    # Validate parameters
    if [ -z "$SERVER_IP" ] || [ -z "$SERVER_ACTIVE_IP" ]; then
        log_error "Parameters -s (server) and -a (active) are required!"
        show_help
    fi
}

# Display installation plan
show_installation_plan() {
    local server_ip="$1"
    local server_active_ip="$2"
    local hostname="$3"
    
    cat << EOF

${YELLOW}═══════════════════════════════════════════════════════════════${NC}
  Zabbix Agent 2 Installation Plan
${YELLOW}═══════════════════════════════════════════════════════════════${NC}

System:           Ubuntu $UBUNTU_VERSION
Zabbix Version:   7.4 (latest release)
Package:          $ZABBIX_PACKAGE

Configuration:
  - Server:       $server_ip
  - ServerActive: $server_active_ip  
  - Hostname:     $hostname

Installation steps (according to Zabbix documentation):
  1. Install Zabbix repository
  2. Update package list
  3. Install zabbix-agent2
  4. Install plugins (MongoDB, MSSQL, PostgreSQL)
  5. Configure parameters in /etc/zabbix/zabbix_agent2.conf
  6. Restart and enable service

${YELLOW}═══════════════════════════════════════════════════════════════${NC}

EOF
    
    read -p "Continue installation? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[TtYy]$ ]] && [[ -n $REPLY ]]; then
        log_info "Installation cancelled by user"
        exit 0
    fi
}

# Detect hostname
get_hostname() {
    local hostname=$(hostnamectl --static 2>/dev/null || hostname -s)
    if [ -z "$hostname" ]; then
        log_error "Failed to detect system hostname"
        exit 1
    fi
    echo "$hostname"
}

# Check Ubuntu version
check_ubuntu_version() {
    if [ ! -f /etc/os-release ]; then
        log_error "Cannot determine operating system version"
        exit 1
    fi

    . /etc/os-release
    
    if [ "$ID" != "ubuntu" ]; then
        log_error "This script is designed for Ubuntu. Detected: $ID"
        exit 1
    fi

    log_info "Detected Ubuntu $VERSION_ID ($VERSION_CODENAME)"
    
    # Determine Zabbix repository package based on Ubuntu version
    case $VERSION_ID in
        20.04)
            ZABBIX_PACKAGE="zabbix-release_latest_7.4+ubuntu20.04_all.deb"
            ;;
        22.04)
            ZABBIX_PACKAGE="zabbix-release_latest_7.4+ubuntu22.04_all.deb"
            ;;
        24.04)
            ZABBIX_PACKAGE="zabbix-release_latest_7.4+ubuntu24.04_all.deb"
            ;;
        *)
            log_warning "Officially unsupported Ubuntu version: $VERSION_ID"
            log_warning "Attempting to use package for Ubuntu 24.04"
            ZABBIX_PACKAGE="zabbix-release_latest_7.4+ubuntu24.04_all.deb"
            ;;
    esac
    
    UBUNTU_VERSION="$VERSION_ID"
}

# Install Zabbix Agent 2
install_zabbix_agent() {
    log_info "Starting Zabbix Agent 2 installation..."

    # Update package list
    log_info "Updating package list..."
    apt-get update -qq

    # Install required packages
    log_info "Installing required packages..."
    apt-get install -y wget

    # Download and install Zabbix repository according to official documentation
    log_info "Adding Zabbix 7.4 repository..."
    log_info "Downloading package: $ZABBIX_PACKAGE"
    
    ZABBIX_REPO_URL="https://repo.zabbix.com/zabbix/7.4/release/ubuntu/pool/main/z/zabbix-release/${ZABBIX_PACKAGE}"
    
    # Download release package
    if ! wget -q "$ZABBIX_REPO_URL" -O /tmp/zabbix-release.deb; then
        log_error "Failed to download Zabbix repository package"
        log_error "URL: $ZABBIX_REPO_URL"
        exit 1
    fi
    
    # Install release package
    log_info "Installing Zabbix repository package..."
    if ! dpkg -i /tmp/zabbix-release.deb; then
        log_error "Failed to install repository package"
        exit 1
    fi
    
    # Update package list after adding repository
    log_info "Updating package list from Zabbix repository..."
    apt-get update -qq

    # Install Zabbix Agent 2
    log_info "Installing Zabbix Agent 2..."
    if ! apt-get install -y zabbix-agent2; then
        log_error "Failed to install Zabbix Agent 2"
        exit 1
    fi

    # Install Zabbix Agent 2 plugins
    log_info "Installing Zabbix Agent 2 plugins..."
    apt-get install -y \
        zabbix-agent2-plugin-mongodb \
        zabbix-agent2-plugin-mssql \
        zabbix-agent2-plugin-postgresql 2>/dev/null || \
        log_warning "Some plugins may not be available for this version"

    # Cleanup
    rm -f /tmp/zabbix-release.deb

    log_info "Zabbix Agent 2 installed successfully"
}

# Configure Zabbix Agent 2
configure_zabbix_agent() {
    local server_ip="$1"
    local server_active_ip="$2"
    local hostname="$3"
    
    local config_file="/etc/zabbix/zabbix_agent2.conf"

    if [ ! -f "$config_file" ]; then
        log_error "Configuration file $config_file does not exist!"
        exit 1
    fi

    log_info "Configuring Zabbix Agent 2..."
    log_info "  Server: $server_ip"
    log_info "  ServerActive: $server_active_ip"
    log_info "  Hostname: $hostname"

    # Backup original configuration
    cp "$config_file" "${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
    log_info "Created configuration backup: ${config_file}.backup.$(date +%Y%m%d_%H%M%S)"

    # Change Server parameter
    if grep -q "^Server=" "$config_file"; then
        sed -i "s/^Server=.*/Server=$server_ip/" "$config_file"
    elif grep -q "^# Server=" "$config_file"; then
        sed -i "s/^# Server=.*/Server=$server_ip/" "$config_file"
    else
        echo "Server=$server_ip" >> "$config_file"
    fi

    # Change ServerActive parameter
    if grep -q "^ServerActive=" "$config_file"; then
        sed -i "s/^ServerActive=.*/ServerActive=$server_active_ip/" "$config_file"
    elif grep -q "^# ServerActive=" "$config_file"; then
        sed -i "s/^# ServerActive=.*/ServerActive=$server_active_ip/" "$config_file"
    else
        echo "ServerActive=$server_active_ip" >> "$config_file"
    fi

    # Change Hostname parameter
    if grep -q "^Hostname=" "$config_file"; then
        sed -i "s/^Hostname=.*/Hostname=$hostname/" "$config_file"
    elif grep -q "^# Hostname=" "$config_file"; then
        sed -i "s/^# Hostname=.*/Hostname=$hostname/" "$config_file"
    else
        echo "Hostname=$hostname" >> "$config_file"
    fi

    log_info "Configuration has been updated"
}

# Start and enable Zabbix Agent 2
start_zabbix_agent() {
    log_info "Starting Zabbix Agent 2..."
    
    # Restart service according to documentation
    log_info "Executing: systemctl restart zabbix-agent2"
    systemctl restart zabbix-agent2
    
    # Enable autostart according to documentation
    log_info "Executing: systemctl enable zabbix-agent2"
    systemctl enable zabbix-agent2
    
    # Check status
    sleep 2
    if systemctl is-active --quiet zabbix-agent2; then
        log_info "Zabbix Agent 2 started successfully"
    else
        log_error "Failed to start Zabbix Agent 2"
        log_error "Check service status:"
        systemctl status zabbix-agent2 --no-pager
        exit 1
    fi
}

# Display summary
show_summary() {
    local server_ip="$1"
    local server_active_ip="$2"
    local hostname="$3"
    
    cat << EOF

${GREEN}═══════════════════════════════════════════════════════════════${NC}
${GREEN}  Zabbix Agent 2 Installation Completed Successfully!${NC}
${GREEN}═══════════════════════════════════════════════════════════════${NC}

Installed version: Zabbix Agent 2 v7.4
Operating system: Ubuntu $UBUNTU_VERSION

Configuration:
  - Server:       $server_ip
  - ServerActive: $server_active_ip
  - Hostname:     $hostname
  - Config file:  /etc/zabbix/zabbix_agent2.conf

Service status:
$(systemctl status zabbix-agent2 --no-pager -l | head -n 10)

Installed plugins:
  - MongoDB
  - MSSQL
  - PostgreSQL

Useful commands:
  - Status:       systemctl status zabbix-agent2
  - Restart:      systemctl restart zabbix-agent2
  - Stop:         systemctl stop zabbix-agent2
  - Logs:         tail -f /var/log/zabbix/zabbix_agent2.log
  - Configuration: nano /etc/zabbix/zabbix_agent2.conf

${GREEN}═══════════════════════════════════════════════════════════════${NC}

EOF
}

# Main function
main() {
    echo ""
    log_info "═══════════════════════════════════════════════════════════════"
    log_info "  Zabbix Agent 2 Installation Script for Ubuntu"
    log_info "═══════════════════════════════════════════════════════════════"
    echo ""

    # Check privileges
    check_root

    # Parse arguments
    parse_args "$@"

    # Check Ubuntu version
    check_ubuntu_version

    # Detect hostname
    SYSTEM_HOSTNAME=$(get_hostname)
    log_info "Detected hostname: $SYSTEM_HOSTNAME"

    # Display installation plan
    show_installation_plan "$SERVER_IP" "$SERVER_ACTIVE_IP" "$SYSTEM_HOSTNAME"

    # Installation
    install_zabbix_agent

    # Configuration
    configure_zabbix_agent "$SERVER_IP" "$SERVER_ACTIVE_IP" "$SYSTEM_HOSTNAME"

    # Start
    start_zabbix_agent

    # Summary
    show_summary "$SERVER_IP" "$SERVER_ACTIVE_IP" "$SYSTEM_HOSTNAME"

    log_info "Installation completed!"
}

# Run script
main "$@"
