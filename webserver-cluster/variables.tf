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

# variable "alb_name" {
#   description = "The name of the ALB"
#   type        = string
#   default     = "webservers-lb"
# }

# variable "instance_security_group_name" {
#   description = "The name of the security group for the EC2 Instances"
#   type        = string
#   default     = "webservers-instance"
# }

# variable "alb_security_group_name" {
#   description = "The name of the security group for the ALB"
#   type        = string
#   default     = "webservers-alb"
# }
