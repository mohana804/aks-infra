module "aks" {
  source              = "./modules/aks"
  project             = var.project
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  kubernetes_version  = var.kubernetes_version
  system_node_count   = var.system_node_count
  user_node_count     = var.user_node_count
  log_analytics_id    = azurerm_log_analytics_workspace.law.id
}

locals {
  tags = {
    project = var.project
    env     = var.resource_group_name
    owner   = "platform"
  }
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

# VNet & subnets
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-aks"
  address_space       = var.address_space
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.aks_subnet_cidr]
}

resource "azurerm_subnet" "bastion" {
  name                 = "snet-bastion"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.bastion_subnet_cidr]
}

# NSGs
resource "azurerm_network_security_group" "aks" {
  name                = "nsg-aks"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  security_rule {
    name                       = "deny-inbound-all"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  tags = local.tags
}

resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

resource "azurerm_network_security_group" "bastion" {
  name                = "nsg-bastion"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  security_rule {
    name                       = "ssh-allow-admin"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.admin_ssh_ip_allow
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "deny-rest"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  tags = local.tags
}

resource "azurerm_subnet_network_security_group_association" "bastion" {
  subnet_id                 = azurerm_subnet.bastion.id
  network_security_group_id = azurerm_network_security_group.bastion.id
}

# Public IP & NIC for jumpbox
resource "azurerm_public_ip" "jump" {
  name                = "pip-jumpbox"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_network_interface" "jump" {
  name                = "nic-jumpbox"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.bastion.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.jump.id
  }
  tags = local.tags
}

resource "azurerm_linux_virtual_machine" "jump" {
  name                = "vm-jumpbox"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  size                = "Standard_B2s"
  admin_username      = "azureuser"
  network_interface_ids = [ azurerm_network_interface.jump.id ]
  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/id_rsa.pub") # TODO: or variable
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  disable_password_authentication = true
  tags = local.tags
}

# Log Analytics
resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.project}-law"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.tags
}

# ACR
resource "azurerm_container_registry" "acr" {
  name                = replace(lower("${var.project}acr"), "-", "")
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = var.acr_sku
  admin_enabled       = false
  tags                = local.tags
}

# NAT Gateway for outbound
resource "azurerm_public_ip" "nat" {
  name                = "pip-natgw"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway" "this" {
  name                = "ngw-aks"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku_name            = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "this" {
  subnet_id      = azurerm_subnet.aks.id
  nat_gateway_id = azurerm_nat_gateway.this.id
}

# Private DNS zone for AKS API
resource "azurerm_private_dns_zone" "aks" {
  name                = "privatelink.${var.location}.azmk8s.io"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "aks" {
  name                  = "dnslink-aks"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.aks.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

# AKS cluster (private, RBAC, 2 node pools)
resource "azurerm_kubernetes_cluster" "this" {
  name                = "${var.project}-aks"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix_private_cluster = "${var.project}-priv"

  kubernetes_version = var.kubernetes_version

  default_node_pool {
    name                = "system"
    vm_size             = "Standard_B2s"
    node_count          = var.system_node_count
    type                = "VirtualMachineScaleSets"
    orchestrator_version = var.kubernetes_version
    max_pods            = 30
    only_critical_addons_enabled = true
    vnet_subnet_id      = azurerm_subnet.aks.id
    node_labels = {
      "kubernetes.azure.com/mode" = "system"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
    outbound_type     = "userAssignedNATGateway"
    nat_gateway_profile {
      managed_outbound_ip_count = 1
    }
  }

  api_server_access_profile {
    enable_private_cluster = true
    private_dns_zone_id    = azurerm_private_dns_zone.aks.id
  }

  role_based_access_control_enabled = true

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  }

  tags = local.tags
}

# User node pool
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "usernp"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = "Standard_B2s"
  node_count            = var.user_node_count
  orchestrator_version  = var.kubernetes_version
  vnet_subnet_id        = azurerm_subnet.aks.id
  mode                  = "User"
  max_pods              = 30
  node_labels = {
    "workload" = "user"
  }
  node_taints = [
    "workload=user:NoSchedule"
  ]
}

# Allow AKS to pull from ACR
resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}
