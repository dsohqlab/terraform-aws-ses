###############################################################################
# SESv2 - Email identities
###############################################################################

output "domain_identities" {
  description = "Map of SESv2 domain identity attributes: id, arn, identity_type, verification_status, verified_for_sending_status, dkim_tokens (Easy DKIM selectors; create CNAMEs at <token>._domainkey.<domain> pointing to <token>.<SigningHostedZone>, using the hosted zone returned by SES), and tags_all."
  value = { for k, v in aws_sesv2_email_identity.domain : k => {
    id                          = v.id
    arn                         = v.arn
    identity_type               = v.identity_type
    verification_status         = v.verification_status
    verified_for_sending_status = v.verified_for_sending_status
    dkim_tokens                 = try(v.dkim_signing_attributes[0].tokens, [])
    tags_all                    = v.tags_all
  } }
}

output "email_identities" {
  description = "Map of SESv2 mailbox identity attributes: id, arn, identity_type, verification_status, verified_for_sending_status, tags_all."
  value = { for k, v in aws_sesv2_email_identity.email : k => {
    id                          = v.id
    arn                         = v.arn
    identity_type               = v.identity_type
    verification_status         = v.verification_status
    verified_for_sending_status = v.verified_for_sending_status
    tags_all                    = v.tags_all
  } }
}

output "mail_from_domains" {
  description = "Map of the configured mail_from_domain per SESv2 identity."
  value       = { for k, v in aws_sesv2_email_identity_mail_from_attributes.this : k => v.mail_from_domain }
}

###############################################################################
# SESv2 - Configuration sets + event destinations
###############################################################################

output "configuration_sets" {
  description = "Map of SESv2 configuration set id, arn, name, and tags_all."
  value = { for k, v in aws_sesv2_configuration_set.this : k => {
    id                     = v.id
    arn                    = v.arn
    configuration_set_name = v.configuration_set_name
    tags_all               = v.tags_all
  } }
}

output "configuration_set_event_destination_ids" {
  description = "Map of the pipe-delimited configuration_set_name|event_destination_name id."
  value       = { for k, v in aws_sesv2_configuration_set_event_destination.this : k => v.id }
}

###############################################################################
# SESv2 - Contact lists
###############################################################################

output "contact_lists" {
  description = "Map of SESv2 contact list id, created_timestamp, last_updated_timestamp, and tags_all."
  value = { for k, v in aws_sesv2_contact_list.this : k => {
    id                     = v.id
    created_timestamp      = v.created_timestamp
    last_updated_timestamp = v.last_updated_timestamp
    tags_all               = v.tags_all
  } }
}

###############################################################################
# SESv2 - Dedicated IP pools
###############################################################################

output "dedicated_ip_pools" {
  description = "Map of SESv2 dedicated IP pool id, arn, and tags_all."
  value = { for k, v in aws_sesv2_dedicated_ip_pool.this : k => {
    id       = v.id
    arn      = v.arn
    tags_all = v.tags_all
  } }
}

output "dedicated_ip_assignment_ids" {
  description = "Map of the comma-separated ip,destination_pool_name id."
  value       = { for k, v in aws_sesv2_dedicated_ip_assignment.this : k => v.id }
}

###############################################################################
# SESv2 - Account-level attributes
###############################################################################

output "account_suppression_enabled" {
  description = "Whether an aws_sesv2_account_suppression_attributes resource is managed by this module (true unless account_suppression_attributes was set to null)."
  value       = var.account_suppression_attributes != null
}

output "account_vdm_enabled" {
  description = "Whether an aws_sesv2_account_vdm_attributes resource is managed by this module (true only when account_vdm_attributes was supplied)."
  value       = var.account_vdm_attributes != null
}

###############################################################################
# SESv2 - Tenants
###############################################################################

output "tenants" {
  description = "Map of SESv2 tenant id, tenant_arn, tenant_id, sending_status, and tags_all."
  value = { for k, v in aws_sesv2_tenant.this : k => {
    id             = v.id
    tenant_arn     = v.tenant_arn
    tenant_id      = v.tenant_id
    sending_status = v.sending_status
    tags_all       = v.tags_all
  } }
}

