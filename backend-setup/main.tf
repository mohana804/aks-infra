terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.113.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.1"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "location" { type = string }
variable "project"  { type = string }

resource "azurerm_resource_group" "tf" {
  name     = "${var.project}-tfstate-rg"
  location = var.location
}

resource "random_string" "sa" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_storage_account" "tf" {
  name                     = "tf${random_string.sa.result}state"
  resource_group_name      = azurerm_resource_group.tf.name
  location                 = azurerm_resource_group.tf.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
}

resource "azurerm_storage_container" "tf" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.tf.name
  container_access_type = "private"
}

output "backend_resource_group" { value = azurerm_resource_group.tf.name }
output "backend_storage_account" { value = azurerm_storage_account.tf.name }
output "backend_container" { value = azurerm_storage_container.tf.name }
