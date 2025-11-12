#!/bin/bash

# This list is now used to drive the loop
VM_IDS="201 202 203 301 302 303"

echo "Connecting to ms proxmox node to send parallel, non-blocking shutdown commands..."

# We execute the remote commands using the default remote shell
ssh ms << EOF

  echo "--- Executing on Proxmox host 'ms' ---"

  # The $VM_IDS variable is expanded by your *local* shell
  # *before* the script block is sent to the remote host.
  for VM in $VM_IDS; do
  
    # We must escape \$VM so it is interpreted by the *remote* shell inside the loop.
    echo "Issuing background shutdown for VM \$VM..."
    
    # Use 'nohup' to make the command immune to hangups (SIGHUP)
    # Use '&' to run it in the background.
    # Redirect stdout/stderr to /dev/null to prevent a 'nohup.out' file
    # from being created for every command.
    nohup qm shutdown \$VM --forceStop > /dev/null 2>&1 &
    
  done

  echo "--- All shutdown commands have been sent to the background. SSH session closing. ---"
EOF

echo "Local script finished. Shutdowns are running independently on 'ms'."
