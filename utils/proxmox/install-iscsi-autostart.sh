#!/bin/bash
# Script for installing automatic iSCSI session login on all PVE nodes

NODES=("pveX") # Replace pveX with actual node hostnames or IPs
SCRIPT_NAME="iscsi-login-check.sh"
SERVICE_NAME="iscsi-login-check.service"

echo "=== Installing automatic iSCSI login on PVE nodes ==="
echo ""

for NODE in "${NODES[@]}"; do
    echo "--- Installing on $NODE ---"
    
    # Copy script
    echo "  Copying script..."
    scp "$SCRIPT_NAME" "root@${NODE}:/usr/local/bin/" || {
        echo "  ERROR: Failed to copy script to $NODE"
        continue
    }
    
    # Set permissions
    echo "  Setting permissions..."
    ssh "root@${NODE}" "chmod +x /usr/local/bin/$SCRIPT_NAME" || {
        echo "  ERROR: Failed to set permissions on $NODE"
        continue
    }
    
    # Copy service file
    echo "  Copying systemd service file..."
    scp "$SERVICE_NAME" "root@${NODE}:/etc/systemd/system/" || {
        echo "  ERROR: Failed to copy service to $NODE"
        continue
    }
    
    # Reload systemd and enable service
    echo "  Configuring systemd..."
    ssh "root@${NODE}" "systemctl daemon-reload && systemctl enable $SERVICE_NAME" || {
        echo "  ERROR: Failed to configure systemd on $NODE"
        continue
    }
    
    echo "  SUCCESS: Installation completed on $NODE"
    echo ""
done

echo "=== Installation completed ==="
echo ""
echo "To test the script manually, run:"
echo "  ssh root@pveX 'systemctl start iscsi-login-check.service'"
echo ""
echo "To check logs:"
echo "  ssh root@pveX 'cat /var/log/iscsi-login-check.log'"
echo "  ssh root@pveX 'journalctl -u iscsi-login-check.service'"
echo ""
echo "To check service status:"
echo "  ssh root@pveX 'systemctl status iscsi-login-check.service'"
