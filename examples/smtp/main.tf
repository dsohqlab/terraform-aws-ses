provider "aws" {
  region = var.aws_region
}

data "aws_partition" "current" {}

module "ses" {
  source  = "dsohqlab/ses/aws"
  version = "1.0.0"

  domain_identities = {
    main = {
      email_identity = var.domain_name
    }
  }

  account_suppression_attributes = null
  tags                           = var.tags
}

locals {
  smtp_permissions = {
    SendRawEmail = {
      actions   = ["ses:SendRawEmail"]
      resources = [module.ses.domain_identities["main"].arn]
    }
  }
}

module "iam_user" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-user"
  version = "6.11.2"

  name                 = var.iam_user_name
  create_login_profile = false
  create_access_key    = true
  pgp_key              = var.pgp_public_key

  create_inline_policy      = true
  inline_policy_permissions = local.smtp_permissions

  tags = var.tags
}

resource "aws_route53_record" "dkim" {
  count = var.dkim_signing_hosted_zone == null ? 0 : 3

  zone_id = var.route53_zone_id
  name    = "${module.ses.domain_identities["main"].dkim_tokens[count.index]}._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = ["${module.ses.domain_identities["main"].dkim_tokens[count.index]}.${var.dkim_signing_hosted_zone}"]
}
