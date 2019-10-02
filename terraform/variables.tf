variable "location" {
  default = "japaneast"
}

variable "k8s_cluster_name" {
  default = "k8s"
}

variable "k8s_vm_count" {
  default = 1  
}

variable "k8s_vm_size" {
  default = "Standard_D2s_v3"
}

variable "k8s_client_id" {
}

variable "k8s_client_secret" {
}

variable "registry_name" {
  default = "friezaRegistry"  
}

variable "redis_name" {
  default = "friezaRedis"  
}

variable "dns_label_name" {
  default = "frieza-dev"  
}
