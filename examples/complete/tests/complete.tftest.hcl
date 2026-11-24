mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:123456789012:ses-example-events"
    }
  }

  mock_resource "aws_sqs_queue" {
    defaults = {
      arn = "arn:aws:sqs:us-east-1:123456789012:ses-example-events"
      id  = "https://sqs.us-east-1.amazonaws.com/123456789012/ses-example-events"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn    = "arn:aws:s3:::ses-example-inbound-test"
      bucket = "ses-example-inbound-test"
      id     = "ses-example-inbound-test"
    }
  }

  mock_resource "aws_ses_receipt_rule_set" {
    defaults = {
      id = "ses-example-inbound"
    }
  }
}

variables {
  aws_region      = "us-east-1"
  name            = "ses-example"
  domain_name     = "mail.example.com"
  route53_zone_id = "ZEXAMPLE"
}

run "publish_dkim" {
  command = plan

  variables {
    dkim_signing_hosted_zone = "dkim.us-east-1.amazonses.com"
  }

  # Mocked providers cannot populate an unconfigured computed DKIM block.
  override_module {
    target = module.ses
    outputs = {
      domain_identities = {
        main = { dkim_tokens = ["token1", "token2", "token3"] }
      }
      mail_from_domains = { main = "bounce.mail.example.com" }
      configuration_sets = {
        transactional = { configuration_set_name = "ses-example-transactional" }
      }
      contact_lists = { newsletter = { id = "ses-example-newsletter" } }
      ses_templates = { welcome = { id = "ses-example-welcome" } }
    }
  }

  assert {
    condition = (
      length(aws_route53_record.dkim) == 3 &&
      alltrue([
        for i, token in ["token1", "token2", "token3"] :
        aws_route53_record.dkim[i].name == "${token}._domainkey.mail.example.com" &&
        one(aws_route53_record.dkim[i].records) == "${token}.dkim.us-east-1.amazonses.com"
      ])
    )
    error_message = "Easy DKIM must publish three records using the SES-provided signing hosted zone."
  }
}

run "initial_outbound" {
  command = apply

  assert {
    condition     = length(aws_route53_record.dkim) == 0 && length(aws_s3_bucket.inbound) == 0 && length(aws_route53_record.inbound_mx) == 0
    error_message = "The initial apply must not publish DKIM records without the SES hosted zone or enable inbound mail."
  }

  assert {
    condition     = one(aws_route53_record.mail_from_mx.records) == "10 feedback-smtp.us-east-1.amazonses.com" && one(aws_route53_record.mail_from_spf.records) == "v=spf1 include:amazonses.com ~all"
    error_message = "The MAIL FROM MX and SPF records must match the configured Region."
  }

  assert {
    condition = (
      jsondecode(aws_sns_topic_policy.events.policy).Statement[1].Condition.StringEquals["AWS:SourceArn"] ==
      "arn:aws:ses:us-east-1:123456789012:configuration-set/ses-example-transactional" &&
      jsondecode(aws_sns_topic_policy.events.policy).Statement[1].Condition.StringEquals["AWS:SourceAccount"] ==
      "123456789012" &&
      jsondecode(aws_sqs_queue_policy.events.policy).Statement[0].Condition.ArnEquals["aws:SourceArn"] ==
      aws_sns_topic.events.arn &&
      aws_sns_topic_subscription.events.endpoint == aws_sqs_queue.events.arn &&
      aws_sns_topic_subscription.events.raw_message_delivery
    )
    error_message = "SES and SNS publish permissions must be restricted to the example's configuration set and topic."
  }
}

run "prepare_inbound" {
  command = apply

  variables {
    enable_inbound = true
  }

  assert {
    condition = (
      length(aws_s3_bucket.inbound) == 1 &&
      contains(keys(module.ses.receipt_rules), "inbound") &&
      length(aws_ses_active_receipt_rule_set.inbound) == 0 &&
      length(aws_route53_record.inbound_mx) == 0
    )
    error_message = "Preparing inbound mail must create the receipt rule without activating it or publishing the inbound MX record."
  }

  assert {
    condition = (
      jsondecode(aws_s3_bucket_policy.inbound[0].policy).Statement[0].Condition.StringEquals["AWS:SourceArn"] ==
      "arn:aws:ses:us-east-1:123456789012:receipt-rule-set/ses-example-inbound:receipt-rule/ses-example-store" &&
      jsondecode(aws_s3_bucket_policy.inbound[0].policy).Statement[0].Condition.StringEquals["AWS:SourceAccount"] ==
      "123456789012"
    )
    error_message = "The inbound bucket must permit only the example's SES receipt rule to write."
  }
}

run "activate_inbound" {
  command = apply

  variables {
    enable_inbound            = true
    activate_receipt_rule_set = true
  }

  assert {
    condition = (
      aws_ses_active_receipt_rule_set.inbound[0].rule_set_name == "ses-example-inbound" &&
      one(aws_route53_record.inbound_mx[0].records) == "10 inbound-smtp.us-east-1.amazonaws.com"
    )
    error_message = "Activation must select the prepared rule set and publish the Region's inbound MX record."
  }
}

run "reject_activation_without_inbound" {
  command = plan

  variables {
    enable_inbound            = false
    activate_receipt_rule_set = true
  }

  expect_failures = [var.activate_receipt_rule_set]
}

run "reject_missing_dkim_zone" {
  command = plan

  variables {
    dkim_signing_hosted_zone = "None"
  }

  expect_failures = [var.dkim_signing_hosted_zone]
}
