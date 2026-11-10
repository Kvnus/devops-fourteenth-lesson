variable "name" {
  description = "Prefix for network resources."
  type        = string
}

variable "zone" {
  type = string
}

variable "cidr" {
  description = "Subnet CIDR. All VMs in it can reach each other (the group allows traffic from itself)."
  type        = string
  default     = "10.10.0.0/24"
}

variable "ssh_allowed_cidrs" {
  description = "Who may connect over SSH. Restrict to your IP/32 in real use."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "app_ports" {
  description = "TCP ports opened to app_allowed_cidrs."
  type        = list(number)
  default     = [8080]
}

variable "app_allowed_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "labels" {
  type    = map(string)
  default = {}
}
