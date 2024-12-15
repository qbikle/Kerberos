#!/bin/bash

DB_FILE="server_data.db"

# Check if the database exists
if [[ ! -f $DB_FILE ]]; then
    echo "Database not found. Creating a new one..."
    sqlite3 $DB_FILE "CREATE TABLE users (username TEXT PRIMARY KEY, secret_key TEXT);"
fi

# Function to hash the password to generate a client secret
generate_secret() {
    local password=$1
    echo -n "$password" | openssl dgst -sha256 | awk '{print $2}'
}

# Function to add a new user
add_user() {
    read -p "Enter username: " username
    read -s -p "Enter password: " password
    echo
    read -s -p "Confirm password: " password_confirm
    echo

    # Verify passwords match
    if [[ "$password" != "$password_confirm" ]]; then
        echo "Error: Passwords do not match."
        return
    fi

    # Generate the secret key from the password
    local secret_key
    secret_key=$(generate_secret "$password")

    # Add the user to the database
    sqlite3 $DB_FILE "INSERT INTO users (username, secret_key) VALUES ('$username', '$secret_key');" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        echo "User '$username' added successfully."
    else
        echo "Error: User '$username' already exists or failed to add."
    fi
}

# Function to delete a user
delete_user() {
    read -p "Enter username to delete: " username

    # Check if the user exists
    local secret_key
    secret_key=$(sqlite3 $DB_FILE "SELECT secret_key FROM users WHERE username = '$username';")

    if [[ -z $secret_key ]]; then
        echo "Error: User '$username' not found."
        return
    fi

    # Delete the user from the database
    sqlite3 $DB_FILE "DELETE FROM users WHERE username = '$username';"

    if [[ $? -eq 0 ]]; then
        echo "User '$username' deleted successfully."
    else
        echo "Error: User '$username' not found or failed to delete."
    fi
}

# Function to check the database
check_database() {
    echo "Database Contents:"
    sqlite3 $DB_FILE "SELECT * FROM users;" | column -t -s '|'
}

# Admin menu
while true; do
    echo "------------------------------------------------"
    echo "Admin Menu"
    echo "1. Add User"
    echo "2. Delete User"
    echo "3. Check Database"
    echo "4. Exit"
    echo "------------------------------------------------"
    read -p "Choose an option: " choice
    echo "------------------------------------------------"

    case $choice in
        1) add_user ;;
        2) delete_user ;;
        3) check_database ;;
        4) echo "Exiting..."; break ;;
        *) echo "Invalid option. Please try again." ;;
    esac
done
