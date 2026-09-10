variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "ap-south-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_name" {
  description = "Name tag for the VPC"
  type        = string
  default     = "my-vpc"
}

variable "pub_subnet_cidr" {
  description = "CIDR for public subnet 1 (ap-south-1b)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "pub_subnet_cidr_2" {
  description = "CIDR for public subnet 2 (ap-south-1a)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "pvt_subnet_cidr" {
  description = "CIDR for private subnet 1 (ap-south-1a)"
  type        = string
  default     = "10.0.11.0/24"
}

variable "pvt_subnet_cidr_2" {
  description = "CIDR for private subnet 2 (ap-south-1b)"
  type        = string
  default     = "10.0.12.0/24"
}

variable "subnet_name" {
  description = "Base name for private subnets"
  type        = string
  default     = "Db-Subnet"
}

variable "public_subnet_name" {
  description = "Base name for public subnets"
  type        = string
  default     = "App-Subnet"
}

variable "environment" {
  description = "Environment tag"
  type        = string
  default     = "Dev"
}

variable "project" {
  description = "Project tag"
  type        = string
  default     = "ai-interview-platform"
}

variable "created_by" {
  description = "Created-by tag"
  type        = string
  default     = "magiceagle7707-oss"
}
