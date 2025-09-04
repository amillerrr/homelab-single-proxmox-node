output "control_plane_ips" {
  description = "IP addresses of control plane nodes"
  value       = var.control_plane_ips
}

output "worker_ips" {
  description = "IP addresses of worker nodes"
  value       = var.worker_ips
}

output "cluster_vip" {
  description = "Virtual IP for Kubernetes API"
  value       = var.cluster_vip
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = "https://${var.cluster_vip}:6443"
}

output "talos_config_path" {
  description = "Path to Talos configuration file"
  value       = "../talos/talosconfig"
}

output "vm_ids" {
  description = "VM IDs created"
  value = {
    control_plane = [for vm in proxmox_vm_qemu.control_plane : vm.vmid]
    workers       = [for vm in proxmox_vm_qemu.worker : vm.vmid]
  }
}

output "cluster_info" {
  description = "Cluster information summary"
  value = {
    name              = var.cluster_name
    control_plane_count = var.control_plane_count
    worker_count      = var.worker_count
    total_nodes       = var.control_plane_count + var.worker_count
    talos_version     = var.talos_version
  }
}

output "next_steps" {
  description = "Next steps after deployment"
  value = <<-EOT
    Cluster deployed with Cilium CNI! Next steps:
    
    1. Export Talos config:
       export TALOSCONFIG=${abspath("../talos/talosconfig")}
    
    2. Check cluster health:
       talosctl health --nodes ${join(",", var.control_plane_ips)}
    
    3. Verify Cilium CNI:
       cilium status
       kubectl get pods -n kube-system | grep cilium
    
    4. Get kubeconfig:
       talosctl kubeconfig
    
    5. Check nodes:
       kubectl get nodes
    
    6. Install GitOps (ArgoCD):
       ./scripts/setup-argocd.sh
    
    7. Setup Sealed Secrets:
       ./scripts/manage-sealed-secrets.sh install
  EOT
}
