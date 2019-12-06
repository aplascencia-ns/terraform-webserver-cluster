# REQUIRE A SPECIFIC TERRAFORM VERSION OR HIGHER
# ------------------------------------------------------------------------------
terraform {
  required_version = ">= 0.12"
}

# Configure the provider(s)
provider "aws" {
  region = "us-east-1" # N. Virginia (US East)
}

resource "aws_security_group" "instance_sg" {
  name = "${var.cluster_name}-instance-sg" # var.instance_security_group_name

  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_vpc" "main_vpc" {
  id = aws_vpc.main_vpc.id
}

data "aws_subnet_ids" "private_subnet" {
  vpc_id = data.aws_vpc.main_vpc.id

  # count = 2
  filter {
    name   = "tag:Name"
    values = ["${var.cluster_name}-Private-Subnet"] #-${count.index + 1}"]       # insert value here
  }
}

# data "aws_subnet" "private_subnet" {
#   count = 2

#   filter {
#     name   = "tag:Name"
#     values = ["${var.cluster_name}-Private-Subnet-${count.index + 1}"]       # insert value here
#   }
# }

# ---------------------------------------------------------------------------------------------------------------------
#  Get DATA SOURCES
# ---------------------------------------------------------------------------------------------------------------------
data "aws_availability_zones" "available" {}


# ---------------------------------------------------------------------------------------------------------------------
#  VPC AND SUBNETS
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "${var.cluster_name}-main-vpc"
  }
}

# PUBLIC SUBNETS
# --------------------------------------
resource "aws_subnet" "public_subnet" {
  # Use the count meta-parameter to create multiple copies
  count  = 1 # length(var.availability_zones)
  vpc_id = aws_vpc.main_vpc.id

  # cidrsubnet function splits a cidr block into subnets
  cidr_block = cidrsubnet(var.network_cidr, 8, count.index) # 10.0.0.0/24 

  # element retrieves a list element at a given index
  availability_zone = data.aws_availability_zones.available.names[0] # AZa

  # availability_zone = element(var.availability_zones, count.index)
  # availability_zone = element(data.aws_availability_zones.all.names, count.index)

  tags = {
    Name = "${var.cluster_name} - Public Subnet ${count.index + 1} - ${element(var.availability_zones, count.index)}"
  }
}

# Route table association with public subnets
resource "aws_route_table_association" "public_rta" {
  # count          = 1                                                   # "${length(var.subnets_cidr)}"
  subnet_id      = "aws_subnet.public_subnet.*.id" # aws_subnet.public_subnet.id 
  route_table_id = aws_route_table.public_rt.id

  # tags {
  #   Name = "${var.cluster_name}-public-rta"
  # }
}

# PRIVATE SUBNETS
# --------------------------------------
resource "aws_subnet" "private_subnet" {
  # Use the count meta-parameter to create multiple copies
  count  = 2 # length(var.availability_zones)
  vpc_id = aws_vpc.main_vpc.id

  # cidrsubnet function splits a cidr block into subnets
  cidr_block = cidrsubnet(var.network_cidr, 8, count.index + 1) # + 1 because I created one public subnet

  # element retrieves a list element at a given index
  availability_zone = data.aws_availability_zones.available.names[count.index]


  # availability_zone = element(var.availability_zones, count.index)

  tags = {
    Name = "${var.cluster_name}-Private-Subnet" #-${count.index + 1}" # - ${element(var.availability_zones, count.index)}"
  }
}

# Route table association with private subnets
resource "aws_route_table_association" "private_rta" {
  # count          = 2
  subnet_id      = "aws_subnet.private_subnet.*.id" #element(aws_subnet.private_subnet.*.id, count.index) # aws_subnet.private_subnet.id
  route_table_id = "aws_route_table.private_rt[count.index]"

  # tags = {
  #   Name = "${var.cluster_name}-private-rta"
  # }
}


