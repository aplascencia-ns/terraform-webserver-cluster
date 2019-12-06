variable "server_port" {
  description = "The port the server will use for HTTP requests"
  type        = number
  default     = 8080
}

variable "cluster_name" {
  description = "The name to use to namespace all the resources in the cluster"
  type        = string
  default     = "webservers-test"
}

variable network_cidr {
  default = "10.0.0.0/16"
}

variable availability_zones {
  default = ["us-east-1a", "us-east-1b"]
}
