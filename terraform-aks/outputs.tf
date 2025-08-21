output "resource_group" { value = azurerm_resource_group.this.name }
output "aks_name"       { value = azurerm_kubernetes_cluster.this.name }
output "acr_name"       { value = azurerm_container_registry.acr.name }
output "law_id"         { value = azurerm_log_analytics_workspace.this.id }
output "jumpbox_public_ip" { value = azurerm_public_ip.jump.ip_address }
