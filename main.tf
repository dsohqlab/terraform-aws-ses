###############################################################################
# SESv2 - Email identities (domain + email address)
###############################################################################

resource "aws_sesv2_email_identity" "domain" {
  for_each = var.domain_identities

  email_identity         = each.value.email_identity
  configuration_set_name = each.value.configuration_set_name

  dynamic "dkim_signing_attributes" {
    for_each = each.value.dkim_signing_attributes != null ? [each.value.dkim_signing_attributes] : []
    content {
      domain_signing_private_key = try(dkim_signing_attributes.value.domain_signing_private_key, null)
      domain_signing_selector    = try(dkim_signing_attributes.value.domain_signing_selector, null)
    }
  }

  tags = var.tags
}

resource "aws_sesv2_email_identity" "email" {
  for_each = var.email_identities

  email_identity         = each.value.email_identity
  configuration_set_name = each.value.configuration_set_name

  tags = var.tags
}

resource "aws_sesv2_email_identity_policy" "this" {
  for_each = var.email_identity_policies

  email_identity = merge({ for k, v in aws_sesv2_email_identity.domain : k => v.email_identity }, { for k, v in aws_sesv2_email_identity.email : k => v.email_identity })[each.value.email_identity_key]
  policy_name    = each.value.policy_name
  policy         = each.value.policy
}

resource "aws_sesv2_email_identity_feedback_attributes" "this" {
  for_each = var.email_identity_feedback_attributes

  email_identity           = merge({ for k, v in aws_sesv2_email_identity.domain : k => v.email_identity }, { for k, v in aws_sesv2_email_identity.email : k => v.email_identity })[each.value.email_identity_key]
  email_forwarding_enabled = each.value.email_forwarding_enabled
}

###############################################################################
# SESv2 - Mail-From attributes (priority resource)
###############################################################################

resource "aws_sesv2_email_identity_mail_from_attributes" "this" {
  for_each = var.mail_from_domains

  email_identity         = merge({ for k, v in aws_sesv2_email_identity.domain : k => v.email_identity }, { for k, v in aws_sesv2_email_identity.email : k => v.email_identity })[each.value.email_identity_key]
  behavior_on_mx_failure = each.value.behavior_on_mx_failure
  mail_from_domain       = each.value.mail_from_domain
}

###############################################################################
# SESv2 - Configuration sets (priority resource)
###############################################################################

resource "aws_sesv2_configuration_set" "this" {
  for_each = var.configuration_sets

  configuration_set_name = each.value.configuration_set_name

  dynamic "delivery_options" {
    for_each = each.value.delivery_options != null ? [each.value.delivery_options] : []
    content {
      max_delivery_seconds = try(delivery_options.value.max_delivery_seconds, null)
      sending_pool_name    = try(delivery_options.value.sending_pool_name, null)
      tls_policy           = try(delivery_options.value.tls_policy, "REQUIRE")
    }
  }

  reputation_options {
    reputation_metrics_enabled = each.value.reputation_options.reputation_metrics_enabled
  }

  sending_options {
    sending_enabled = each.value.sending_options.sending_enabled
  }

  suppression_options {
    suppressed_reasons = each.value.suppression_options.suppressed_reasons
  }

  dynamic "tracking_options" {
    for_each = each.value.tracking_options != null ? [each.value.tracking_options] : []
    content {
      custom_redirect_domain = tracking_options.value.custom_redirect_domain
      https_policy           = try(tracking_options.value.https_policy, null)
    }
  }

  dynamic "vdm_options" {
    for_each = each.value.vdm_options != null ? [each.value.vdm_options] : []
    content {
      dynamic "dashboard_options" {
        for_each = vdm_options.value.dashboard_engagement_metrics != null ? [vdm_options.value.dashboard_engagement_metrics] : []
        content {
          engagement_metrics = dashboard_options.value
        }
      }

      dynamic "guardian_options" {
        for_each = vdm_options.value.guardian_optimized_shared_delivery != null ? [vdm_options.value.guardian_optimized_shared_delivery] : []
        content {
          optimized_shared_delivery = guardian_options.value
        }
      }
    }
  }

  tags = var.tags
}

