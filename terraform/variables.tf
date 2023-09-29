variable "region" {
}

variable "env" {
}

variable "project_name" {
}

variable "availability_zones" {
  type        = list
  description = "The az that the resources will be launched"
}

variable "dns_zone_name" {
}

variable "alb_protocol" {}

variable "tags" {
  type        = map
  default     = {}
  description = "Optional tags to add to resources"
}

variable "dns_records" {
  description = "List of DNS records to create"
  type = list(object({
    dns_subdomain = string
    ttl     = number
  }))
}


