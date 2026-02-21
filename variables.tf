# variables.tf

variable "vm_ip" {
  description = "The static IP address of the VM"
  type        = string
  # REPLACE this default with the IP you configured in Netplan
  default     = "172.16.137.100" 
}

variable "ssh_user" {
  description = "The username to connect to the VM"
  type        = string
  default     = "gabimaru"
}

variable "maru" {
  type = string
  sensitive = true
}
