# ----- General AWS Settings -----
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

# ----- VPC and Networking -----
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.123.0.0/16"
}

variable "azs" {
  description = "Availability Zones to use"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnets" {
  type    = list(string)
  default = ["10.123.1.0/24", "10.123.2.0/24"]
}

variable "private_subnets" {
  type    = list(string)
  default = ["10.123.3.0/24", "10.123.4.0/24"]
}

variable "intra_subnets" {
  type    = list(string)
  default = ["10.123.5.0/24", "10.123.6.0/24"]
}

# ----- S3/SNS/Lambda -----
variable "bucket_name" {
  description = "Prefix for the S3 bucket name"
  type        = string
  default     = "compliance-checker-bucket"
}

variable "sns_topic_name" {
  description = "SNS topic name"
  type        = string
  default     = "compliance-checker-topic"
}

variable "notification_email" {
  description = "Notification email for SNS"
  type        = string
}

variable "lambda_function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "ComplianceCheckerFunction"
}

# ----- EKS -----
variable "eks_cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "compliance-eks"
}

variable "eks_cluster_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.33"
}

# ----- Tags/Metadata -----
variable "project_name" {
  description = "Project name"
  type        = string
  default     = "Compliance Checker Project"
}

variable "environment" {
  description = "Environment (dev, stage, prod, etc)"
  type        = string
  default     = "dev"
}

variable "ecr_repo" {
  description = "ECR repository name (from CI: ECR_REPO)"
  type        = string
}
