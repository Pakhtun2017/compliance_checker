output "compliance_bucket_name" {
  value = aws_s3_bucket.compliance_bucket.bucket
}

output "flask_dashboard_irsa_role_arn" {
  value = aws_iam_role.flask_dashboard.arn
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "ecr_repo_url" {
  description = "Full ECR repository URI (account.dkr.ecr.region.amazonaws.com/name)"
  value       = aws_ecr_repository.app.repository_url
}
