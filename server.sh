#!/bin/bash

DB_FILE="server_data.db"
PORT=9090

# Initialize the database if not present
if [[ ! -f $DB_FILE ]]; then
    sqlite3 $DB_FILE "CREATE TABLE users (username TEXT PRIMARY KEY, secret_key TEXT);"
    sqlite3 $DB_FILE "CREATE TABLE service_tickets (ticket_id TEXT PRIMARY KEY, service_name TEXT, username TEXT, timestamp TEXT, ticket_life TEXT);"
    sqlite3 $DB_FILE "INSERT INTO users (username, secret_key) VALUES ('user1', 'my_secret_key');"
fi

echo "Server is listening on port $PORT..."
while true; do
    # Listen for incoming messages
    nc -l -p $PORT | while read -r line; do
        if [[ "$line" == *"auth_request"* ]]; then
            # Handle TGT request
            username=$(echo "$line" | grep -oP '"username":"\K[^"]*')
            service_name=$(echo "$line" | grep -oP '"service_name":"\K[^"]*')
            user_ip=$(echo "$line" | grep -oP '"user_ip":"\K[^"]*')
            ticket_life=$(echo "$line" | grep -oP '"ticket_life":"\K[^"]*')

            echo "Authentication request from $username for service $service_name from $user_ip"

            # Lookup the user in the database
            secret_key=$(sqlite3 $DB_FILE "SELECT secret_key FROM users WHERE username = '$username';")
            if [[ -z $secret_key ]]; then
                echo "Invalid user" | nc -N $user_ip $PORT
                continue
            fi

            echo "User authenticated. Generating TGT..."

            # Generate the TGT
            tgt_id="TGT-$(date +%s)"
            timestamp=$(date "+%Y-%m-%d %H:%M:%S")
            tgt="{\"tgt_id\":\"$tgt_id\",\"timestamp\":\"$timestamp\",\"user_ip\":\"$user_ip\",\"ticket_life\":\"$ticket_life\",\"username\":\"$username\",\"service_name\":\"$service_name\"}"

            echo "TGT generated: $tgt"

            # Encrypt the TGT
            echo -n "$tgt" | openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:"$secret_key" > encrypted_ticket.txt

            # Send the encrypted TGT back to the user
            nc -N $user_ip $PORT < encrypted_ticket.txt

        elif [[ "$line" == *"service_request"* ]]; then
            # Handle service ticket request
            echo "Service ticket request received."

            username=$(echo "$line" | grep -oP '"username":"\K[^"]*')
            service_name=$(echo "$line" | grep -oP '"service_name":"\K[^"]*')
            decrypted_tgt=$(echo "$line" | grep -oP '"decrypted_tgt":"\K[^"]*')
            user_ip=$(echo "$line" | grep -oP '"user_ip":"\K[^"]*')

            # Generate service ticket
            ticket_id="ST-$(date +%s)" 
            timestamp=$(date "+%Y-%m-%d %H:%M:%S")
            service_ticket="{\"ticket_id\":\"$ticket_id\",\"timestamp\":\"$timestamp\",\"username\":\"$username\",\"service_name\":\"$service_name\",\"user_ip\":\"$user_ip\"}"

            echo "Service ticket generated: $service_ticket"

            echo "Service name: $service_name"

            # Encrypt the service ticket
            echo -n "$service_ticket" | openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:"$service_name" > encrypted_service_ticket.txt

            # Save the service ticket in the database
            sqlite3 $DB_FILE "INSERT INTO service_tickets (ticket_id, service_name, username, timestamp, ticket_life) VALUES ('$ticket_id', '$service_name', '$username', '$timestamp', '3600');"

            echo "Sending service ticket to $username..."
            nc -N $user_ip $PORT < encrypted_service_ticket.txt

        elif [[ "$line" == *"access_request"* ]]; then
            # Handle access to service
            echo "Access request received."

            # Extract the service ticket details
            username=$(echo "$line" | grep -oP '"username":"\K[^"]*')
            service_name=$(echo "$line" | grep -oP '"service_name":"\K[^"]*')
            decrypted_service_ticket=$(echo "$line" | grep -oP '"decrypted_service_ticket":"\K[^"]*')

            # Extract fields from decrypted service ticket
            ticket_id=$(echo "$decrypted_service_ticket" | grep -oP '"ticket_id":"\K[^"]*')
            ticket_username=$(echo "$decrypted_service_ticket" | grep -oP '"username":"\K[^"]*')
            ticket_service_name=$(echo "$decrypted_service_ticket" | grep -oP '"service_name":"\K[^"]*')

            # Validate the service ticket
            result=$(sqlite3 $DB_FILE "SELECT COUNT(*) FROM service_tickets WHERE ticket_id = '$ticket_id' AND service_name = '$ticket_service_name' AND username = '$ticket_username';")
            if [[ "$result" -eq 1 ]]; then
                echo "Access granted to service: $ticket_service_name for user: $ticket_username" | nc -N $user_ip $PORT
            else
                echo "Access denied. Invalid service ticket or user." | nc -N $user_ip $PORT
            fi
        fi
    done
done
