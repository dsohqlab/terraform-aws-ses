provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  configuration_set_name = "${var.name}-transactional"
  receipt_rule_set_name  = "${var.name}-inbound"
  receipt_rule_name      = "${var.name}-store"
  mail_from_domain       = "bounce.${var.domain_name}"
  tags                   = merge({ ManagedBy = "Terraform", Example = "ses" }, var.tags)
}

resource "aws_sns_topic" "events" {
  name = "${var.name}-events"
  tags = local.tags
}

resource "aws_sns_topic_policy" "events" {
  arn = aws_sns_topic.events.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "sns:*"
        Resource  = aws_sns_topic.events.arn
      },
      {
        Sid       = "AllowSESPublish"
        Effect    = "Allow"
        Principal = { Service = "ses.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.events.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
            "AWS:SourceArn"     = "arn:${data.aws_partition.current.partition}:ses:${var.aws_region}:${data.aws_caller_identity.current.account_id}:configuration-set/${local.configuration_set_name}"
          }
        }
      }
    ]
  })
}

resource "aws_sqs_queue" "events" {
  name                      = "${var.name}-events"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
  tags                      = local.tags
}

resource "aws_sqs_queue_policy" "events" {
  queue_url = aws_sqs_queue.events.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowSNSSendMessage"
        Effect    = "Allow"
        Principal = { Service = "sns.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.events.arn
        Condition = {
          ArnEquals = { "aws:SourceArn" = aws_sns_topic.events.arn }
        }
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "events" {
  topic_arn            = aws_sns_topic.events.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.events.arn
  raw_message_delivery = true

  depends_on = [aws_sqs_queue_policy.events]
}

resource "aws_s3_bucket" "inbound" {
  count = var.enable_inbound ? 1 : 0

  bucket_prefix = "${var.name}-inbound-"
  force_destroy = false
  tags          = local.tags
}

resource "aws_s3_bucket_public_access_block" "inbound" {
  count = var.enable_inbound ? 1 : 0

  bucket                  = aws_s3_bucket.inbound[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "inbound" {
  count = var.enable_inbound ? 1 : 0

  bucket = aws_s3_bucket.inbound[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "inbound" {
  count = var.enable_inbound ? 1 : 0

  bucket = aws_s3_bucket.inbound[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowSESReceive"
        Effect    = "Allow"
        Principal = { Service = "ses.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.inbound[0].arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
            "AWS:SourceArn"     = "arn:${data.aws_partition.current.partition}:ses:${var.aws_region}:${data.aws_caller_identity.current.account_id}:receipt-rule-set/${local.receipt_rule_set_name}:receipt-rule/${local.receipt_rule_name}"
          }
        }
      }
    ]
  })
}

module "ses" {
  source  = "dsohqlab/ses/aws"
  version = "1.0.0"

  domain_identities = {
    main = {
      email_identity = var.domain_name
    }
  }

  mail_from_domains = {
    main = {
      email_identity_key     = "main"
      mail_from_domain       = local.mail_from_domain
      behavior_on_mx_failure = "USE_DEFAULT_VALUE"
    }
  }

  configuration_sets = {
    transactional = {
      configuration_set_name = local.configuration_set_name
      delivery_options = {
        tls_policy = "REQUIRE"
      }
      reputation_options = {
        reputation_metrics_enabled = true
      }
      suppression_options = {
        suppressed_reasons = ["BOUNCE", "COMPLAINT"]
      }
    }
  }

  configuration_set_event_destinations = {
    events = {
      configuration_set_key  = "transactional"
      event_destination_name = "${var.name}-events"
      matching_event_types   = ["SEND", "DELIVERY", "BOUNCE", "COMPLAINT", "REJECT"]
      sns_destination = {
        topic_arn = aws_sns_topic.events.arn
      }
    }
  }

  contact_lists = {
    newsletter = {
      contact_list_name = "${var.name}-newsletter"
      description       = "Example contact list for an opt-in newsletter"
      topics = [
        {
          topic_name                  = "updates"
          display_name                = "Updates"
          default_subscription_status = "OPT_OUT"
        }
      ]
    }
  }

  ses_templates = {
    welcome = {
      name    = "${var.name}-welcome"
      subject = "Welcome, {{name}}"
      html    = "<h1>Welcome, {{name}}</h1><p>Your subscription is ready.</p>"
      text    = "Welcome, {{name}}. Your subscription is ready."
    }
  }

  account_suppression_attributes = {
    suppressed_reasons = ["BOUNCE", "COMPLAINT"]
  }

  receipt_rule_sets = var.enable_inbound ? {
    inbound = {
      rule_set_name = local.receipt_rule_set_name
    }
  } : {}

  receipt_rules = var.enable_inbound ? {
    inbound = {
      rule_set_key = "inbound"
      name         = local.receipt_rule_name
      recipients   = [var.domain_name]
      scan_enabled = true
      tls_policy   = "Require"
      s3_action = {
        bucket_name       = aws_s3_bucket.inbound[0].id
        object_key_prefix = "emails/"
        position          = 1
      }
    }
  } : {}

  tags = local.tags

  depends_on = [
    aws_sns_topic_policy.events,
    aws_sns_topic_subscription.events,
    aws_s3_bucket_policy.inbound,
    aws_s3_bucket_public_access_block.inbound,
    aws_s3_bucket_server_side_encryption_configuration.inbound,
  ]
}

# The module's active-rule-set resource does not wait for the receipt rules.
resource "aws_ses_active_receipt_rule_set" "inbound" {
  count = var.enable_inbound && var.activate_receipt_rule_set ? 1 : 0

  rule_set_name = module.ses.receipt_rule_sets["inbound"].id

  depends_on = [module.ses]
}

resource "aws_route53_record" "dkim" {
  count = var.dkim_signing_hosted_zone == null ? 0 : 3

  zone_id = var.route53_zone_id
  name    = "${module.ses.domain_identities["main"].dkim_tokens[count.index]}._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = ["${module.ses.domain_identities["main"].dkim_tokens[count.index]}.${var.dkim_signing_hosted_zone}"]
}

resource "aws_route53_record" "mail_from_mx" {
  zone_id = var.route53_zone_id
  name    = local.mail_from_domain
  type    = "MX"
  ttl     = 300
  records = ["10 feedback-smtp.${var.aws_region}.amazonses.com"]
}

resource "aws_route53_record" "mail_from_spf" {
  zone_id = var.route53_zone_id
  name    = local.mail_from_domain
  type    = "TXT"
  ttl     = 300
  records = ["v=spf1 include:amazonses.com ~all"]
}

resource "aws_route53_record" "inbound_mx" {
  count = var.enable_inbound && var.activate_receipt_rule_set ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "MX"
  ttl     = 300
  records = ["10 inbound-smtp.${var.aws_region}.${data.aws_partition.current.dns_suffix}"]

  depends_on = [aws_ses_active_receipt_rule_set.inbound]
}
