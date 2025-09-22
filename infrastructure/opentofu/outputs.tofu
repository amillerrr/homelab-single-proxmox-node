resource "local_file" "talos_machine_secrets" {
  content = yamlencode({
    cluster    = module.talos_cluster.machine_secrets.cluster
    secrets    = module.talos_cluster.machine_secrets.secrets
    trustdinfo = module.talos_cluster.machine_secrets.trustdinfo
    certs = {
      etcd = {
        crt = module.talos_cluster.machine_secrets.certs.etcd.cert
        key = module.talos_cluster.machine_secrets.certs.etcd.key
      }
      k8s = {
        crt = module.talos_cluster.machine_secrets.certs.k8s.cert
        key = module.talos_cluster.machine_secrets.certs.k8s.key
      }
      k8saggregator = {
        crt = module.talos_cluster.machine_secrets.certs.k8s_aggregator.cert
        key = module.talos_cluster.machine_secrets.certs.k8s_aggregator.key
      }
      k8sserviceaccount = {
        key = module.talos_cluster.machine_secrets.certs.k8s_serviceaccount.key
      }
      os = {
        crt = module.talos_cluster.machine_secrets.certs.os.cert
        key = module.talos_cluster.machine_secrets.certs.os.key
      }
    }
  })
  filename = "output/talos-machine-secrets.yaml"
}

resource "local_file" "talos_machine_configs" {
  for_each        = module.talos_cluster.machine_config
  content         = each.value.machine_configuration
  filename        = "output/talos-machine-config-${each.key}.yaml"
  file_permission = "0600"
}

resource "local_file" "talos_config" {
  content         = module.talos_cluster.client_configuration.talos_config
  filename        = "output/talos-config.yaml"
  file_permission = "0600"
}

resource "local_file" "kube_config" {
  content         = module.talos_cluster.kube_config.kubeconfig_raw
  filename        = "output/kube-config.yaml"
  file_permission = "0600"
}

output "kube_config" {
  value     = module.talos_cluster.kube_config.kubeconfig_raw
  sensitive = true
}

output "talos_config" {
  value     = module.talos_cluster.client_configuration.talos_config
  sensitive = true
}
