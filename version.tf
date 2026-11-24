terraform {
  required_version = ">= 1.11.1"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.45"
    }
  }

  provider_meta "aws" {
    user_agent = [
      "github.com/dsohqlab/terraform-aws-ses"
    ]
  }
}
