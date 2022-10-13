variable "component_name" {
  type    = string
  default = "sonarqube-server"
}

variable "container_name" {
  type    = string
  default = "sonarqube-server"
}

variable "image_name" {
  type    = string
  default = "sonarqube-customize-image-release"
}

variable "image_version" {
  type    = string
  default = "latest"
}

variable "container_port" {
  type    = number
  default = 9000
}

variable "database_name" {
  description = "sonarQube database name"
  type        = string
  default     = "sonar"
}

variable "master_username" {
  description = "sonarQube database master user name"
  type        = string
  default     = "sonar"
}

variable "dns_zone_name" {
  type    = string
  default = "germatech.click"
}

variable "subject_alternative_names" {
  type    = list(any)
  default = ["*.germatech.click"]
}