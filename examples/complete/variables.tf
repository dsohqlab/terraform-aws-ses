variable "aws_region" {
  description = "AWS Region for SES and its supporting resources. Choose a Region supporting SES email receiving if inbound mail is enabled."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Prefix for example resources; use a different name for each deployment."
  type        = string
  default     = "ses-example"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,24}[a-z0-9])?$", var.name))
    error_message = "name must be 1-26 lowercase letters, digits, or hyphens, and must start and end with a letter or digit."
  }
}

variable "domain_name" {
  description = "Dedicated domain or subdomain to verify with SES, without a trailing dot."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$", var.domain_name))
    error_message = "domain_name must be a domain name without a trailing dot."
  }
}

variable "route53_zone_id" {
  description = "ID of the existing public Route 53 hosted zone authoritative for domain_name."
  type        = string
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

variable "enable_inbound" {
  description = "Create an inbound S3 bucket and receipt rules after the domain has been verified. This does not activate the rule set."
  type        = bool
  default     = false
}

variable "activate_receipt_rule_set" {
  description = "Activate the example's receipt rule set and publish its inbound MX record. This replaces any active rule set in the account and Region."
  type        = bool
  default     = false

  validation {
    condition     = var.activate_receipt_rule_set ? var.enable_inbound : true
    error_message = "enable_inbound must be true before activating the receipt rule set."
  }
}

variable "tags" {
  description = "Additional tags for taggable resources."
  type        = map(string)
  default     = {}
}
