#!/usr/bin/env bash

# Path to the log file
LOG_FILE="/var/log/tailscale_watchdog.log"
# How often to check (in seconds)
CHECK_INTERVAL=60
# How many failed pings before restarting
FAILURE_THRESHOLD=3
# Ping timeout (in seconds)
PING_TIMEOUT=3

# --- Script Logic ---
failure_count=0

echo "$(date): Watchdog service started." >> $LOG_FILE

while true; do
    # Dynamically find the default gateway each time, in case it changes
    DEFAULT_GW=$(ip route show default | awk '/default/ {print $3}' | head -n 1)
    TIMESTAMP=$(date)

    if [ -z "$DEFAULT_GW" ]; then
        echo "$TIMESTAMP: Error - Could not determine default gateway. Sleeping for $CHECK_INTERVAL seconds." >> $LOG_FILE
        sleep $CHECK_INTERVAL
        continue # Skip the rest of this loop iteration
    fi

    # Check if the default gateway is reachable
    ping -c 1 -W $PING_TIMEOUT "$DEFAULT_GW" > /dev/null 2>&1

    if [ $? -ne 0 ]; then
        # Ping failed
        ((failure_count++))
        echo "$TIMESTAMP: Ping to default gateway $DEFAULT_GW failed ($failure_count/$FAILURE_THRESHOLD)." >> $LOG_FILE

        if [ $failure_count -ge $FAILURE_THRESHOLD ]; then
            echo "$TIMESTAMP: Failure threshold reached. Restarting tailscaled..." >> $LOG_FILE
            # Attempt to restart tailscaled
            if systemctl restart tailscaled; then
                echo "$TIMESTAMP: tailscaled restart command issued successfully." >> $LOG_FILE
                # Reset failure count after attempting restart
                failure_count=0
                # Optional: Add a longer delay after restart to allow stabilization
                sleep 30
            else
                echo "$TIMESTAMP: Error restarting tailscaled. Check systemd logs for details." >> $LOG_FILE
                # Keep failure count high to potentially retry later or indicate persistent issue
            fi
        fi
    else
        # Ping succeeded
        if [ $failure_count -gt 0 ]; then
            echo "$TIMESTAMP: Ping to default gateway $DEFAULT_GW succeeded. Resetting failure count." >> $LOG_FILE
        fi
        failure_count=0 # Reset counter on success

        # Optional: Check if tailscale0 is UP even if gateway is reachable
        if ! ip link show tailscale0 | grep -q "state UP"; then
             echo "$TIMESTAMP: Default gateway $DEFAULT_GW OK, but tailscale0 interface is DOWN or missing. Restarting tailscaled..." >> $LOG_FILE
             if systemctl restart tailscaled; then
                 echo "$TIMESTAMP: tailscaled restart command issued successfully (due to interface down)." >> $LOG_FILE
                 sleep 30
             else
                 echo "$TIMESTAMP: Error restarting tailscaled (due to interface down). Check systemd logs." >> $LOG_FILE
             fi
        fi
    fi

    # Wait before the next check
    sleep $CHECK_INTERVAL

done

