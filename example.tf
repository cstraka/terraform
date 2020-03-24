provider "aws" {
	profile    = "cstraka"
	region     = "us-west-2"
}

variable "server_port" {
	description = "The port the server will use for HTTP requests"
	type = number
	default = 8080
}

variable "asg_capacity_size" {
	description = "the Minimum and Desired server count for the ASG"
	type = number
	default = 2
}

# New security group resource to allow tcp 8080 connections.
resource "aws_security_group" "instance" {
	name = "terraform-example-instance"
	ingress {
		from_port = var.server_port
		to_port = var.server_port
		protocol = "tcp"
		cidr_blocks = ["0.0.0.0/0"]
	}
}

# New security group resource to allow port 80 to and from ALB.
resource "aws_security_group" "alb" {
	name = "terraform-example-alb"
	
	#allow HTTP inbound
	ingress {
		from_port = 80
		to_port = 80
		protocol = "tcp"
		cidr_blocks = ["0.0.0.0/0"]
	}
	
	#allow all outbound
	egress {
		from_port = 0
		to_port = 0
		protocol = "-1"
		cidr_blocks = ["0.0.0.0/0"]
	}
}

data "aws_vpc" "default" {
	default = true
}

data "aws_subnet_ids" "default" {
	vpc_id = data.aws_vpc.default.id
}

# AWS Application Load Balancer (ALB) resource
resource "aws_lb" "example" {
	name = "terraform-asg-example"
	load_balancer_type = "application"
	subnets = data.aws_subnet_ids.default.ids
	security_groups = [aws_security_group.alb.id]
}

resource "aws_lb_target_group" "asg" {
	name = "terraform-asg-example"
	port = var.server_port
	protocol = "HTTP"
	vpc_id = data.aws_vpc.default.id
	
	health_check {
		path = "/"
		protocol = "HTTP"
		matcher = "200"
		interval = 15
		timeout = 3
		healthy_threshold = 2
		unhealthy_threshold = 2
	}
}

# AWS Application Load Balancer (ALB) LISTENER resource
resource "aws_lb_listener" "http" {
	load_balancer_arn = aws_lb.example.arn
	port = 80
	protocol = "HTTP"
	
	#By default, return a simple 404 page
	default_action {
		type = "fixed-response"
		
		fixed_response {
			content_type = "text/plain"
			message_body = "404: page not found"
			status_code = 404
		}
	}
}

# EC2 Resource 
# aws_launch_configuration is an auto scale group (ASG)
resource "aws_launch_configuration" "example" {
	image_id = "ami-0d1cd67c26f5fca19"
	instance_type = "t2.micro"
	security_groups = [aws_security_group.instance.id]
	
	user_data = <<-EOF
		#!/bin/bash
		echo "Hello, World" > index.html
		nohup busybox httpd -f -p ${var.server_port} &
		EOF
	
	lifecycle {
		create_before_destroy = true
	}
}

# EIP Resource - can't use on an ASG.
#resource "aws_eip" "ip" {
#    vpc = true
#    instance = aws_instance.example.id
#}

# AWS ASG Resource
resource "aws_autoscaling_group" "example"{
	launch_configuration = aws_launch_configuration.example.name
	vpc_zone_identifier = data.aws_subnet_ids.default.ids
	
	target_group_arns = [aws_lb_target_group.asg.arn]
	health_check_type = "ELB"
	
	min_size = var.asg_capacity_size
	max_size = 10
	desired_capacity = var.asg_capacity_size
	
	tag {
		key = "Name"
		value = "terraform-asg-example"
		propagate_at_launch = true
	} 
}

resource "aws_lb_listener_rule" "asg" {
	listener_arn = aws_lb_listener.http.arn
	priority = 100
	
	condition {
		field = "path-pattern"
		values = ["*"]
	}
	
	action {
		type = "forward"
		target_group_arn = aws_lb_target_group.asg.arn
	}
}

# Output statement for IP Address
output "alb_dns_name" {
	value = aws_lb.example.dns_name
	description = "The domain name of the load balancer"
}