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
