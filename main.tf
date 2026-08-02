# Region restricted by Azure for Students policy — see allowed list via:
# az policy assignment list --query "[?displayName=='Allowed resource deployment regions'].parameters" -o json
resource "azurerm_resource_group" "deploystage" {
  name     = "deploystage-rg"
  location = "Sweden Central"
}

resource "azurerm_container_registry" "deploystage" {
  name                = "deploystageacr"
  resource_group_name = azurerm_resource_group.deploystage.name
  location            = azurerm_resource_group.deploystage.location
  sku                 = "Basic"
  admin_enabled       = true
}

resource "azurerm_kubernetes_cluster" "deploystage" {
  name                = "deploystage-aks"
  resource_group_name = azurerm_resource_group.deploystage.name
  location            = azurerm_resource_group.deploystage.location
  dns_prefix          = "deploystage"
  oidc_issuer_enabled = true

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_B2s_v2"

    upgrade_settings {
      drain_timeout_in_minutes      = 0
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 0
    }
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_virtual_network" "deploystage" {
  name                = "deploystage-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.deploystage.location
  resource_group_name = azurerm_resource_group.deploystage.name
}

resource "azurerm_subnet" "jenkins" {
  name                 = "jenkins-subnet"
  virtual_network_name = azurerm_virtual_network.deploystage.name
  resource_group_name  = azurerm_resource_group.deploystage.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_security_group" "jenkins" {
  name                = "jenkins-nsg"
  location            = azurerm_resource_group.deploystage.location
  resource_group_name = azurerm_resource_group.deploystage.name

  security_rule {
    name                       = "AllowSSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowJenkinsUI"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "jenkins" {
  name                = "jenkins-public-ip"
  location            = azurerm_resource_group.deploystage.location
  resource_group_name = azurerm_resource_group.deploystage.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "jenkins" {
  name                = "jenkins-nic"
  location            = azurerm_resource_group.deploystage.location
  resource_group_name = azurerm_resource_group.deploystage.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.jenkins.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.jenkins.id
  }
}

resource "azurerm_network_interface_security_group_association" "jenkins" {
  network_interface_id      = azurerm_network_interface.jenkins.id
  network_security_group_id = azurerm_network_security_group.jenkins.id
}

resource "azurerm_linux_virtual_machine" "jenkins" {
  name                = "jenkins-vm"
  resource_group_name = azurerm_resource_group.deploystage.name
  location            = azurerm_resource_group.deploystage.location
  size                = "Standard_B2s_v2"
  admin_username      = "azureuser"
  network_interface_ids = [
    azurerm_network_interface.jenkins.id,
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = file(var.ssh_public_key_path)
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                    = azurerm_kubernetes_cluster.deploystage.kubelet_identity[0].object_id
  role_definition_name            = "AcrPull"
  scope                           = azurerm_container_registry.deploystage.id
  skip_service_principal_aad_check = true
}

resource "azurerm_postgresql_flexible_server" "deploystage" {
  name                   = "deploystage-db"
  resource_group_name    = azurerm_resource_group.deploystage.name
  location               = azurerm_resource_group.deploystage.location
  version                = "16"
  administrator_login    = "deploystageadmin"
  administrator_password = var.db_admin_password
  storage_mb             = 32768
  sku_name               = "B_Standard_B1ms"
  zone                   = "1"
}

resource "azurerm_postgresql_flexible_server_database" "deploystage" {
  name      = "deploystage"
  server_id = azurerm_postgresql_flexible_server.deploystage.id
  collation = "en_US.utf8"
  charset   = "UTF8"
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.deploystage.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_my_ip" {
  name             = "AllowMyLaptop"
  server_id        = azurerm_postgresql_flexible_server.deploystage.id
  start_ip_address = var.my_ip
  end_ip_address   = var.my_ip
}
