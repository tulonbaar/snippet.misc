#!/bin/bash

# Get script directory to work with relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_DIR="$SCRIPT_DIR/cert"

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to display colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_progress() {
    echo -e "${CYAN}[PROGRESS]${NC} $1"
}

# List of hosts
HOSTS=("host-1" "host-2" "host-3")

# Check if certificate directory exists
if [ ! -d "$CERT_DIR" ]; then
    print_error "Certificate directory $CERT_DIR does not exist!"
    exit 1
fi

# Check if there are certificate files
if [ -z "$(ls -A "$CERT_DIR"/ 2>/dev/null)" ]; then
    print_error "No certificate files in directory $CERT_DIR/"
    exit 1
fi

print_info "Starting certificate copy to ${#HOSTS[@]} hosts..."
print_info "Source certificates: $(ls -1 "$CERT_DIR"/ | tr '\n' ' ')"
echo ""

SUCCESSFUL_HOSTS=0
FAILED_HOSTS=0

for i in "${!HOSTS[@]}"; do
    HOST="${HOSTS[i]}"
    HOST_NUM=$((i + 1))
    
    echo -e "${CYAN}=====================================================================${NC}"
    print_progress "[$HOST_NUM/${#HOSTS[@]}] Processing host: ${YELLOW}$HOST${NC}"
    echo -e "${CYAN}=====================================================================${NC}"
    
    # Create directory for certificates
    print_info "Creating directory /home/deploy/certs/ on $HOST..."
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$HOST" "mkdir -p /home/deploy/certs/" 2>/dev/null; then
        print_success "Directory created successfully"
    else
        print_error "Cannot create directory on $HOST"
        ((FAILED_HOSTS++))
        echo ""
        continue
    fi
    
    # Copy certificates
    print_info "Copying certificates to $HOST..."
    if scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 -r "$CERT_DIR"/* "$HOST":/home/deploy/certs/ 2>/dev/null; then
        print_success "Certificates copied successfully to $HOST"
        ((SUCCESSFUL_HOSTS++))
        
        # Verify copied files
        print_info "Verifying copied files..."
        COPIED_FILES=$(ssh -o StrictHostKeyChecking=no "$HOST" "ls -la /home/deploy/certs/ 2>/dev/null" | wc -l)
        if [ "$COPIED_FILES" -gt 2 ]; then
            print_success "Verification completed successfully ($((COPIED_FILES - 2)) files)"
        else
            print_warning "Verification failed - check files manually"
        fi
    else
        print_error "Failed to copy certificates to $HOST"
        ((FAILED_HOSTS++))
    fi
    
    echo ""
done

# Summary
echo -e "${CYAN}=====================================================================${NC}"
echo -e "${CYAN}                              SUMMARY${NC}"
echo -e "${CYAN}=====================================================================${NC}"

if [ $SUCCESSFUL_HOSTS -eq ${#HOSTS[@]} ]; then
    print_success "All certificates copied successfully!"
    print_info "Hosts processed: ${#HOSTS[@]}"
    print_success "Successful hosts: $SUCCESSFUL_HOSTS"
elif [ $SUCCESSFUL_HOSTS -gt 0 ]; then
    print_warning "Copy completed with errors"
    print_info "Hosts processed: ${#HOSTS[@]}"
    print_success "Successful hosts: $SUCCESSFUL_HOSTS"
    print_error "Failed hosts: $FAILED_HOSTS"
else
    print_error "Failed to copy certificates to any host!"
    print_info "Hosts processed: ${#HOSTS[@]}"
    print_error "Failed hosts: $FAILED_HOSTS"
    exit 1
fi

echo ""
print_info "Script finished."