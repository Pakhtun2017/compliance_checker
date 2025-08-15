locals {
  name   = "compliance-checker-cluster"
  region = "us-east-1"

  vpc_cidr = "10.123.0.0/16"
  azs      = ["us-east-1a", "us-east-1b"]

  public_subnets  = ["10.123.1.0/24", "10.123.2.0/24"]
  private_subnets = ["10.123.3.0/24", "10.123.4.0/24"]
  intra_subnets   = ["10.123.5.0/24", "10.123.6.0/24"]

  tags = {
    Example = local.name
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets
  intra_subnets   = local.intra_subnets

  enable_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}


module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = local.name
  kubernetes_version = "1.33"

  # EKS Addons
  addons = {
    coredns = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
  }

  # allows EKS API endpoint to be reachable from the internet
  endpoint_public_access = true

  # Adds the current caller identity as an administrator via cluster access entry
  enable_cluster_creator_admin_permissions = true

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  enable_irsa = true

  # EKS Managed Node Group(s)
  eks_managed_node_groups = {
    pashtun-cluster-group = {
      ami_type                              = "AL2023_x86_64_STANDARD"
      instance_types                        = ["t3.medium"]
      capacity_type                         = "SPOT"
      attach_cluster_primary_security_group = true
      min_size                              = 1
      max_size                              = 2
      desired_size                          = 1

      tags = {
        ExtraTag = "helloworld"
      }
    }
  }

  # this solves the issue of duplicate SG tags issue
  # https://stackoverflow.com/questions/74687452/eks-error-syncing-load-balancer-failed-to-ensure-load-balancer-multiple-tagge
  node_security_group_tags = {
    "kubernetes.io/cluster/${local.name}" = null
  }

  tags = local.tags
}

# -------------------------
# COMPLIANCE CHECKER AWS RESOURCES
# -------------------------

resource "random_id" "resource_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "compliance_bucket" {
  bucket        = "compliance-checker-bucket-${random_id.resource_suffix.hex}"
  force_destroy = true
}

resource "aws_sns_topic" "compliance_topic" {
  name = "compliance-checker-topic-${random_id.resource_suffix.hex}"
}

resource "aws_sns_topic_subscription" "email_sub" {
  topic_arn = aws_sns_topic.compliance_topic.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

data "archive_file" "lambda_pkg" {
  type        = "zip"
  source_file = "${path.module}/lambda/compliance_checker.py"
  output_path = "${path.module}/lambda/function.zip"
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda" {
  name               = "compliance-checker-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.compliance_bucket.arn}/*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.compliance_topic.arn]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "ComplianceLambdaPolicy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_policy.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "compliance_checker" {
  function_name    = "ComplianceCheckerFunction-${random_id.resource_suffix.hex}"
  role             = aws_iam_role.lambda.arn
  handler          = "compliance_checker.lambda_handler"
  runtime          = "python3.10"
  filename         = data.archive_file.lambda_pkg.output_path
  source_code_hash = data.archive_file.lambda_pkg.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.compliance_topic.arn
    }
  }
}

resource "aws_lambda_permission" "from_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.compliance_checker.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.compliance_bucket.arn
}

resource "aws_s3_bucket_notification" "notify" {
  bucket = aws_s3_bucket.compliance_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.compliance_checker.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".json"
  }

  depends_on = [aws_lambda_permission.from_s3]
}

# IRSA (IAM Role for Service Account) for Flask Dashboard
data "aws_iam_policy_document" "flask_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      # <-- match your Helm SA exactly:
      values = ["system:serviceaccount:compliance:compliance-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}


data "aws_iam_policy_document" "flask_s3_policy" {
  statement {
    actions = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [
      aws_s3_bucket.compliance_bucket.arn,
      "${aws_s3_bucket.compliance_bucket.arn}/*"
    ]
    effect = "Allow"
  }
}

resource "aws_iam_role" "flask_dashboard" {
  name               = "flask-dashboard-irsa"
  assume_role_policy = data.aws_iam_policy_document.flask_assume_role.json
}

resource "aws_iam_role_policy" "flask_dashboard" {
  name   = "FlaskDashboardS3Policy"
  role   = aws_iam_role.flask_dashboard.id
  policy = data.aws_iam_policy_document.flask_s3_policy.json
}

# Discover the current account and region from the active AWS credentials
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}


# Create the repo (first run in a new account). If a repo
# with this name already exists, run `terraform import` once.
resource "aws_ecr_repository" "app" {
  name = var.ecr_repo

  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "AES256"
  }

    # allow Terraform to delete even if images are present
  force_delete = true

  tags = {
    Project = "compliance-checker"
  }
}

# IAM policy using dynamic account & region (no hardcoded strings)
data "aws_iam_policy_document" "ci_ecr" {
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrRepoManagement"
    effect = "Allow"
    actions = [
      "ecr:CreateRepository",
      "ecr:DescribeRepositories",
      "ecr:PutLifecyclePolicy",
      "ecr:PutImageScanningConfiguration",
      "ecr:TagResource"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPushAndQuerySpecificRepo"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:DescribeImages"
    ]
    resources = [
      # "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/${var.ecr_repo}"
      "arn:aws:ecr:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:repository/${var.ecr_repo}"
    ]
  }
}

resource "aws_iam_policy" "ci_ecr" {
  name   = "ci-ecr-permissions"
  policy = data.aws_iam_policy_document.ci_ecr.json
}
