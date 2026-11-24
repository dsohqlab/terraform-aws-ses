module "wrapper" {
  source = "../"

  for_each = var.items

  account_suppression_attributes = try(each.value.account_suppression_attributes, var.defaults.account_suppression_attributes, {
    suppressed_reasons = ["BOUNCE", "COMPLAINT"]
  })
  account_vdm_attributes                       = try(each.value.account_vdm_attributes, var.defaults.account_vdm_attributes, null)
  active_receipt_rule_set_key                  = try(each.value.active_receipt_rule_set_key, var.defaults.active_receipt_rule_set_key, null)
  classic_configuration_set_event_destinations = try(each.value.classic_configuration_set_event_destinations, var.defaults.classic_configuration_set_event_destinations, {})
  classic_configuration_sets                   = try(each.value.classic_configuration_sets, var.defaults.classic_configuration_sets, {})
  classic_domain_identities                    = try(each.value.classic_domain_identities, var.defaults.classic_domain_identities, {})
  classic_email_identities                     = try(each.value.classic_email_identities, var.defaults.classic_email_identities, {})
  classic_identity_policies                    = try(each.value.classic_identity_policies, var.defaults.classic_identity_policies, {})
  classic_mail_from_domains                    = try(each.value.classic_mail_from_domains, var.defaults.classic_mail_from_domains, {})
  configuration_set_event_destinations         = try(each.value.configuration_set_event_destinations, var.defaults.configuration_set_event_destinations, {})
  configuration_sets                           = try(each.value.configuration_sets, var.defaults.configuration_sets, {})
  contact_lists                                = try(each.value.contact_lists, var.defaults.contact_lists, {})
  dedicated_ip_assignments                     = try(each.value.dedicated_ip_assignments, var.defaults.dedicated_ip_assignments, {})
  dedicated_ip_pools                           = try(each.value.dedicated_ip_pools, var.defaults.dedicated_ip_pools, {})
  domain_identities                            = try(each.value.domain_identities, var.defaults.domain_identities, {})
  email_identities                             = try(each.value.email_identities, var.defaults.email_identities, {})
  email_identity_feedback_attributes           = try(each.value.email_identity_feedback_attributes, var.defaults.email_identity_feedback_attributes, {})
  email_identity_policies                      = try(each.value.email_identity_policies, var.defaults.email_identity_policies, {})
  identity_notification_topics                 = try(each.value.identity_notification_topics, var.defaults.identity_notification_topics, {})
  mail_from_domains                            = try(each.value.mail_from_domains, var.defaults.mail_from_domains, {})
  receipt_filters                              = try(each.value.receipt_filters, var.defaults.receipt_filters, {})
  receipt_rule_sets                            = try(each.value.receipt_rule_sets, var.defaults.receipt_rule_sets, {})
  receipt_rules                                = try(each.value.receipt_rules, var.defaults.receipt_rules, {})
  ses_templates                                = try(each.value.ses_templates, var.defaults.ses_templates, {})
  tags                                         = try(each.value.tags, var.defaults.tags, {})
  tenant_resource_associations                 = try(each.value.tenant_resource_associations, var.defaults.tenant_resource_associations, {})
  tenants                                      = try(each.value.tenants, var.defaults.tenants, {})
  timeouts                                     = try(each.value.timeouts, var.defaults.timeouts, {})
}