# ---------------------------------------------------------------------------------------------------------------------
#  NETWORKING
# ---------------------------------------------------------------------------------------------------------------------
# Internet Gateway
resource "aws_internet_gateway" "web_igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

resource "aws_network_acl" "all" {
  vpc_id = aws_vpc.main_vpc.id

  egress {
    protocol   = "-1"
    rule_no    = 2
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  ingress {
    protocol   = "-1"
    rule_no    = 1
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  # tags {
  #   Name = "${var.cluster_name}-open-acl"
  # }
}

# Route table: attach Internet Gateway 
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.web_igw.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main_vpc.id

  # count = 1
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.public_nat_gw.id
  }

  tags = {
    Name = "${var.cluster_name}-private-rt"
  }
}

resource "aws_eip" "forNat_eip" {
  vpc = true

  tags = {
    Name = "${var.cluster_name}-eip"
  }
}

resource "aws_nat_gateway" "public_nat_gw" {
  # count         = 1
  allocation_id = aws_eip.forNat_eip.id
  subnet_id     = "aws_subnet.public_subnet.*.id"
  depends_on    = [aws_internet_gateway.web_igw]

  tags = {
    Name = "${var.cluster_name}-public-nat-gw"
  }
}





# ---------------------------------------------------------------------------------------------------------------------
# AUTO SCALING GROUP
# ---------------------------------------------------------------------------------------------------------------------
# Create a launch configuration, which specifies how to configure each EC2 Instance in the ASG
resource "aws_launch_configuration" "web_asg_lc" {
  image_id        = "ami-04b9e92b5572fa0d1"
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.instance_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p ${var.server_port} &
              EOF

  # Required when using a launch configuration with an auto scaling group.
  # https://www.terraform.io/docs/providers/aws/r/launch_configuration.html
  lifecycle {
    create_before_destroy = true
  }
}

# create the ASG itself using the aws_autoscaling_group resource
resource "aws_autoscaling_group" "web_asg" {
  launch_configuration = aws_launch_configuration.web_asg_lc.name
  vpc_zone_identifier  = data.aws_subnet_ids.private_subnet.ids # pull the subnet IDs out of the aws_subnet_ids data source
  # count = 2
  # availability_zones =  ["${data.aws_availability_zones.available.names[count.index]}"]
  target_group_arns = [aws_lb_target_group.web_lb_tg.arn]
  health_check_type = "ELB"

  min_size = 2
  max_size = 2

  tag {
    key                 = "Name"
    value               = var.cluster_name
    propagate_at_launch = true
  }
}


# ---------------------------------------------------------------------------------------------------------------------
# LOAD BALANCER
# ---------------------------------------------------------------------------------------------------------------------

# The first step is to create the ALB itself
resource "aws_lb" "public_lb" {
  name               = var.cluster_name
  load_balancer_type = "application"
  subnets            = aws_subnet.public_subnet.*.id
  # subnets            = data.aws_subnet_ids.default.ids
  security_groups = [aws_security_group.web_lb_sg.id]
}

# The next step is to define a listener for this ALB
# --- Note that, by default, all AWS resources, including ALBs, don’t allow any incoming or outgoing traffic, 
# --- so you need to create a new security group specifically for the ALB
resource "aws_lb_listener" "web_lb_http_lstr" {
  load_balancer_arn = aws_lb.public_lb.arn
  port              = 80
  protocol          = "HTTP"

  # By default, return a simple 404 page
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}

resource "aws_lb_target_group" "web_lb_tg" {
  name     = var.cluster_name
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.main_vpc.id # data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener_rule" "web_lb_lstr_r" {
  listener_arn = aws_lb_listener.web_lb_http_lstr.arn
  priority     = 100

  condition {
    field  = "path-pattern"
    values = ["*"]
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_lb_tg.arn
  }
}

resource "aws_security_group" "web_lb_sg" {
  name = "${var.cluster_name}-lb-sg"

  # Allow inbound HTTP requests
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound requests
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}