###############################################################################
# SESv2 - Configuration set event destinations (priority resource)
###############################################################################

resource "aws_sesv2_configuration_set_event_destination" "this" {
  for_each = var.configuration_set_event_destinations

  configuration_set_name = aws_sesv2_configuration_set.this[each.value.configuration_set_key].configuration_set_name
  event_destination_name = each.value.event_destination_name

  event_destination {
    matching_event_types = each.value.matching_event_types
    enabled              = each.value.enabled

    dynamic "sns_destination" {
      for_each = each.value.sns_destination != null ? [each.value.sns_destination] : []
      content {
        topic_arn = sns_destination.value.topic_arn
      }
    }

    dynamic "cloud_watch_destination" {
      for_each = each.value.cloud_watch_destination != null ? [each.value.cloud_watch_destination] : []
      content {
        dynamic "dimension_configuration" {
          for_each = cloud_watch_destination.value.dimension_configurations
          content {
            default_dimension_value = dimension_configuration.value.default_dimension_value
            dimension_name          = dimension_configuration.value.dimension_name
            dimension_value_source  = dimension_configuration.value.dimension_value_source
          }
        }
      }
    }

    dynamic "event_bridge_destination" {
      for_each = each.value.event_bridge_destination != null ? [each.value.event_bridge_destination] : []
      content {
        event_bus_arn = event_bridge_destination.value.event_bus_arn
      }
    }

    dynamic "kinesis_firehose_destination" {
      for_each = each.value.kinesis_firehose_destination != null ? [each.value.kinesis_firehose_destination] : []
      content {
        delivery_stream_arn = kinesis_firehose_destination.value.delivery_stream_arn
        iam_role_arn        = kinesis_firehose_destination.value.iam_role_arn
      }
    }

    dynamic "pinpoint_destination" {
      for_each = each.value.pinpoint_destination != null ? [each.value.pinpoint_destination] : []
      content {
        application_arn = pinpoint_destination.value.application_arn
      }
    }
  }
}

###############################################################################
# SESv2 - Contact lists
###############################################################################

resource "aws_sesv2_contact_list" "this" {
  for_each = var.contact_lists

  contact_list_name = each.value.contact_list_name
  description       = each.value.description

  dynamic "topic" {
    for_each = each.value.topics
    content {
      topic_name                  = topic.value.topic_name
      display_name                = topic.value.display_name
      description                 = try(topic.value.description, null)
      default_subscription_status = topic.value.default_subscription_status
    }
  }

  tags = var.tags
}

###############################################################################
# SESv2 - Dedicated IP pools + assignment
###############################################################################

resource "aws_sesv2_dedicated_ip_pool" "this" {
  for_each = var.dedicated_ip_pools

  pool_name    = each.value.pool_name
  scaling_mode = each.value.scaling_mode

  tags = var.tags
}

resource "aws_sesv2_dedicated_ip_assignment" "this" {
  for_each = var.dedicated_ip_assignments

  ip                    = each.value.ip
  destination_pool_name = aws_sesv2_dedicated_ip_pool.this[each.value.pool_key].pool_name

  timeouts {
    create = var.timeouts.dedicated_ip_assignment_create
    delete = var.timeouts.dedicated_ip_assignment_delete
  }
}

###############################################################################
# SESv2 - Account-level suppression (SECURE DEFAULT - on) + VDM
###############################################################################

resource "aws_sesv2_account_suppression_attributes" "this" {
  for_each = var.account_suppression_attributes != null ? { this = var.account_suppression_attributes } : {}

  suppressed_reasons = each.value.suppressed_reasons
}

resource "aws_sesv2_account_vdm_attributes" "this" {
  for_each = var.account_vdm_attributes != null ? { this = var.account_vdm_attributes } : {}

  vdm_enabled = each.value.vdm_enabled

  dynamic "dashboard_attributes" {
    for_each = each.value.dashboard_engagement_metrics != null ? [each.value.dashboard_engagement_metrics] : []
    content {
      engagement_metrics = dashboard_attributes.value
    }
  }

  dynamic "guardian_attributes" {
    for_each = each.value.guardian_optimized_shared_delivery != null ? [each.value.guardian_optimized_shared_delivery] : []
    content {
      optimized_shared_delivery = guardian_attributes.value
    }
  }
}

