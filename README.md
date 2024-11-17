# Jellyfin Suspend Inhibitor for Linux

A systemd service that prevents system suspension while Jellyfin media is playing. This is particularly useful for Jellyfin server installations where you want to prevent the system from going to sleep during remote playback.

## Features

- Prevents system suspension during active Jellyfin playback
- Automatically allows system suspension when playback is paused or stopped
- Works with remote playback sessions
- Minimal resource usage
- Proper systemd integration

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
curl -O https://raw.githubusercontent.com/yourusername/jellyfin-suspend-inhibitor/main/install.sh
chmod +x install.sh
```

2. Run the installation script:
```bash
sudo ./install.sh
```

3. Configure your Jellyfin API key:
```bash
sudo nano /usr/local/bin/jellyfin-inhibitor.sh
```
Find the line:
```bash
response=$(curl -s "http://localhost:8096/Sessions?api_key=YOUR_API_KEY")
```
Replace `YOUR_API_KEY` with the API key you created earlier.

4. Restart the service:
```bash
sudo systemctl restart jellyfin-inhibitor
```

## Manual Installation

1. Create the script file:
```bash
sudo nano /usr/local/bin/jellyfin-inhibitor.sh
```

2. Copy and paste the following content into the file:
```bash
#!/bin/bash

# Enable logging
exec 1> >(logger -s -t $(basename $0)) 2>&1

INHIBITOR_TAG="jellyfin-playback-inhibitor"

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
    # Kill all existing jellyfin inhibitors
    pkill -f "systemd-inhibit.*$INHIBITOR_TAG"
}

create_inhibitor() {
    # Only create if no inhibitor exists
    if ! pgrep -f "systemd-inhibit.*$INHIBITOR_TAG" >/dev/null; then
        systemd-inhibit --what=sleep:idle --who="Jellyfin" \
                       --why="Media playback in progress" \
                       --mode=block \
                       bash -c "echo \$\$ > /tmp/$INHIBITOR_TAG.pid && exec sleep infinity" &
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
```

3. Update the API key:
   - In the script you just created, find the line:
     ```bash
     response=$(curl -s "http://localhost:8096/Sessions?api_key=YOUR_API_KEY")
     ```
   - Replace `YOUR_API_KEY` with your actual Jellyfin API key
   - Save the file (in nano: Ctrl+O, Enter, Ctrl+X)

4. Make the script executable:
```bash
sudo chmod +x /usr/local/bin/jellyfin-inhibitor.sh
```

5. Create the systemd service file:
```bash
sudo nano /etc/systemd/system/jellyfin-inhibitor.service
```

6. Copy and paste the following content into the service file:
```ini
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
```

7. Enable and start the service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable jellyfin-inhibitor
sudo systemctl start jellyfin-inhibitor
```

8. Verify the service is running:
```bash
sudo systemctl status jellyfin-inhibitor
```

## Configuration

The script uses the following configuration:
- Default Jellyfin server address: `http://localhost:8096`
- Check interval: 30 seconds
- Inhibits both sleep and idle modes

To modify these settings, edit the script file:
```bash
sudo nano /usr/local/bin/jellyfin-inhibitor.sh
```

## Verification

Check if the service is running:
```bash
sudo systemctl status jellyfin-inhibitor
```

View logs:
```bash
sudo journalctl -u jellyfin-inhibitor -f
```

List active inhibitors:
```bash
systemd-inhibit --list
```

## Troubleshooting

1. If the service isn't starting:
   - Check the logs: `sudo journalctl -u jellyfin-inhibitor -f`
   - Verify the API key is correct
   - Ensure Jellyfin is running and accessible

2. If suspension isn't being prevented:
   - Verify the service is running
   - Check if the inhibitor appears in the list: `systemd-inhibit --list`
   - Check the logs for playback detection

3. API Key Issues:
   - If you get authentication errors, create a new API key
   - Verify there are no spaces or extra characters when pasting the key
   - Ensure the API key has not been revoked in the Jellyfin dashboard

4. Common API Key Errors:
   - "401 Unauthorized": Invalid or expired API key
   - "No response": Check if Jellyfin is running and the server address is correct
   - "Connection refused": Check if the Jellyfin server address is correct

## Security Considerations

- The API key provides access to Jellyfin sessions information
- Keep the API key secure and don't share it
- The script runs as root but only accesses Jellyfin API and system sleep states
- Consider using a dedicated API key for this service

## License

MIT License - See LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
