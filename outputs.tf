output "jenkins_public_ip" {
  value = azurerm_public_ip.jenkins.ip_address
}

output "acr_login_server" {
  value = azurerm_container_registry.deploystage.login_server
}

output "postgres_fqdn" {
  value = azurerm_postgresql_flexible_server.deploystage.fqdn
}