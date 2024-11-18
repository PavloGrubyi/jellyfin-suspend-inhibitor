#!/bin/bash

# Check if running as root (we don't want that)
if [ "$EUID" -eq 0 ]; then
    echo "Please run this script as a normal user, not as root"
    exit 1
fi

# Create necessary directories
mkdir -p ~/.local/bin
mkdir -p ~/.config/systemd/user

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
cat > ~/.local/bin/jellyfin-inhibitor.sh << EOL
#!/bin/bash

# Enable logging
exec 1> >(logger -s -t \$(basename \$0)) 2>&1

INHIBITOR_TAG="jellyfin-playback-inhibitor-\$USER"

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
    # Kill all existing jellyfin inhibitors for this user
    pkill -f "systemd-inhibit.*\$INHIBITOR_TAG"
}

create_inhibitor() {
    # Only create if no inhibitor exists
    if ! pgrep -f "systemd-inhibit.*\$INHIBITOR_TAG" >/dev/null; then
        # Enhanced inhibitor flags to prevent both manual and automatic suspend
        systemd-inhibit --what=sleep:idle:handle-lid-switch:handle-power-key \\
                       --who="Jellyfin (\$USER)" \\
                       --why="Media playback in progress" \\
                       --mode=block \\
                       bash -c "echo \\\$\\\$ > /tmp/\$INHIBITOR_TAG.pid && exec sleep infinity" &
        
        # Also prevent automatic suspend via gsettings
        gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
        gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
        echo "Created new suspend inhibitor"
    fi
}

restore_power_settings() {
    # Restore default power settings
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'suspend'
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'suspend'
}

# Cleanup on script exit
trap 'cleanup_inhibitors; restore_power_settings' EXIT

# Main loop
while true; do
    if check_jellyfin_playback; then
        echo "Active playback detected"
        create_inhibitor
    else
        echo "No active playback"
        cleanup_inhibitors
        restore_power_settings
    fi
    sleep 30
done
EOL

# Make the script executable
chmod +x ~/.local/bin/jellyfin-inhibitor.sh

# Create the systemd user service
cat > ~/.config/systemd/user/jellyfin-inhibitor.service << EOL
[Unit]
Description=Jellyfin Suspend Inhibitor
After=network.target

[Service]
Type=simple
ExecStart=${HOME}/.local/bin/jellyfin-inhibitor.sh
Restart=always

[Install]
WantedBy=default.target
EOL

# Enable user service lingering (allows the service to run even when user is not logged in)
loginctl enable-linger "$USER"

# Reload systemd user daemon
systemctl --user daemon-reload

# Enable and start the service
systemctl --user enable jellyfin-inhibitor
systemctl --user start jellyfin-inhibitor

# Verify the service started successfully
if systemctl --user is-active --quiet jellyfin-inhibitor; then
    echo -e "\nInstallation completed successfully!"
    echo "The service is now running and will start automatically on boot."
    echo -e "\nYou can check the status with: systemctl --user status jellyfin-inhibitor"
    echo "View the logs with: journalctl --user -u jellyfin-inhibitor -f"
else
    echo -e "\nWarning: Service installation completed but the service failed to start."
    echo "Please check the logs with: journalctl --user -u jellyfin-inhibitor -f"
fi

# Test API key
echo -e "\nTesting Jellyfin API key..."
response=$(curl -s "http://localhost:8096/Sessions?api_key=${API_KEY}")
if echo "$response" | grep -q "forbidden\|unauthorized\|error"; then
    echo "Warning: API key test failed. Please verify your API key is correct."
    echo "You can update it by editing ~/.local/bin/jellyfin-inhibitor.sh"
else
    echo "API key test successful!"
fi
