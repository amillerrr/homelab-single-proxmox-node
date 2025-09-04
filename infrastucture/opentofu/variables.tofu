# Proxmox Connection
variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
  default     = "https://10.0.10.10:8006/api2/json"
}

variable "proxmox_tls_insecure" {
  description = "Disable TLS verification (not recommended for production)"
  type        = bool
  default     = true
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "ms"
}

variable "proxmox_host" {
  description = "Proxmox host IP or hostname for SSH"
  type        = string
  default     = "10.0.10.10"
}

# Talos Configuration
variable "talos_version" {
  description = "Talos Linux version"
  type        = string
  default     = "1.11.0"
}

variable "cluster_name" {
  description = "Kubernetes cluster name"
  type        = string
  default     = "talos-k8s"
}

variable "cluster_vip" {
  description = "Virtual IP for Kubernetes API (HA)"
  type        = string
  default     = "10.0.10.250"
}

# Network Configuration
variable "network_bridge" {
  description = "Proxmox network bridge"
  type        = string
  default     = "vmbr0"
}

variable "gateway" {
  description = "Network gateway"
  type        = string
  default     = "10.0.10.1"
}

variable "dns_servers" {
  description = "DNS servers"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "domain" {
  description = "Domain name"
  type        = string
  default     = "local"
}

# Control Plane Configuration
variable "control_plane_count" {
  description = "Number of control plane nodes"
  type        = number
  default     = 3
}

variable "control_plane_cores" {
  description = "Number of CPU cores for control plane nodes"
  type        = number
  default     = 2
}

variable "control_plane_memory" {
  description = "Memory in MB for control plane nodes"
  type        = number
  default     = 8192
}

variable "control_plane_disk_size" {
  description = "Disk size for control plane nodes"
  type        = string
  default     = "100G"
}

variable "control_plane_ips" {
  description = "Static IPs for control plane nodes"
  type        = list(string)
  default     = [
    "10.0.10.210",
    "10.0.10.211",
    "10.0.10.212"
  ]
}

variable "control_plane_vmid_start" {
  description = "Starting VM ID for control plane nodes"
  type        = number
  default     = 200
}

# Worker Configuration
variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 3
}

variable "worker_cores" {
  description = "Number of CPU cores for worker nodes"
  type        = number
  default     = 2
}

variable "worker_memory" {
  description = "Memory in MB for worker nodes"
  type        = number
  default     = 8192
}

variable "worker_disk_size" {
  description = "Disk size for worker nodes"
  type        = string
  default     = "100G"
}

variable "worker_ips" {
  description = "Static IPs for worker nodes"
  type        = list(string)
  default     = [
    "10.0.10.220",
    "10.0.10.221",
    "10.0.10.222"
  ]
}

variable "worker_vmid_start" {
  description = "Starting VM ID for worker nodes"
  type        = number
  default     = 300
}

# Storage Configuration
variable "storage_pool" {
  description = "Proxmox storage pool for VM disks"
  type        = string
  default     = "local-lvm"
}

# Template Configuration (Optional)
variable "use_template" {
  description = "Use a VM template instead of ISO"
  type        = bool
  default     = false
}

variable "template_name" {
  description = "Name of the VM template to clone from"
  type        = string
  default     = ""
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "production"
    ManagedBy   = "OpenTofu"
    OS          = "TalosLinux"
    Cluster     = "talos-k8s"
  }
}

# Timeouts
variable "vm_timeout" {
  description = "Timeout for VM operations"
  type        = string
  default     = "10m"
}

variable "bootstrap_timeout" {
  description = "Timeout for cluster bootstrap"
  type        = string
  default     = "20m"
}
