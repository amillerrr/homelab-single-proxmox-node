#!/bin/bash

VM_IDS="201 202 203 301 302 303"

echo "Connecting to ms proxmox node..."

ssh ms << EOF

  echo "--- Executing on Proxmox host ---"

  qm shutdown 201 --forceStop
  qm shutdown 202 --forceStop
  qm shutdown 203 --forceStop
  qm shutdown 301 --forceStop
  qm shutdown 302 --forceStop
  qm shutdown 303 --forceStop

  echo "--- All shutdown commands sent ---"

EOF