###############################################################################
# SESv2 - Tenants
###############################################################################

resource "aws_sesv2_tenant" "this" {
  for_each = var.tenants

  tenant_name = each.value.tenant_name

  tags = var.tags
}

resource "aws_sesv2_tenant_resource_association" "this" {
  for_each = var.tenant_resource_associations

  tenant_name  = aws_sesv2_tenant.this[each.value.tenant_key].tenant_name
  resource_arn = each.value.resource_arn
}

###############################################################################
# Classic SES - Domain identities + auto DKIM + auto verification
###############################################################################

resource "aws_ses_domain_identity" "this" {
  for_each = var.classic_domain_identities

  domain = each.value.domain
}

resource "aws_ses_domain_dkim" "this" {
  for_each = { for k, v in var.classic_domain_identities : k => v if v.enable_dkim }

  domain = aws_ses_domain_identity.this[each.key].domain
}

resource "aws_ses_domain_identity_verification" "this" {
  for_each = { for k, v in var.classic_domain_identities : k => v if v.verify }

  domain = aws_ses_domain_identity.this[each.key].domain

  timeouts {
    create = var.timeouts.domain_identity_verification_create
  }
}

resource "aws_ses_email_identity" "this" {
  for_each = var.classic_email_identities

  email = each.value.email
}

###############################################################################
# Classic SES - Mail-From attributes
###############################################################################

resource "aws_ses_domain_mail_from" "this" {
  for_each = var.classic_mail_from_domains

  domain                 = merge({ for k, v in aws_ses_domain_identity.this : k => v.domain }, { for k, v in aws_ses_email_identity.this : k => v.email })[each.value.identity_key]
  mail_from_domain       = each.value.mail_from_domain
  behavior_on_mx_failure = each.value.behavior_on_mx_failure
}

###############################################################################
# Classic SES - Configuration sets + event destinations
###############################################################################

resource "aws_ses_configuration_set" "this" {
  for_each = var.classic_configuration_sets

  name                       = each.value.name
  sending_enabled            = each.value.sending_enabled
  reputation_metrics_enabled = each.value.reputation_metrics_enabled

  delivery_options {
    tls_policy = each.value.tls_policy
  }

  dynamic "tracking_options" {
    for_each = each.value.custom_redirect_domain != null ? [each.value.custom_redirect_domain] : []
    content {
      custom_redirect_domain = tracking_options.value
    }
  }
}

resource "aws_ses_event_destination" "this" {
  for_each = var.classic_configuration_set_event_destinations

  name                   = each.value.name
  configuration_set_name = aws_ses_configuration_set.this[each.value.configuration_set_key].name
  enabled                = each.value.enabled
  matching_types         = each.value.matching_types

  dynamic "cloudwatch_destination" {
    for_each = each.value.cloudwatch_destination != null ? [each.value.cloudwatch_destination] : []
    content {
      default_value  = cloudwatch_destination.value.default_value
      dimension_name = cloudwatch_destination.value.dimension_name
      value_source   = cloudwatch_destination.value.value_source
    }
  }

  dynamic "kinesis_destination" {
    for_each = each.value.kinesis_destination != null ? [each.value.kinesis_destination] : []
    content {
      stream_arn = kinesis_destination.value.stream_arn
      role_arn   = kinesis_destination.value.role_arn
    }
  }

  dynamic "sns_destination" {
    for_each = each.value.sns_destination != null ? [each.value.sns_destination] : []
    content {
      topic_arn = sns_destination.value.topic_arn
    }
  }
}

###############################################################################
# Classic SES - Identity notification topics + identity policies
###############################################################################

resource "aws_ses_identity_notification_topic" "this" {
  for_each = var.identity_notification_topics

  identity                 = each.value.identity
  notification_type        = each.value.notification_type
  topic_arn                = each.value.topic_arn
  include_original_headers = each.value.include_original_headers
}

