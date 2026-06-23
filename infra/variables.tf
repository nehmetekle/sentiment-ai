variable "image_tag" {
  description = "Tag of the Docker image to deploy"
  type        = string
  default     = "latest"
}

variable "app_port" {
  description = "Port exposed for staging"
  type        = number
  default     = 8001
}

variable "container_name" {
  description = "Name of the staging container"
  type        = string
  default     = "sentiment-staging"
}

variable "registry" {
  description = "Docker registry"
  type        = string
  default     = "ghcr.io/nehmetekle"
}