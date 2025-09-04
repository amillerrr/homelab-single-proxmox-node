terraform {
  required_version = ">= 1.0"
  
  # Configure backend for state storage
  backend "s3" {
    bucket = "homelab-proxmox-statefile"
    key    = "single-node/k8s-cluster/terraform.tfstate"
    region = "us-west-2"
  }
}

# Control Plane Nodes
resource "proxmox_vm_qemu" "control_plane" {
  count = var.control_plane_count
  
  name        = "talos-cp-${format("%02d", count.index + 1)}"
  target_node = var.proxmox_node
  vmid        = var.control_plane_vmid_start + count.index
  
  clone = var.use_template ? var.template_name : null
  
  # iso         = "local:iso/nocloud-amd64.iso"
  
  cores   = var.control_plane_cores
  memory  = var.control_plane_memory
  scsihw  = "virtio-scsi-pci"
  boot    = "order=scsi0;ide2;net0"

  disks {
    scsi {
      scsi0 {
        disk {
          size     = var.control_plane_disk_size
          storage  = var.storage_pool
          iothread = true
        }
      }
    }
    ide {
      ide2 {
        cdrom {
          iso = "local:iso/nocloud-amd64.iso"
        }
      }
    }
  } 
  
  network {
    id = 1
    model    = "virtio"
    bridge   = var.network_bridge
    firewall = false
  }
  
  # Cloud-init settings for static IP
  ipconfig0 = "ip=${var.control_plane_ips[count.index]}/24,gw=${var.gateway}"
  
  # Enable QEMU agent
  agent = 1
  
  # CPU type
  cpu_type = "host"
  
  # Enable KVM
  kvm = true
  
  # Start on boot
  onboot = true
  
  # Enable hotplug
  hotplug = "network,disk,usb"
  
  lifecycle {
    ignore_changes = [
      network,
      disk,
    ]
  }
}

# Worker Nodes
resource "proxmox_vm_qemu" "worker" {
  count = var.worker_count
  
  name        = "talos-worker-${format("%02d", count.index + 1)}"
  target_node = var.proxmox_node
  vmid        = var.worker_vmid_start + count.index
  
  clone = var.use_template ? var.template_name : null
  
  cores   = var.worker_cores
  memory  = var.worker_memory
  scsihw  = "virtio-scsi-pci"
  boot    = "order=scsi0;ide2;net0"
  
  disks {
    scsi {
      scsi0 {
        disk {
          size     = var.control_plane_disk_size
          storage  = var.storage_pool
          iothread = true
        }
      }
    }
    ide {
      ide2 {
        cdrom {
          iso = "local:iso/nocloud-amd64.iso"
        }
      }
    }
  } 
  
  network {
    id = 1
    model    = "virtio"
    bridge   = var.network_bridge
    firewall = false
  }
  
  # Cloud-init settings for static IP
  ipconfig0 = "ip=${var.worker_ips[count.index]}/24,gw=${var.gateway}"
  
  # Enable QEMU agent
  agent = 1
  
  # CPU type
  cpu_type = "host"
  
  # Enable KVM
  kvm = true
  
  # Start on boot
  onboot = true
  
  # Enable hotplug
  hotplug = "network,disk,usb"
  
  lifecycle {
    ignore_changes = [
      network,
      disk,
    ]
  }
}

# Generate Talos machine configs
resource "terraform_data" "generate_configs" {
  provisioner "local-exec" {
    command = <<-EOT
      if [ ! -f ../talos/secrets/secrets.yaml ]; then
        mkdir -p ../talos/secrets
        talosctl gen secrets -o ../talos/secrets/secrets.yaml
      fi
      
      # Generate control plane configs
      %{ for idx, ip in var.control_plane_ips ~}
      talosctl gen config \
        --with-secrets ../talos/secrets/secrets.yaml \
        talos-k8s https://${var.cluster_vip}:6443 \
        --output ../talos/controlplane-${idx}.yaml \
        --output-types controlplane \
        --config-patch '[
          {
            "op": "add",
            "path": "/machine/network/interfaces",
            "value": [{
              "interface": "eth0",
              "addresses": ["${ip}/24"],
              "routes": [{"network": "0.0.0.0/0", "gateway": "${var.gateway}"}]
            }]
          },
          {
            "op": "add",
            "path": "/cluster/apiServer/certSANs",
            "value": ["${var.cluster_vip}"]
          },
          {
            "op": "add",
            "path": "/cluster/controlPlane/endpoint",
            "value": "https://${var.cluster_vip}:6443"
          }
        ]'
      %{ endfor ~}
      
      # Generate worker configs
      %{ for idx, ip in var.worker_ips ~}
      talosctl gen config \
        --with-secrets ../talos/secrets/secrets.yaml \
        talos-k8s https://${var.cluster_vip}:6443 \
        --output ../talos/worker-${idx}.yaml \
        --output-types worker \
        --config-patch '[
          {
            "op": "add",
            "path": "/machine/network/interfaces",
            "value": [{
              "interface": "eth0",
              "addresses": ["${ip}/24"],
              "routes": [{"network": "0.0.0.0/0", "gateway": "${var.gateway}"}]
            }]
          },
          {
            "op": "add",
            "path": "/machine/kubelet/extraArgs",
            "value": {"rotate-server-certificates": "true"}
          },
          {
            "op": "add",
            "path": "/machine/sysctls",
            "value": {
              "net.core.bpf_jit_enable": "1",
              "net.ipv4.conf.all.rp_filter": "0",
              "net.ipv4.ip_forward": "1",
              "net.ipv6.conf.all.forwarding": "1"
            }
          },
          {
            "op": "add",
            "path": "/machine/kernel",
            "value": {
              "modules": [
                {"name": "br_netfilter"},
                {"name": "overlay"},
                {"name": "ip_tables"},
                {"name": "iptable_nat"},
                {"name": "iptable_filter"},
                {"name": "iptable_mangle"}
              ]
            }
          },
          {
            "op": "add",
            "path": "/cluster/proxy",
            "value": {"disabled": true}
          },
          {
            "op": "add",
            "path": "/cluster/network",
            "value": {
              "podSubnets": ["10.244.0.0/16"],
              "serviceSubnets": ["10.96.0.0/12"]
            }
          }
        ]'
      %{ endfor ~}
    EOT
  }
  
  depends_on = [
    proxmox_vm_qemu.control_plane,
    proxmox_vm_qemu.worker
  ]
}

