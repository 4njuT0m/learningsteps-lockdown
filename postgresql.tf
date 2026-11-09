resource "azurerm_postgresql_flexible_server" "main" {
  name                   = "psql-${var.prefix}"
  location               = azurerm_resource_group.main.location
  resource_group_name    = azurerm_resource_group.main.name
  version                = "16"
  administrator_login    = var.db_admin_username
  administrator_password = var.db_admin_password
  sku_name               = "B_Standard_B1ms"
  storage_mb             = 32768
  zone                   = "1"

  # Phase 4: VNet integration. These settings force Terraform to destroy and
  # recreate the server (data loss without a backup), so the migration was
  # done backup-first: pg_dump -> apply -> restore through the VM.
  public_network_access_enabled = false
  delegated_subnet_id           = azurerm_subnet.db.id
  private_dns_zone_id           = azurerm_private_dns_zone.postgres.id

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}

# Phase 4: the "allow-all" firewall rule (0.0.0.0 - 255.255.255.255) is gone.
# A VNet-integrated server has no public endpoint, so no firewall rules apply.

resource "azurerm_postgresql_flexible_server_database" "app" {
  name      = var.db_name
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}
