# Same pins as the rest of the project — see terraform/bootstrap/versions.tf
# for the rationale on tilde-major version constraints.

terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}
