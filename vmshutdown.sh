#!/bin/bash

echo "Connecting to ms proxmox node to send parallel, non-blocking shutdown commands..."

# We execute the remote commands using the default remote shell
ssh ms << EOF

  echo "--- Executing on Proxmox host 'ms' ---"

  nohup qm shutdown 201 --skiplock --forceStop > /dev/null 2>&1 &
  nohup qm shutdown 202 --skiplock --forceStop > /dev/null 2>&1 &
  nohup qm shutdown 203 --skiplock --forceStop > /dev/null 2>&1 &
  nohup qm shutdown 301 --skiplock --forceStop > /dev/null 2>&1 &
  nohup qm shutdown 302 --skiplock --forceStop > /dev/null 2>&1 &
  nohup qm shutdown 303 --skiplock --forceStop > /dev/null 2>&1 &

  echo "--- All shutdown commands have been sent to the background. SSH session closing. ---"
EOF

echo "Local script finished. Shutdowns are running independently on 'ms'."
