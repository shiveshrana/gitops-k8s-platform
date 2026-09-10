variable "aws_region" {
  description = "AWS region for the EKS cluster"
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "gitops-platform"
}