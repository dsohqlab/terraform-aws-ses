mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_sesv2_email_identity" {
    defaults = {
      arn = "arn:aws:ses:us-east-1:123456789012:identity/mail.example.com"
    }
  }

  mock_resource "aws_iam_user" {
    defaults = {
      arn = "arn:aws:iam::123456789012:user/ses-smtp-example"
    }
  }

  mock_resource "aws_iam_access_key" {
    defaults = {
      id                             = "AKIATESTEXAMPLE12345"
      encrypted_ses_smtp_password_v4 = "RU5DUllQVEVE"
      key_fingerprint                = "example-fingerprint"
    }
  }
}

variables {
  aws_region      = "us-east-1"
  domain_name     = "mail.example.com"
  route53_zone_id = "ZEXAMPLE"
  pgp_public_key  = "YWJjZA=="
}

run "publish_dkim" {
  command = plan

  variables {
    dkim_signing_hosted_zone = "provided-dkim.example.net"
  }

  override_module {
    target = module.ses
    outputs = {
      domain_identities = {
        main = {
          arn         = "arn:aws:ses:us-east-1:123456789012:identity/mail.example.com"
          dkim_tokens = ["token1", "token2", "token3"]
        }
      }
    }
  }

  assert {
    condition = (
      length(aws_route53_record.dkim) == 3 &&
      alltrue([
        for i, token in ["token1", "token2", "token3"] :
        aws_route53_record.dkim[i].name == "${token}._domainkey.mail.example.com" &&
        one(aws_route53_record.dkim[i].records) == "${token}.provided-dkim.example.net"
      ])
    )
    error_message = "Easy DKIM must publish three records using the SES-provided signing hosted zone."
  }
}

run "alternate_region_and_identity" {
  command = plan

  variables {
    aws_region  = "eu-west-1"
    domain_name = "mail.other.example"
  }

  override_module {
    target = module.ses
    outputs = {
      domain_identities = {
        main = {
          arn         = "arn:aws:ses:eu-west-1:123456789012:identity/mail.other.example"
          dkim_tokens = ["token1", "token2", "token3"]
        }
      }
    }
  }

  assert {
    condition = (
      output.smtp_endpoint == "email-smtp.eu-west-1.amazonaws.com" &&
      local.smtp_permissions.SendRawEmail.resources == ["arn:aws:ses:eu-west-1:123456789012:identity/mail.other.example"]
    )
    error_message = "The endpoint and policy must follow the configured Region and SES identity."
  }
}

run "smtp_credentials" {
  command = apply

  assert {
    condition = (
      length(local.smtp_permissions) == 1 &&
      local.smtp_permissions.SendRawEmail.actions == ["ses:SendRawEmail"] &&
      local.smtp_permissions.SendRawEmail.resources == ["arn:aws:ses:us-east-1:123456789012:identity/mail.example.com"]
    )
    error_message = "The SMTP user must only be granted SendRawEmail on the example's SES identity."
  }

  assert {
    condition = (
      nonsensitive(output.smtp_username) == "AKIATESTEXAMPLE12345" &&
      nonsensitive(output.smtp_password_encrypted) == "RU5DUllQVEVE" &&
      output.smtp_pgp_key_fingerprint == "example-fingerprint" &&
      output.smtp_endpoint == "email-smtp.us-east-1.amazonaws.com"
    )
    error_message = "The SMTP outputs must use the encrypted password and the configured Region."
  }

  assert {
    condition = (
      nonsensitive(module.iam_user.login_profile_password) == null &&
      length(aws_route53_record.dkim) == 0 &&
      !module.ses.account_suppression_enabled
    )
    error_message = "The initial apply must not create a console login, DKIM records, or account-level suppression settings."
  }
}

run "reject_empty_pgp_key" {
  command = plan

  variables {
    pgp_public_key = ""
  }

  expect_failures = [var.pgp_public_key]
}

run "reject_invalid_pgp_key" {
  command = plan

  variables {
    pgp_public_key = "not-base64"
  }

  expect_failures = [var.pgp_public_key]
}
