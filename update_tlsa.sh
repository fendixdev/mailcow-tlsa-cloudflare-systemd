#!/bin/bash
# /opt/mailcow-dockerized/data/hooks/acme/update_tlsa.sh
# 
# Based on cloudflare_tlsa_mailcow.sh by wardpieters
# https://github.com/wardpieters/cloudflare_tlsa_mailcow.sh
#
# Extended with automatic monitoring and notification features
#
# Load configuration
CONFIG_FILE="/opt/mailcow-dockerized/data/hooks/acme/config.conf"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Error: Config file not found at $CONFIG_FILE"
    exit 1
fi

# Telegram notification function
send_telegram() {
    local message="$1"
    if [ ! -z "$telegram_bot_token" ] && [ ! -z "$telegram_chat_id" ]; then
        curl -s -X POST "https://api.telegram.org/bot${telegram_bot_token}/sendMessage" \
            -H 'Content-Type: application/json' \
            -d "{\"chat_id\": \"${telegram_chat_id}\", \"text\": \"${message}\", \"parse_mode\": \"HTML\"}" \
            > /dev/null 2>&1
    fi
}

# Send start notification
send_telegram "🔐 <b>TLSA Update Started</b>\n\nDomain: ${dnsrecord}\nTime: $(date '+%Y-%m-%d %H:%M:%S')"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install it first."
    echo "On Debian/Ubuntu: sudo apt-get install jq"
    echo "On CentOS/RHEL: sudo yum install jq"
    send_telegram "❌ <b>Error</b>\n\njq is not installed on the server"
    exit 1
fi

# get certificate hash
chain_hash=$(openssl x509 -in /opt/mailcow-dockerized/data/assets/ssl/cert.pem -noout -pubkey | openssl pkey -pubin -outform DER | openssl dgst -sha256 -binary | hexdump -ve '/1 "%02x"')

echo "Certificate hash: $chain_hash"

# get the zone id for the requested zone
zone_response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$zone&status=active" \
  -H "Authorization: Bearer $cloudflare_token" \
  -H "Content-Type: application/json")

zone_id=$(echo "$zone_response" | jq -r '.result[0].id')

if [ -z "$zone_id" ] || [ "$zone_id" == "null" ]; then
    echo "Error: Could not get zone ID for $zone"
    echo "Response: $zone_response"
    send_telegram "❌ <b>TLSA Update Failed</b>\n\nCould not get zone ID for ${zone}\nCheck Cloudflare API token permissions"
    exit 1
fi

echo "ID for $zone is $zone_id"

# Define ports array - properly quoted
ports=("_25._tcp")

# Counter for updates
updates_made=0
errors_count=0

for port in "${ports[@]}"
do
    # Properly quote the full record name
    full_record="${port}.${dnsrecord}"
    
    echo "Processing record $full_record ..."
    
    # get the dns record id
    dnsrecord_req=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=TLSA&name=$full_record" \
        -H "Authorization: Bearer $cloudflare_token" \
        -H "Content-Type: application/json")
    
    dnsrecord_id=$(echo "$dnsrecord_req" | jq -r '.result[0].id')
    dnsrecord_hash=$(echo "$dnsrecord_req" | jq -r '.result[0].data.certificate')

    if [ -z "$dnsrecord_id" ] || [ "$dnsrecord_id" == "null" ]
    then
        # Add the record
        echo "Adding new TLSA record..."
        add_response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
            -H "Authorization: Bearer $cloudflare_token" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"TLSA\",\"name\":\"$full_record\", \"data\": {\"usage\": \"3\", \"selector\": \"1\", \"matching_type\": \"1\", \"certificate\":\"$chain_hash\"},\"ttl\":1,\"proxied\":false}")
        
        success=$(echo "$add_response" | jq -r '.success')
        if [ "$success" == "true" ]; then
            echo "Record $full_record added successfully!"
            updates_made=$((updates_made + 1))
        else
            echo "Error adding record:"
            echo "$add_response" | jq
            errors_count=$((errors_count + 1))
        fi
    else
        if [[ "$dnsrecord_hash" != "$chain_hash" ]]
        then
            # Update the record
            echo "Updating existing TLSA record..."
            update_response=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$dnsrecord_id" \
                -H "Authorization: Bearer $cloudflare_token" \
                -H "Content-Type: application/json" \
                --data "{\"type\":\"TLSA\",\"name\":\"$full_record\", \"data\": {\"usage\": \"3\", \"selector\": \"1\", \"matching_type\": \"1\", \"certificate\":\"$chain_hash\"},\"ttl\":1,\"proxied\":false}")

            success=$(echo "$update_response" | jq -r '.success')
            if [ "$success" == "true" ]; then
                echo "Record $full_record updated successfully!"
                updates_made=$((updates_made + 1))
            else
                echo "Error updating record:"
                echo "$update_response" | jq
                errors_count=$((errors_count + 1))
            fi
        else
            echo "Record $full_record is already up to date!"
        fi
    fi
done

# Send completion notification
if [ $errors_count -gt 0 ]; then
    send_telegram "⚠️ <b>TLSA Update Completed with Errors</b>\n\nDomain: ${dnsrecord}\n📊 Records updated: ${updates_made}\n❌ Errors: ${errors_count}\n🕐 Time: $(date '+%Y-%m-%d %H:%M:%S')"
elif [ $updates_made -gt 0 ]; then
    send_telegram "✅ <b>TLSA Update Completed</b>\n\nDomain: ${dnsrecord}\n📊 Records updated: ${updates_made}\n🕐 Time: $(date '+%Y-%m-%d %H:%M:%S')"
else
    send_telegram "ℹ️ <b>TLSA Check Completed</b>\n\nDomain: ${dnsrecord}\n✓ All records are up to date\n🕐 Time: $(date '+%Y-%m-%d %H:%M:%S')"
fi
