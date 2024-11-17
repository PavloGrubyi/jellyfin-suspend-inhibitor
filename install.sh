#!/bin/bash

# Jellyfin Suspend Inhibitor Installer
# This script installs and configures the Jellyfin suspend inhibitor service

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Prompt for API key
echo "Please enter your Jellyfin API key:"
echo "  (You can find this in Jellyfin Dashboard → Advanced → API Keys)"
read -p "API Key: " API_KEY

# Validate API key is not empty
if [ -z "$API_KEY" ]; then
    echo "Error: API key cannot be empty"
    exit 1
fi

echo "Installing Jellyfin Suspend Inhibitor..."

# Create the inhibitor script
cat > /usr/local/bin/jellyfin-inhibitor.sh << EOL
#!/bin/bash

# Enable logging
exec 1> >(logger -s -t \$(basename \$0)) 2>&1

INHIBITOR_TAG="jellyfin-playback-inhibitor"

check_jellyfin_playback() {
    # Get active sessions from Jellyfin API
    response=\$(curl -s "http://localhost:8096/Sessions?api_key=${API_KEY}")
    
    # Check for active video playback
    if echo "\$response" | grep -q '"IsPaused":false' && \\
       echo "\$response" | grep -q '"PositionTicks":[1-9]' && \\
       echo "\$response" | grep -q '"MediaType":"Video"'; then
        return 0
    fi
    return 1
}

cleanup_inhibitors() {
    # Kill all existing jellyfin inhibitors
    pkill -f "systemd-inhibit.*\$INHIBITOR_TAG"
}

create_inhibitor() {
    # Only create if no inhibitor exists
    if ! pgrep -f "systemd-inhibit.*\$INHIBITOR_TAG" >/dev/null; then
        systemd-inhibit --what=sleep:idle --who="Jellyfin" \\
                       --why="Media playback in progress" \\
                       --mode=block \\
                       bash -c "echo \\\$\\\$ > /tmp/\$INHIBITOR_TAG.pid && exec sleep infinity" &
        echo "Created new suspend inhibitor"
    fi
}

# Cleanup on script exit
trap cleanup_inhibitors EXIT

# Main loop
while true; do
    if check_jellyfin_playback; then
        echo "Active playback detected"
        create_inhibitor
    else
        echo "No active playback"
        cleanup_inhibitors
    fi
    sleep 30
done
EOL

# Make the script executable
chmod +x /usr/local/bin/jellyfin-inhibitor.sh

# Create the systemd service
cat > /etc/systemd/system/jellyfin-inhibitor.service << 'EOL'
[Unit]
Description=Jellyfin Suspend Inhibitor
After=network.target jellyfin.service

[Service]
Type=simple
ExecStart=/usr/local/bin/jellyfin-inhibitor.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOL

# Reload systemd, enable and start the service
systemctl daemon-reload
systemctl enable jellyfin-inhibitor
systemctl start jellyfin-inhibitor

# Verify the service started successfully
if systemctl is-active --quiet jellyfin-inhibitor; then
    echo -e "\nInstallation completed successfully!"
    echo "The service is now running and will start automatically on boot."
    echo -e "\nYou can check the status with: sudo systemctl status jellyfin-inhibitor"
    echo "View the logs with: sudo journalctl -u jellyfin-inhibitor -f"
else
    echo -e "\nWarning: Service installation completed but the service failed to start."
    echo "Please check the logs with: sudo journalctl -u jellyfin-inhibitor -f"
fi

# Test API key
echo -e "\nTesting Jellyfin API key..."
response=$(curl -s "http://localhost:8096/Sessions?api_key=${API_KEY}")
if echo "$response" | grep -q "forbidden\|unauthorized\|error"; then
    echo "Warning: API key test failed. Please verify your API key is correct."
    echo "You can update it by editing /usr/local/bin/jellyfin-inhibitor.sh"
else
    echo "API key test successful!"
fi
