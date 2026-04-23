# Same pins as bootstrap. Modules don't enforce their own provider
# configuration — they inherit from the root module that calls them —
# but they CAN declare version constraints their HCL assumes.

terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}
