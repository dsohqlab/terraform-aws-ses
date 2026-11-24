output "domain_identity" {
  description = "SES domain identity, verification status, and Easy DKIM tokens."
  value       = module.ses.domain_identities["main"]
}

output "iam_user_arn" {
  description = "ARN of the dedicated SMTP IAM user."
  value       = module.iam_user.arn
}

output "smtp_endpoint" {
  description = "Regional SES SMTP endpoint; connect using STARTTLS on port 587."
  value       = "email-smtp.${var.aws_region}.${data.aws_partition.current.dns_suffix}"
}

output "smtp_username" {
  description = "SMTP username, which is the IAM access key ID."
  value       = module.iam_user.access_key_id
  sensitive   = true
}

output "smtp_password_encrypted" {
  description = "Base64-encoded, PGP-encrypted regional SES SMTP password."
  value       = module.iam_user.access_key_encrypted_ses_smtp_password_v4
  sensitive   = true
}

output "smtp_pgp_key_fingerprint" {
  description = "Fingerprint of the PGP public key used to encrypt the credentials."
  value       = module.iam_user.access_key_fingerprint
}
