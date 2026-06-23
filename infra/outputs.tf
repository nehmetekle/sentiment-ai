output "container_id" {
  description = "ID of the staging container"
  value       = docker_container.sentiment_staging.id
}

output "app_url" {
  description = "URL of the staging application"
  value       = "http://localhost:${var.app_port}"
}

output "network_name" {
  description = "Name of the Docker network"
  value       = docker_network.cicd.name
}