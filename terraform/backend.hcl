bucket         = "compliance-checker-state-bucket"
key            = "compliance-checker/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "compliance-checker-db-locks"
encrypt        = true