resource "aws_ses_identity_policy" "this" {
  for_each = var.classic_identity_policies

  identity = each.value.identity
  name     = each.value.name
  policy   = each.value.policy
}

###############################################################################
# Classic SES - Account-level receipt filters
###############################################################################

resource "aws_ses_receipt_filter" "this" {
  for_each = var.receipt_filters

  name   = each.value.name
  cidr   = each.value.cidr
  policy = each.value.policy
}

###############################################################################
# Classic SES - Receipt rule sets + rules (priority - inbound processing)
###############################################################################

resource "aws_ses_receipt_rule_set" "this" {
  for_each = var.receipt_rule_sets

  rule_set_name = each.value.rule_set_name
}

resource "aws_ses_receipt_rule" "this" {
  for_each = var.receipt_rules

  name          = each.value.name
  rule_set_name = aws_ses_receipt_rule_set.this[each.value.rule_set_key].rule_set_name
  after         = each.value.after
  recipients    = each.value.recipients
  enabled       = each.value.enabled
  scan_enabled  = each.value.scan_enabled
  tls_policy    = each.value.tls_policy

  dynamic "add_header_action" {
    for_each = each.value.add_header_action != null ? [each.value.add_header_action] : []
    content {
      header_name  = add_header_action.value.header_name
      header_value = add_header_action.value.header_value
      position     = add_header_action.value.position
    }
  }

  dynamic "bounce_action" {
    for_each = each.value.bounce_action != null ? [each.value.bounce_action] : []
    content {
      message         = bounce_action.value.message
      sender          = bounce_action.value.sender
      smtp_reply_code = bounce_action.value.smtp_reply_code
      status_code     = try(bounce_action.value.status_code, null)
      topic_arn       = try(bounce_action.value.topic_arn, null)
      position        = bounce_action.value.position
    }
  }

  dynamic "lambda_action" {
    for_each = each.value.lambda_action != null ? [each.value.lambda_action] : []
    content {
      function_arn    = lambda_action.value.function_arn
      invocation_type = try(lambda_action.value.invocation_type, null)
      topic_arn       = try(lambda_action.value.topic_arn, null)
      position        = lambda_action.value.position
    }
  }

  dynamic "s3_action" {
    for_each = each.value.s3_action != null ? [each.value.s3_action] : []
    content {
      bucket_name       = s3_action.value.bucket_name
      iam_role_arn      = try(s3_action.value.iam_role_arn, null)
      kms_key_arn       = try(s3_action.value.kms_key_arn, null)
      object_key_prefix = try(s3_action.value.object_key_prefix, null)
      topic_arn         = try(s3_action.value.topic_arn, null)
      position          = s3_action.value.position
    }
  }

  dynamic "sns_action" {
    for_each = each.value.sns_action != null ? [each.value.sns_action] : []
    content {
      topic_arn = sns_action.value.topic_arn
      encoding  = try(sns_action.value.encoding, "UTF-8")
      position  = sns_action.value.position
    }
  }

  dynamic "stop_action" {
    for_each = each.value.stop_action != null ? [each.value.stop_action] : []
    content {
      scope     = try(stop_action.value.scope, "RuleSet")
      topic_arn = try(stop_action.value.topic_arn, null)
      position  = stop_action.value.position
    }
  }

  dynamic "workmail_action" {
    for_each = each.value.workmail_action != null ? [each.value.workmail_action] : []
    content {
      organization_arn = workmail_action.value.organization_arn
      topic_arn        = try(workmail_action.value.topic_arn, null)
      position         = workmail_action.value.position
    }
  }
}

resource "aws_ses_active_receipt_rule_set" "this" {
  for_each = var.active_receipt_rule_set_key != null ? { this = var.active_receipt_rule_set_key } : {}

  rule_set_name = aws_ses_receipt_rule_set.this[each.value].rule_set_name
}

###############################################################################
# Classic SES - Templates
###############################################################################

resource "aws_ses_template" "this" {
  for_each = var.ses_templates

  name    = each.value.name
  subject = each.value.subject
  html    = each.value.html
  text    = each.value.text
}
