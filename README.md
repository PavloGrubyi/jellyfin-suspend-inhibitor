# Jellyfin Suspend Inhibitor for Linux

A systemd user service that prevents system suspension while Jellyfin media is playing. This is particularly useful for Jellyfin server installations where you want to prevent the system from going to sleep during remote playback.

## Features

- Prevents system suspension during active Jellyfin playback
- Automatically allows system suspension when playback is paused or stopped
- Works with remote playback sessions
- Minimal resource usage
- Proper systemd integration
- Runs without root privileges as a user service
- Supports multiple users with individual configurations

## Prerequisites

- Debian-based Linux system (tested on Debian 12)
- Jellyfin Media Server
- systemd
- curl
- Jellyfin API key

## Getting Jellyfin API Key

1. Log in to your Jellyfin web interface as an administrator
2. Go to Dashboard 
   - Click on the user icon in the top-right corner
   - Select "Dashboard"

3. Navigate to API Keys:
   - In the left sidebar, scroll down to "Advanced"
   - Click on "API Keys"

4. Create new API Key:
   - Click the "+" button or "New API Key"
   - Enter a name for your key (e.g., "Suspend Inhibitor")
   - Click "OK" to generate the key

5. Copy the generated API key:
   - The key will be shown only once
   - It looks like a long string of letters and numbers
   - Save this key securely as you'll need it during installation

Note: If you lose the API key, you can't recover it - you'll need to create a new one.

## Installation

1. Download the installation script:
```bash
curl -O https://raw.githubusercontent.com/PavloGrubyi/jellyfin-suspend-inhibitor/main/install.sh
chmod +x install.sh
```

2. Run the installation script as your normal user (NOT as root):
```bash
./install.sh
```

3. When prompted, enter your Jellyfin API key

The script will:
- Create necessary directories
- Install the service for your user
- Enable automatic startup
- Start the service
- Test the API key

## Service Management

Check service status:
```bash
systemctl --user status jellyfin-inhibitor
```

View logs:
```bash
journalctl --user -u jellyfin-inhibitor -f
```

Stop the service:
```bash
systemctl --user stop jellyfin-inhibitor
```

Start the service:
```bash
systemctl --user start jellyfin-inhibitor
```

Disable service autostart:
```bash
systemctl --user disable jellyfin-inhibitor
```

Enable service autostart:
```bash
systemctl --user enable jellyfin-inhibitor
```

## Manual Installation

1. Create necessary directories:
```bash
mkdir -p ~/.local/bin
mkdir -p ~/.config/systemd/user
```

2. Create the script file:
```bash
nano ~/.local/bin/jellyfin-inhibitor.sh
```

3. Copy and paste the following content into the file:
```bash
#!/bin/bash

# Enable logging
exec 1> >(logger -s -t $(basename $0)) 2>&1

INHIBITOR_TAG="jellyfin-playback-inhibitor-$USER"

check_jellyfin_playback() {
    # Get active sessions from Jellyfin API
    response=$(curl -s "http://localhost:8096/Sessions?api_key=YOUR_API_KEY")
    
    # Check for active video playback
    if echo "$response" | grep -q '"IsPaused":false' && \
       echo "$response" | grep -q '"PositionTicks":[1-9]' && \
       echo "$response" | grep -q '"MediaType":"Video"'; then
        return 0
    fi
    return 1
}

cleanup_inhibitors() {
    # Kill all existing jellyfin inhibitors for this user
    pkill -f "systemd-inhibit.*$INHIBITOR_TAG"
}

create_inhibitor() {
    # Only create if no inhibitor exists
    if ! pgrep -f "systemd-inhibit.*$INHIBITOR_TAG" >/dev/null; then
        # Enhanced inhibitor flags to prevent both manual and automatic suspend
        systemd-inhibit --what=sleep:idle:handle-lid-switch:handle-power-key \
                       --who="Jellyfin ($USER)" \
                       --why="Media playback in progress" \
                       --mode=block \
                       bash -c "echo \$\$ > /tmp/$INHIBITOR_TAG.pid && exec sleep infinity" &
        
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
```

4. Update the API key:
   - In the script you just created, find the line:
     ```bash
     response=$(curl -s "http://localhost:8096/Sessions?api_key=YOUR_API_KEY")
     ```
   - Replace `YOUR_API_KEY` with your actual Jellyfin API key
   - Save the file (in nano: Ctrl+O, Enter, Ctrl+X)

5. Make the script executable:
```bash
chmod +x ~/.local/bin/jellyfin-inhibitor.sh
```

6. Create the systemd user service file:
```bash
nano ~/.config/systemd/user/jellyfin-inhibitor.service
```

7. Copy and paste the following content into the service file:
```ini
[Unit]
Description=Jellyfin Suspend Inhibitor
After=network.target

[Service]
Type=simple
ExecStart=%h/.local/bin/jellyfin-inhibitor.sh
Restart=always

[Install]
WantedBy=default.target
```

8. Enable user service lingering (allows the service to run when user is not logged in):
```bash
loginctl enable-linger "$USER"
```

9. Enable and start the service:
```bash
systemctl --user daemon-reload
systemctl --user enable jellyfin-inhibitor
systemctl --user start jellyfin-inhibitor
```

## Configuration

The script uses the following configuration:
- Default Jellyfin server address: `http://localhost:8096`
- Check interval: 30 seconds
- Inhibits both sleep and idle modes

To modify these settings, edit the script file:
```bash
nano ~/.local/bin/jellyfin-inhibitor.sh
```

## Troubleshooting

1. If the service isn't starting:
   - Check the logs: `journalctl --user -u jellyfin-inhibitor -f`
   - Verify the API key is correct
   - Ensure Jellyfin is running and accessible

2. If suspension isn't being prevented:
   - Verify the service is running: `systemctl --user status jellyfin-inhibitor`
   - Check if the inhibitor appears in the list: `systemd-inhibit --list`
   - Check the logs for playback detection

3. API Key Issues:
   - If you get authentication errors, create a new API key
   - Verify there are no spaces or extra characters when pasting the key
   - Ensure the API key has not been revoked in the Jellyfin dashboard

4. If the service stops working after system reboot:
   - Check if user lingering is enabled: `loginctl show-user $USER | grep Linger`
   - If it shows "Linger=no", run: `loginctl enable-linger "$USER"`

## Security Considerations

- The service runs entirely under user context without requiring root privileges
- Each user can have their own instance of the service with their own API key
- The API key provides access only to Jellyfin sessions information
- Keep the API key secure and don't share it
- The script only accesses Jellyfin API and system sleep states

## License

MIT License - See LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
