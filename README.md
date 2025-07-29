# Mailcow TLSA Auto-Update

Automatic TLSA DNS record updater for Mailcow mail servers using Cloudflare DNS.

## Overview

This system automatically monitors SSL certificate changes in Mailcow and updates TLSA (DNS-based Authentication of Named Entities) records in Cloudflare. When Mailcow renews certificates through ACME/Let's Encrypt, the TLSA records are automatically updated to match the new certificate fingerprint.

Based on the original work by [wardpieters/cloudflare_tlsa_mailcow.sh](https://github.com/wardpieters/cloudflare_tlsa_mailcow.sh), this enhanced version adds automatic monitoring and systemd integration.

## Features

- 🔄 Automatic detection of certificate changes
- ☁️ Cloudflare DNS integration
- 📱 Telegram notifications for update status
- 🛡️ Systemd service for reliability
- 📝 Detailed logging

## Requirements

- Mailcow-dockerized installation
- Cloudflare account with API access
- Linux system with systemd
- `jq` for JSON parsing
- `inotify-tools` for file monitoring
- `openssl` for certificate processing
- `curl` for API requests

## Installation

1. **Clone or download the files to your server**

2. **Install dependencies**:
   ```bash
   apt-get update
   apt-get install -y jq inotify-tools
   ```

3. **Copy files to their locations**:
   ```bash
   # Create directories
   mkdir -p /opt/mailcow-dockerized/data/hooks/acme
   
   # Copy scripts
   cp update_tlsa.sh /opt/mailcow-dockerized/data/hooks/acme/
   cp config.conf /opt/mailcow-dockerized/data/hooks/acme/
   cp watch-cert-changes.sh /usr/local/bin/
   
   # Make scripts executable
   chmod +x /opt/mailcow-dockerized/data/hooks/acme/update_tlsa.sh
   chmod +x /usr/local/bin/watch-cert-changes.sh
   
   # Copy systemd service
   cp mailcow-tlsa-watcher.service /etc/systemd/system/
   ```

4. **Configure the system**:
   Edit `/opt/mailcow-dockerized/data/hooks/acme/config.conf` with your settings:
   ```bash
   # Domain settings
   zone="yourdomain.com"
   dnsrecord="mail.yourdomain.com"
   
   # Cloudflare settings
   cloudflare_token="your-cloudflare-api-token"
   
   # Telegram settings (optional)
   telegram_bot_token="your-telegram-bot-token"
   telegram_chat_id="your-telegram-chat-id"
   ```

5. **Enable and start the service**:
   ```bash
   systemctl daemon-reload
   systemctl enable mailcow-tlsa-watcher.service
   systemctl start mailcow-tlsa-watcher.service
   ```

## Configuration

### Cloudflare API Token

Create a Cloudflare API token with the following permissions:
- Zone → DNS → Edit
- Zone → Zone → Read

Limit the token to the specific zone containing your mail server domain.

### Telegram Notifications (Optional)

To receive notifications via Telegram:
1. Create a bot using [@BotFather](https://t.me/botfather)
2. Get your chat ID by messaging the bot and visiting:
   `https://api.telegram.org/bot<YourBotToken>/getUpdates`
3. Add the bot token and chat ID to the config file

## How It Works

1. **Certificate Monitoring**: The watcher script uses `inotifywait` to monitor changes to the Mailcow SSL certificate at `/opt/mailcow-dockerized/data/assets/ssl/cert.pem`

2. **Change Detection**: When a certificate change is detected (renewal, replacement), the script waits 10 seconds for the operation to complete

3. **TLSA Generation**: The update script extracts the public key from the certificate and generates a SHA-256 hash

4. **DNS Update**: Using the Cloudflare API, the script:
   - Checks if TLSA records exist
   - Creates new records if missing
   - Updates existing records if the hash has changed
   - Skips if records are already up-to-date

5. **Notifications**: Sends status updates via Telegram (if configured)

## TLSA Record Details

The script creates TLSA records with the following parameters:
- **Usage**: 3 (DANE-EE)
- **Selector**: 1 (SubjectPublicKeyInfo)
- **Matching Type**: 1 (SHA-256)
- **Port**: 25 (SMTP)

Example DNS record:
```
_25._tcp.mail.yourdomain.com. 1 IN TLSA 3 1 1 <certificate-hash>
```

## Monitoring

Check service status:
```bash
systemctl status mailcow-tlsa-watcher.service
```

View logs:
```bash
journalctl -u mailcow-tlsa-watcher.service -f
```

Test the update script manually:
```bash
/opt/mailcow-dockerized/data/hooks/acme/update_tlsa.sh
```

## Troubleshooting

### Service won't start
- Check file permissions
- Verify all paths exist
- Check systemd logs: `journalctl -xe`

### TLSA records not updating
- Verify Cloudflare API token permissions
- Check if the zone name matches exactly
- Test API access manually with curl

### No notifications
- Verify Telegram bot token and chat ID
- Ensure the bot has sent at least one message to you
- Check if curl can reach Telegram API

## Security Considerations

- Store API tokens securely with restricted file permissions:
  ```bash
  chmod 600 /opt/mailcow-dockerized/data/hooks/acme/config.conf
  ```
- Use Cloudflare API tokens with minimal required permissions
- Consider using environment variables for sensitive data in production

## Credits

This project is based on and inspired by [wardpieters/cloudflare_tlsa_mailcow.sh](https://github.com/wardpieters/cloudflare_tlsa_mailcow.sh). The original script has been extended with:
- Automatic certificate monitoring using inotify
- Systemd service integration
- Enhanced error handling
- Telegram notification support

## Contributing

Issues and pull requests are welcome! Please test thoroughly before submitting changes that affect certificate handling.
