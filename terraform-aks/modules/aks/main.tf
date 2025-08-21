# optional module placeholder
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.project}-aks"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "${var.project}-dns"

  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name       = "systempool"
    node_count = var.system_node_count
    vm_size    = "Standard_B2s"
    mode       = "System"
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    dns_service_ip    = "10.20.0.10"
    service_cidr      = "10.20.0.0/16"
    docker_bridge_cidr = "172.17.0.1/16"
    outbound_type     = "userAssignedNATGateway"
  }

  oms_agent {
    log_analytics_workspace_id = var.log_analytics_id
  }

  role_based_access_control_enabled = true

  depends_on = [azurerm_log_analytics_workspace.law]
}

# User node pool
resource "azurerm_kubernetes_cluster_node_pool" "userpool" {
  name                  = "userpool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = "Standard_B2s"
  node_count            = var.user_node_count
  mode                  = "User"

  node_labels = {
    workload = "user"
  }

  node_taints = ["CriticalAddonsOnly=true:NoSchedule"]
}