###############################################################################
# Classic SES - Domain + email identities
###############################################################################

output "classic_domain_identities" {
  description = "Map of classic SES domain identity attributes: id, arn, domain, verification_token (create a TXT record at _amazonses.<domain> with this value), and dkim_tokens (present when enable_dkim is true; create CNAMEs at <token>._domainkey.<domain> pointing to <token>.<SigningHostedZone>, using the hosted zone returned by SES)."
  value = { for k, v in aws_ses_domain_identity.this : k => {
    id                 = v.id
    arn                = v.arn
    domain             = v.domain
    verification_token = v.verification_token
    dkim_tokens        = try(aws_ses_domain_dkim.this[k].dkim_tokens, [])
  } }
}

output "classic_email_identities" {
  description = "Map of classic SES email identity id and email."
  value = { for k, v in aws_ses_email_identity.this : k => {
    id    = v.id
    email = v.email
  } }
}

output "classic_mail_from_domains" {
  description = "Map (keyed by the caller's classic_mail_from_domains key) of the configured mail_from_domain per classic SES identity."
  value       = { for k, v in aws_ses_domain_mail_from.this : k => v.mail_from_domain }
}

###############################################################################
# Classic SES - Configuration sets + event destinations
###############################################################################

output "classic_configuration_sets" {
  description = "Map of classic SES configuration set id, arn, and name."
  value = { for k, v in aws_ses_configuration_set.this : k => {
    id   = v.id
    arn  = v.arn
    name = v.name
  } }
}

output "classic_configuration_set_event_destination_arns" {
  description = "Map of classic SES event destination arn."
  value       = { for k, v in aws_ses_event_destination.this : k => v.arn }
}

###############################################################################
# Classic SES - Account-level receipt filters
###############################################################################

output "receipt_filter_arns" {
  description = "Map of classic SES receipt filter arn."
  value       = { for k, v in aws_ses_receipt_filter.this : k => v.arn }
}

###############################################################################
# Classic SES - Receipt rule sets + rules (inbound processing)
###############################################################################

output "receipt_rule_sets" {
  description = "Map of classic SES receipt rule set id and arn."
  value = { for k, v in aws_ses_receipt_rule_set.this : k => {
    id  = v.id
    arn = v.arn
  } }
}

output "receipt_rules" {
  description = "Map of classic SES receipt rule id and arn."
  value = { for k, v in aws_ses_receipt_rule.this : k => {
    id  = v.id
    arn = v.arn
  } }
}

output "active_receipt_rule_set_name" {
  description = "The name of the receipt rule set currently designated ACTIVE by this module, or null when active_receipt_rule_set_key was not set."
  value       = var.active_receipt_rule_set_key != null ? aws_ses_active_receipt_rule_set.this["this"].rule_set_name : null
}

###############################################################################
# Classic SES - Templates
###############################################################################

output "ses_templates" {
  description = "Map of classic SES template id and arn."
  value = { for k, v in aws_ses_template.this : k => {
    id  = v.id
    arn = v.arn
  } }
}

###############################################################################
# Cross-cutting identity lookups (used internally; exposed for convenience so
# callers can wire DNS records / notification topics without recomputing the
# same merges this module already performed).
###############################################################################

output "v2_identity_email_by_key" {
  description = "Map merging domain_identities and email_identities keys to their resolved SESv2 email_identity string. Convenience output for wiring identity_notification_topics / classic_identity_policies identity fields without re-deriving the value."
  value       = merge({ for k, v in aws_sesv2_email_identity.domain : k => v.email_identity }, { for k, v in aws_sesv2_email_identity.email : k => v.email_identity })
}

output "classic_identity_by_key" {
  description = "Map merging classic_domain_identities and classic_email_identities keys to their resolved domain/email string. Convenience output for wiring identity_notification_topics / classic_identity_policies identity fields without re-deriving the value."
  value       = merge({ for k, v in aws_ses_domain_identity.this : k => v.domain }, { for k, v in aws_ses_email_identity.this : k => v.email })
}
