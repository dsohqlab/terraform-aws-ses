output "domain_identity" {
  description = "SES domain identity, verification status, and Easy DKIM tokens."
  value       = module.ses.domain_identities["main"]
}

output "mail_from_domain" {
  description = "Custom MAIL FROM domain configured for the identity."
  value       = module.ses.mail_from_domains["main"]
}

output "configuration_set_name" {
  description = "Configuration set to specify when sending email."
  value       = module.ses.configuration_sets["transactional"].configuration_set_name
}

output "events_topic_arn" {
  description = "SNS topic that receives SES sending events."
  value       = aws_sns_topic.events.arn
}

output "events_queue_url" {
  description = "SQS queue containing the SES event messages."
  value       = aws_sqs_queue.events.id
}

output "contact_list_name" {
  description = "Example newsletter contact list name."
  value       = module.ses.contact_lists["newsletter"].id
}

output "template_name" {
  description = "Example welcome template name."
  value       = module.ses.ses_templates["welcome"].id
}

output "inbound_bucket_name" {
  description = "S3 bucket for received messages, or null when inbound mail is disabled."
  value       = var.enable_inbound ? aws_s3_bucket.inbound[0].id : null
}

output "active_receipt_rule_set_name" {
  description = "Active receipt rule set managed by the example, or null when activation is disabled."
  value       = var.enable_inbound && var.activate_receipt_rule_set ? aws_ses_active_receipt_rule_set.inbound[0].rule_set_name : null
}
