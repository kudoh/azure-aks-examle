terraform {
  backend "azurerm" {
    resource_group_name   = "terraform_state"
    storage_account_name  = "terraform0905"
    container_name        = "tfstate"
    key                   = "dev.tfstate"
  }
}

provider "azurerm" {
}

provider "random" {
}

resource "azurerm_resource_group" "dev" {
  name = "dev"
  location = "${var.location}"
  tags = {
    env = "dev"
  }
}

resource "azurerm_virtual_network" "dev" {
  name                = "k8s_vnet"
  resource_group_name = "${azurerm_resource_group.dev.name}"
  location            = "${azurerm_resource_group.dev.location}"
  address_space       = ["10.100.0.0/16"]
}

resource "azurerm_subnet" "k8s" {
  name                 = "k8s_subnet"
  resource_group_name  = "${azurerm_resource_group.dev.name}"
  virtual_network_name = "${azurerm_virtual_network.dev.name}"
  address_prefix       = "10.100.0.0/20"
  lifecycle {
      ignore_changes = ["route_table_id"]
  }
}

resource "azurerm_container_registry" "dev" {
  name                = "${var.registry_name}"
  resource_group_name = "${azurerm_resource_group.dev.name}"
  location            = "${azurerm_resource_group.dev.location}"
  sku                 = "Standard"
}
resource "random_id" "k8s" {
  keepers = {
    k8s_cluster = "${var.k8s_cluster_name}"
  }  
  byte_length = 8
}

resource "azurerm_application_insights" "k8s" {
  name                = "k8s-tf-appinsights"
  location            = "${azurerm_resource_group.dev.location}"
  resource_group_name = "${azurerm_resource_group.dev.name}"
  application_type    = "web"
}

resource "azurerm_log_analytics_workspace" "k8s" {
  name                = "k8s-${random_id.k8s.hex}"
  location            = "${azurerm_resource_group.dev.location}"
  resource_group_name = "${azurerm_resource_group.dev.name}"
  sku                 = "PerGB2018"
}

resource "azurerm_log_analytics_solution" "k8s" {
  solution_name         = "Containers"
  location              = "${azurerm_resource_group.dev.location}"
  resource_group_name   = "${azurerm_resource_group.dev.name}"
  workspace_resource_id = "${azurerm_log_analytics_workspace.k8s.id}"
  workspace_name        = "${azurerm_log_analytics_workspace.k8s.name}"

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/Containers"
  }
}

resource "azurerm_kubernetes_cluster" "k8s_cluster" {

  name                = "${var.k8s_cluster_name}"
  location            = "${azurerm_resource_group.dev.location}"
  resource_group_name = "${azurerm_resource_group.dev.name}"
  dns_prefix          = "dev"
  node_resource_group = "dev_aks_node_group"

  agent_pool_profile {
    name            = "default"
    count           = "${var.k8s_vm_count}"
    vm_size         = "${var.k8s_vm_size}"
    os_type         = "Linux"
    os_disk_size_gb = 30
    vnet_subnet_id = "${azurerm_subnet.k8s.id}"
  }

  service_principal {
    client_id     = "${var.k8s_client_id}"
    client_secret = "${var.k8s_client_secret}"
  }

  addon_profile {
    oms_agent {
      enabled                    = true
      log_analytics_workspace_id = "${azurerm_log_analytics_workspace.k8s.id}"
    }
  }

  tags = {
    env = "dev"
  }
}

resource "azurerm_redis_cache" "this" {
  name                = "${var.redis_name}"
  location            = "${azurerm_resource_group.dev.location}"
  resource_group_name = "${azurerm_resource_group.dev.name}"
  capacity            = 2
  family              = "C"
  sku_name            = "Basic"
  enable_non_ssl_port = true
  minimum_tls_version = "1.2"

  redis_configuration {}
}

resource "azurerm_public_ip" "k8s" {
  name                = "k8s_ingress_public_id"
  location            = "${azurerm_resource_group.dev.location}"
  resource_group_name = "${azurerm_kubernetes_cluster.k8s_cluster.node_resource_group}"
  allocation_method   = "Static"
  domain_name_label   = "${var.dns_label_name}"
}
