variable "aws_region" {
  description = "AWS Region for the SES identity and SMTP endpoint; IAM-based SMTP must be supported there."
  type        = string
  default     = "us-east-1"
  nullable    = false
}

variable "domain_name" {
  description = "Dedicated domain or subdomain to verify with SES, without a trailing dot."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$", var.domain_name))
    error_message = "domain_name must be a domain name without a trailing dot."
  }
}

variable "route53_zone_id" {
  description = "ID of the existing public Route 53 hosted zone authoritative for domain_name."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.route53_zone_id)) > 0
    error_message = "route53_zone_id must not be empty."
  }
}

variable "dkim_signing_hosted_zone" {
  description = "SES DkimAttributes.SigningHostedZone for this identity, without a trailing dot. Leave null on the first apply and set it after creating the identity."
  type        = string
  default     = null

  validation {
    condition     = var.dkim_signing_hosted_zone == null ? true : can(regex("^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$", var.dkim_signing_hosted_zone))
    error_message = "dkim_signing_hosted_zone must be the SES-provided DNS name without a trailing dot, or null."
  }
}

variable "iam_user_name" {
  description = "Name of the dedicated SMTP IAM user; IAM user names are unique within an AWS account."
  type        = string
  default     = "ses-smtp-example"
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.iam_user_name))
    error_message = "iam_user_name must be 1-64 letters, digits, or IAM-compatible characters: +=,.@_-."
  }
}

variable "pgp_public_key" {
  description = "Base64-encoded binary PGP public key used to encrypt the AWS access key and SES SMTP password."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9+/]+={0,2}$", var.pgp_public_key)) && length(var.pgp_public_key) % 4 == 0
    error_message = "pgp_public_key must be a non-empty, base64-encoded binary PGP public key without whitespace."
  }
}

variable "tags" {
  description = "Additional tags for taggable resources."
  type        = map(string)
  default     = {}
  nullable    = false
}
