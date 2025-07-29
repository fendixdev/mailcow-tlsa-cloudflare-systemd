#!/bin/bash
# /usr/local/bin/watch-cert-changes.sh

CERT_PATH="/opt/mailcow-dockerized/data/assets/ssl/cert.pem"
TLSA_SCRIPT="/opt/mailcow-dockerized/data/hooks/acme/update_tlsa.sh"

# Install inotify-tools if not present
if ! command -v inotifywait &> /dev/null; then
    apt-get update && apt-get install -y inotify-tools
fi

echo "Starting certificate watcher..."

while true; do
    # Wait for changes to the certificate file
    inotifywait -e modify,create,close_write,moved_to,attrib "$CERT_PATH"
    
    echo "Certificate change detected, waiting 10 seconds for completion..."
    sleep 10
    
    # Run the TLSA update script
    if [ -x "$TLSA_SCRIPT" ]; then
        echo "Running TLSA update script..."
        "$TLSA_SCRIPT"
    else
        echo "Error: TLSA script not found or not executable"
    fi
done
