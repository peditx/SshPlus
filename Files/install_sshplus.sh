#!/bin/bash

CONFIG_FILE="/etc/sshplus.conf"
SERVICE_FILE="/etc/init.d/sshplus"
BINARY_FILE="/usr/bin/sshplus"

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script as root."
    exit 1
fi

# Install dependencies
echo "Updating package lists and installing required packages..."
opkg update && opkg install sshpass whiptail

# Get SSH configuration from user
echo "Enter SSH Host:"
read -r SSH_HOST
echo "Enter SSH Username:"
read -r SSH_USER
echo "Enter SSH Password:"
read -r -s SSH_PASS
echo "Enter SSH Port (default: 22):"
read -r SSH_PORT
SSH_PORT=${SSH_PORT:-22}

# Save configuration
cat <<EOF > "$CONFIG_FILE"
SSH_HOST="$SSH_HOST"
SSH_USER="$SSH_USER"
SSH_PASS="$SSH_PASS"
SSH_PORT="$SSH_PORT"
EOF

echo "Configuration saved to $CONFIG_FILE"

# Create service to start SSH on boot
cat <<'EOF' > "$SERVICE_FILE"
#!/bin/sh /etc/rc.common
START=99
STOP=1

start() {
    source /etc/sshplus.conf
    sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -N -D 8089 "$SSH_USER@$SSH_HOST" -p "$SSH_PORT" &
}

stop() {
    pkill -f "sshpass -p"
}

EOF

chmod +x "$SERVICE_FILE"
/etc/init.d/sshplus enable
/etc/init.d/sshplus start

# Create the SSHPlus management script
cat <<'EOF' > "$BINARY_FILE"
#!/bin/bash

CONFIG_FILE="/etc/sshplus.conf"
SERVICE_FILE="/etc/init.d/sshplus"

menu() {
    OPTION=$(whiptail --title "PeDitX OS SshPlus on passwall" --menu "Choose an option" 15 50 3 \
        "1" "Edit SSH Config" \
        "2" "Start SSH Service" \
        "3" "Stop SSH Service" 3>&1 1>&2 2>&3)

    case $OPTION in
        1)
            edit_config
            ;;
        2)
            start_service
            ;;
        3)
            stop_service
            ;;
    esac
}

edit_config() {
    SSH_HOST=$(whiptail --title "PeDitX OS SshPlus on passwall" --inputbox "Enter SSH Host:" 10 50 3>&1 1>&2 2>&3)
    SSH_USER=$(whiptail --title "PeDitX OS SshPlus on passwall" --inputbox "Enter SSH Username:" 10 50 3>&1 1>&2 2>&3)
    SSH_PASS=$(whiptail --title "PeDitX OS SshPlus on passwall" --passwordbox "Enter SSH Password:" 10 50 3>&1 1>&2 2>&3)
    SSH_PORT=$(whiptail --title "PeDitX OS SshPlus on passwall" --inputbox "Enter SSH Port (default: 22):" 10 50 3>&1 1>&2 2>&3)

    [ -z "$SSH_PORT" ] && SSH_PORT="22"

    cat <<EOF > "$CONFIG_FILE"
SSH_HOST="$SSH_HOST"
SSH_USER="$SSH_USER"
SSH_PASS="$SSH_PASS"
SSH_PORT="$SSH_PORT"
EOF

    whiptail --title "PeDitX OS SshPlus on passwall" --msgbox "Configuration updated successfully!" 10 40
}

start_service() {
    /etc/init.d/sshplus start
    whiptail --title "PeDitX OS SshPlus on passwall" --msgbox "SSH Service started successfully!" 10 40
}

stop_service() {
    /etc/init.d/sshplus stop
    whiptail --title "PeDitX OS SshPlus on passwall" --msgbox "SSH Service stopped successfully!" 10 40
}

menu
EOF

chmod +x "$BINARY_FILE"

echo "Installation complete! Run 'sshplus' to manage your SSH proxy."
