variable "db_admin_password" {
  type      = string
  sensitive = true
}

variable "ssh_public_key_path" {
  type = string
}

variable "my_ip" {
  description = "Public IP allowed to access PostgreSQL"
  type        = string
}