output "client_certificate" {
  value = "${azurerm_kubernetes_cluster.k8s_cluster.kube_config.0.client_certificate}"
}

output "kube_config" {
  value = "${azurerm_kubernetes_cluster.k8s_cluster.kube_config_raw}"
}

output "acr_login_server" {
  description = "ACR Registry"
  value = "${azurerm_container_registry.dev.login_server}"
}

output "redis_host" {
  value = "${azurerm_redis_cache.this.hostname}"
}
output "redis_port" {
  value = "${azurerm_redis_cache.this.port}"
}
output "redis_primary_key" {
  value = "${azurerm_redis_cache.this.primary_access_key}"
}

output "public_ip_fqdn" {
  value = "${azurerm_public_ip.k8s.fqdn}"
}
output "public_ip" {
  value = "${azurerm_public_ip.k8s.ip_address}"
}

output "app_insights_instrumentation_key" {
  value = "${azurerm_application_insights.k8s.instrumentation_key}"
}

output "app_insights_app_id" {
  value = "${azurerm_application_insights.k8s.app_id}"
}
