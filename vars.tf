variable "tag_name" {
  type    = string
  default = "demo-infastructure"
}

variable "region" {
  type    = string
  default = "eu-west-2"
}

variable "dbuser" {
  type      = string
  sensitive = true
}

variable "dbpass" {
  type      = string
  sensitive = true
}