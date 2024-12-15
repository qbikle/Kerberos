#!/bin/bash

SERVER_IP="0.0.0.0"
PORT=9090

# Authentication message
get_tgt() {
    username=$(whoami)
    read -p "Enter service name: " service_name
    user_ip=$(hostname -I | awk '{print $1}')
    ticket_life="3600"
    auth_message="{\"request_type\":\"auth_request\",\"username\":\"$username\",\"service_name\":\"$service_name\",\"user_ip\":\"$user_ip\",\"ticket_life\":\"$ticket_life\"}"

    # Prompt for the password
    read -s -p "Enter password: " password
    echo

    # Generate the secret key from the password
    SECRET_KEY=$(echo -n "$password" | openssl dgst -sha256 | awk '{print $2}')

    echo "Sending authentication request..."
    echo "$auth_message" | nc -w 0 $SERVER_IP $PORT > encrypted_ticket.txt

    echo "Waiting for TGT..."
    nc -w 3 -l -p $PORT > encrypted_ticket.txt

    echo "TGT received. Decrypting..."
    TGT=$(openssl enc -d -aes-256-cbc -pbkdf2 -pass pass:"$SECRET_KEY" < encrypted_ticket.txt)
    echo "Received TGT: $TGT"
}

# Function to request a service ticket
get_service_ticket() {
    if [[ ! -f encrypted_ticket.txt ]]; then
        echo "No TGT found. Please authenticate first."
        return
    fi

    # Request service ticket
    username=$(whoami)
    
    # ask user for password
    read -s -p "Enter password: " password

    SECRET_KEY=$(echo -n "$password" | openssl dgst -sha256 | awk '{print $2}')

    decrypted_tgt=$(openssl enc -d -aes-256-cbc -pbkdf2 -pass pass:"$SECRET_KEY" < encrypted_ticket.txt)

    read -p "Enter service name: " service_name
    # service_request="{\"request_type\":\"service_request\",\"encrypted_tgt\":\"$encrypted_tgt\",\"username\":\"$username\",\"service_name\":\"$service_name\"}"
    
    # send the decrypted tgt
    service_request="{\"request_type\":\"service_request\",\"decrypted_tgt\":\"$decrypted_tgt\",\"username\":\"$username\",\"service_name\":\"$service_name\"}"

    echo "Service Request: $service_request"

    echo "Requesting service ticket..."
    echo "$service_request" | nc -w 0 $SERVER_IP $PORT

    echo "Waiting for service ticket..."
    nc -w 3 -l -p $PORT > encrypted_service_ticket.txt
    sleep 4

    echo "Service ticket received. Decrypting..."
    service_ticket=$(openssl enc -d -aes-256-cbc -pbkdf2 -pass pass:"$service_name" < encrypted_service_ticket.txt)
    echo "Received Service Ticket: $service_ticket"
}


# Function to access the service
access_service() {
    # Check if encrypted service ticket exists
    if [[ ! -f encrypted_service_ticket.txt ]]; then
        echo "No service ticket found. Please request a service ticket first."
        return
    fi


    read -p "Enter service name: " service_name

    # Decrypt the service ticket
    service_ticket=$(openssl enc -d -aes-256-cbc -pbkdf2 -pass pass:"$service_name" < encrypted_service_ticket.txt)

    service_access="{\"request_type\":\"access_request\",\"service_ticket\":\"$service_ticket\"}"

    echo "Requesting access to service..."
    echo "$service_access" | nc -w 0 $SERVER_IP $PORT

    echo "Waiting for service access response..."
    RESPONSE=$(nc -w 3 -l -p $PORT)
    echo "Server Response: $RESPONSE"
}

# Main menu
while true; do
    echo "---------------------------"
    echo "1. Authenticate and Get TGT"
    echo "2. Request Service Ticket"
    echo "3. Access Service"
    echo "4. Exit"
    echo "---------------------------"
    read -p "Choose an option: " choice

    case $choice in
        1)
            get_tgt
            ;;
        2)
            get_service_ticket
            ;;
        3)
            access_service
            ;;
        4)
            echo "Exiting."
            break
            ;;
        *)
            echo "Invalid choice. Please try again."
            ;;
    esac
done
