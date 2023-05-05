#!/usr/bin/env bash

# Define output colors
Green_font_prefix="\033[32m"
Red_font_prefix="\033[31m"
Green_background_prefix="\033[42;37m"
Red_background_prefix="\033[41;37m"
Font_color_suffix="\033[0m"

# Define log file paths
LOG_FILE='/tmp/ngrok.log'
TELEGRAM_LOG="/tmp/telegram.log"

# Define continue file path
CONTINUE_FILE="/tmp/continue"

# Check if NGROK_TOKEN environment variable is set
if [[ -z "${NGROK_TOKEN}" ]]; then
    echo -e "${ERROR} Please set 'NGROK_TOKEN' environment variable."
    exit 2
fi

# Check if SSH_PASSWORD or SSH_PUBKEY or GH_SSH_PUBKEY environment variable is set
if [[ -z "${SSH_PASSWORD}" && -z "${SSH_PUBKEY}" && -z "${GH_SSH_PUBKEY}" ]]; then
    echo -e "${ERROR} Please set 'SSH_PASSWORD' environment variable."
    exit 3
fi

# Install ngrok based on the OS type
if [[ -n "$(uname | grep -i Linux)" ]]; then
    echo -e "${INFO} Installing ngrok ..."
    curl -fsSL https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-amd64.zip -o ngrok.zip
    unzip ngrok.zip ngrok
    rm ngrok.zip
    chmod +x ngrok
    sudo mv ngrok /usr/local/bin
    ngrok -v
elif [[ -n "$(uname | grep -i Darwin)" ]]; then
    echo -e "${INFO} Installing ngrok ..."
    curl -fsSL https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-darwin-amd64.zip -o ngrok.zip
    unzip ngrok.zip ngrok
    rm ngrok.zip
    chmod +x ngrok
    sudo mv ngrok /usr/local/bin
    ngrok -v
    USER=root
    echo -e "${INFO} Setting up SSH service ..."
    echo 'PermitRootLogin yes' | sudo tee -a /etc/ssh/sshd_config >/dev/null
    sudo launchctl unload /System/Library/LaunchDaemons/ssh.plist
    sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist
else
    echo -e "${ERROR} This system is not supported!"
    exit 1
fi

# Set user password if SSH_PASSWORD environment variable is set
if [[ -n "${SSH_PASSWORD}" ]]; then
    echo -e "${INFO} Setting user(${USER}) password ..."
    echo -e "${SSH_PASSWORD}\n${SSH_PASSWORD}" | sudo passwd "${USER}"
fi

# Start ngrok proxy for SSH and VNC ports
echo -e "${INFO} Starting ngrok proxy for SSH and VNC ports ..."
screen -dmS ngrok bash -c "ngrok tcp 22 --log ${LOG_FILE} --authtoken ${NGROK_TOKEN} --region ${NGROK_REGION:-us} && \
                           ngrok tcp 5900 --log ${LOG_FILE} --authtoken ${NGROK_TOKEN} --region ${NGROK_REGION:-us}"

# Wait for ngrok to start
SECONDS_LEFT=10
while ((${SECONDS_LEFT} > 0)); do
    echo -e "${INFO} Waiting ${SECONDS_LEFT}s for ngrok to start ..."
    sleep 1
    SECONDS_LEFT=$((${SECONDS_LEFT} - 1))
done

# Check if ngrok started successfully
ERRORS_LOG=$(grep "command failed" ${LOG_FILE})
if [[ -e "${LOG_FILE}" && -z "${ERRORS_LOG}" ]]; then
    SSH_CMD="$(grep -oE "tcp://(.+)" ${LOG_FILE} | sed "s/tcp:\/\//ssh ${USER}@/" | sed "s/:/ -p /")"
    VNC_URL="$(grep -oE "tcp://(.+)" ${LOG_FILE} | sed "s/tcp:\/\//vnc:\/\/$(hostname -I | awk '{print $1}'):/" | sed "s/:/=/" | awk '{ print $1 ":5900?" $2 }')"

    # Prepare message for output
    MSG="*GitHub Actions - ngrok session info:*\n\n⚡ *CLI:* \`${SSH_CMD}\`\n💻 *VNC URL:* \`${VNC_URL}\`\n\n🔔 *TIPS:* Run \`touch ${CONTINUE_FILE}\` to continue to the next step."

    # Send message via Telegram if TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID environment variables are set
    if [[ -n "${TELEGRAM_BOT_TOKEN}" && -n "${TELEGRAM_CHAT_ID}" ]]; then
        echo -e "${INFO} Sending message via Telegram ..."
        curl -sSX POST https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage \
            -d chat_id="${TELEGRAM_CHAT_ID}" \
            -d parse_mode="MarkdownV2" \
            -d text="$(echo -e "${MSG}")" >${TELEGRAM_LOG} 2>&1
        TELEGRAM_STATUS=$(cat ${TELEGRAM_LOG} | jq -r .ok)
        if [[ "${TELEGRAM_STATUS}" != 'true' ]]; then
            echo -e "${ERROR} Telegram message sending failed: $(cat ${TELEGRAM_LOG})"
        else
            echo -e "${INFO} Telegram message sent successfully!"
        fi
    fi

    # Output SSH and VNC URLs to console
    echo -e "${Green_font_prefix}To connect to this session, copy and paste the following into a terminal:${Font_color_suffix}\n\n${SSH_CMD}\n\n${VNC_URL}\n\n${Green_background_prefix}TIPS:${Font_color_suffix} Run 'touch ${CONTINUE_FILE}' to continue to the next step."
else
    # Output error message if ngrok failed to start
    echo -e "${ERROR} Failed to start ngrok proxy: $(cat ${LOG_FILE})"
fi

# Blocking loop to wait for user input to continue to the next step
while [[ -n $(ps aux | grep ngrok) ]]; do
    sleep 1
    if [[ -e ${CONTINUE_FILE} ]]; then
        echo -e "${INFO} Continuing to the next step ..."
        exit 0
    fi
done

# Output error message if ngrok stopped unexpectedly
echo "${ERROR} Ngrok stopped unexpectedly."
