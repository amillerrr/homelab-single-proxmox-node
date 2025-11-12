#!/bin/bash

VM_IDS="201 202 203 301 302 303"

echo "Connecting to ms proxmox node..."

ssh ms << EOF

  echo "--- Executing on Proxmox host ---"

  for vmid in $VM_IDS; do
    echo "Sending graceful shutdown to VM \$vmid..."
    qm shutdown $vmid
  done

  echo "--- All shutdown commands sent ---"

EOF

