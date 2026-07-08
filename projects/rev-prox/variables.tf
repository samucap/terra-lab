variable "instance_type" {
  type    = string
  default = "t4g.micro"
}

variable "backend_target" {
  type    = string
  default = "192.168.11.1"
}