# Wait for VMs to be ready
resource "time_sleep" "wait_for_vms" {
  depends_on = [
    proxmox_vm_qemu.control_plane,
    proxmox_vm_qemu.worker
  ]
  
  create_duration = "30s"
}

# Apply Talos configs
resource "terraform_data" "apply_configs" {
  count = var.control_plane_count + var.worker_count

  provisioner "local-exec" {
    command = <<-EOT
      # Determine if this is a control plane or worker node
      if [ ${count.index} -lt ${var.control_plane_count} ]; then
        # This is a control plane node. Terraform interpolates these values.
        NODE_IP="${var.control_plane_ips[count.index]}"
        CONFIG_FILE="../talos/controlplane-${count.index}.yaml"
      else
        # This is a worker node. Terraform also interpolates these.
        NODE_IP="${var.worker_ips[count.index - var.control_plane_count]}"
        CONFIG_FILE="../talos/worker-${count.index - var.control_plane_count}.yaml"
      fi

      # Wait for node to be reachable.
      # These variables are used by the shell, so they MUST be escaped with $$.
      echo "Waiting for node $${NODE_IP} to be reachable..."
      until nc -zv $${NODE_IP} 50000 2>/dev/null; do
        echo "Waiting for Talos API on $${NODE_IP}..."
        sleep 5
      done

      # Apply the configuration.
      # These variables also need to be escaped.
      talosctl apply-config --insecure --nodes $${NODE_IP} --file $${CONFIG_FILE}
    EOT
  }

  depends_on = [
    terraform_data.generate_configs,
    time_sleep.wait_for_vms
  ]
}
resource "terraform_data" "apply_control_plane_configs" {
  count = var.control_plane_count

  provisioner "local-exec" {
    command = <<-EOT
      NODE_IP="${var.control_plane_ips[count.index]}"
      CONFIG_FILE="../talos/controlplane-${count.index}.yaml"
      
      echo "Waiting for node $${NODE_IP} to be reachable..."
      until nc -zv $${NODE_IP} 50000 2>/dev/null; do
        echo "Waiting for Talos API on $${NODE_IP}..."
        sleep 5
      done
      
      talosctl apply-config --insecure --nodes $${NODE_IP} --file $${CONFIG_FILE}
    EOT
  }
  
  depends_on = [
    terraform_data.generate_configs,
    time_sleep.wait_for_vms
  ]
}

resource "terraform_data" "apply_worker_configs" {
  count = var.worker_count

  provisioner "local-exec" {
    command = <<-EOT
      NODE_IP="${var.worker_ips[count.index]}"
      CONFIG_FILE="../talos/worker-${count.index}.yaml"
      
      echo "Waiting for node $${NODE_IP} to be reachable..."
      until nc -zv $${NODE_IP} 50000 2>/dev/null; do
        echo "Waiting for Talos API on $${NODE_IP}..."
        sleep 5
      done
      
      talosctl apply-config --insecure --nodes $${NODE_IP} --file $${CONFIG_FILE}
    EOT
  }
  
  depends_on = [
    terraform_data.generate_configs,
    time_sleep.wait_for_vms
  ]
}

# Bootstrap the cluster
resource "terraform_data" "bootstrap_cluster" {
  provisioner "local-exec" {
    command = <<-EOT
      # Wait for all configs to be applied
      sleep 30
      
      # Bootstrap on the first control plane node
      export TALOSCONFIG=../talos/talosconfig
      talosctl config endpoint ${var.control_plane_ips[0]}
      talosctl config node ${var.control_plane_ips[0]}
      
      echo "Bootstrapping Kubernetes cluster..."
      talosctl bootstrap
      
      # Wait for cluster to be ready
      echo "Waiting for cluster to be ready..."
      talosctl health --wait-timeout 10m
      
      # Get kubeconfig
      talosctl kubeconfig -f
      
      echo "Cluster bootstrapped successfully!"
    EOT
  }
  
  depends_on = [
    terraform_data.apply_control_plane_configs,
    terraform_data.apply_worker_configs
  ]
}
