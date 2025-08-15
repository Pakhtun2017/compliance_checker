terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws       = { source = "hashicorp/aws", version = "~> 6.0" }
    helm      = { source = "hashicorp/helm", version = "~> 2.0" }
    tls       = { source = "hashicorp/tls", version = ">= 4.0.0" }
    time      = { source = "hashicorp/time", version = ">= 0.9.0" }
    cloudinit = { source = "hashicorp/cloudinit", version = ">= 2.0.0" }
    null      = { source = "hashicorp/null", version = ">= 3.0.0" }
    archive   = { source = "hashicorp/archive" }
    random    = { source = "hashicorp/random" }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "helm" {
  alias = "eks"
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks", "get-token",
        "--cluster-name", var.eks_cluster_name,
        "--region", var.aws_region,
      ]
    }
  }
}
