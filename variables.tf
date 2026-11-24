###############################################################################
# SESv2 - Email identities (domain + email address)
###############################################################################

variable "domain_identities" {
  description = <<EOT
Map of SESv2 DOMAIN email identities.Each entry renders one aws_sesv2_email_identity with email_identity set to a domain (not a single mailbox address). This is the SESv2 keystone identity resource - mail_from_domains, configuration_set_event_destinations, and the classic receipt-rule inbound path all reference identities created here.

domain_identities = {
  main = {
    email_identity = "example.com"
    configuration_set_name = module.ses.configuration_sets_keys["transactional"]
  }
}

Per-entry fields:
- email_identity: (Required) The domain to verify, e.g. "example.com". FORCE-NEW - SESv2 has no rename; changing this destroys and recreates the identity and every mail-from / feedback attribute resource keyed to it.
- configuration_set_name: (Optional) Configuration set applied by default when sending from this identity. Null (default) sends with no default configuration set.
- dkim_signing_attributes: (Optional) Bring-your-own-DKIM. Supply domain_signing_private_key (1024/2048-bit RSA, base64, headers/newlines stripped) and domain_signing_selector together to use your own key pair instead of AWS Easy DKIM.
Leave null (default) to use AWS Easy DKIM, which auto-generates a rotating key pair and exposes CNAME tokens via this module's outputs.
EOT
  type = map(object({
    email_identity         = string
    configuration_set_name = optional(string)
    dkim_signing_attributes = optional(object({
      domain_signing_private_key = optional(string)
      domain_signing_selector    = optional(string)
    }))
  }))
  default = {}
}

variable "email_identities" {
  description = <<EOT
Map of SESv2 single-mailbox email identities (e.g. "support@example.com"), each rendering one aws_sesv2_email_identity with email_identity set to a full email address. Mailbox identities cannot carry a mail-from domain (that is a domain-level DNS construct) - use domain_identities for anything that needs mail_from_domains, DKIM CNAME records, or inbound receipt-rule routing.

email_identities = {
  support = {
    email_identity = "support@example.com"
  }
}

Per-entry fields:
- email_identity: (Required) FORCE-NEW. Full email address to verify. AWS emails a verification link to this address; the identity stays PENDING until the recipient clicks it (Terraform cannot complete this step - see README AWS Prerequisites).
- configuration_set_name: (Optional) Configuration set applied by default when sending from this identity.
EOT
  type = map(object({
    email_identity         = string
    configuration_set_name = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.email_identities : can(regex("^[^@]+@[^@]+\\.[^@]+$", v.email_identity))])
    error_message = "email_identities[*].email_identity must be a full email address (e.g. info@example.com); use domain_identities for bare domains."
  }
}

variable "email_identity_policies" {
  description = <<EOT
Map of SESv2 sending-authorization policies attached to a domain or email identity, keyed by a caller-chosen stable name. Each entry renders one aws_sesv2_email_identity_policy.

email_identity_policies = {
  cross-account-send = {
    email_identity_key = "main" # key into domain_identities or email_identities
    policy_name = "cross-account-send"
    policy = data.aws_iam_policy_document.cross_account.json
  }
}

Per-entry fields:
- email_identity_key: (Required) Key into var.domain_identities OR var.email_identities identifying which identity this policy attaches to. Keys must be unique across both maps for this lookup to be unambiguous.
- policy_name: (Required) Name of the policy.
- policy: (Required) JSON sending-authorization policy document (e.g. via data.aws_iam_policy_document).
EOT
  type = map(object({
    email_identity_key = string
    policy_name        = string
    policy             = string
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.email_identity_policies : can(jsondecode(v.policy))])
    error_message = "email_identity_policies[*].policy must be valid JSON."
  }
}

variable "email_identity_feedback_attributes" {
  description = <<EOT
Map of SESv2 feedback-forwarding toggles, each rendering one aws_sesv2_email_identity_feedback_attributes.
Controls whether bounce/complaint notifications are forwarded to the identity's own mailbox via email (in addition to any SNS/event-destination wiring configured elsewhere).

email_identity_feedback_attributes = {
  main = {
    email_identity_key = "main"
    email_forwarding_enabled = false
  }
}

Per-entry fields:
- email_identity_key: (Required) Key into var.domain_identities OR var.email_identities.
- email_forwarding_enabled: (Optional) Whether bounce/complaint notifications are emailed to the identity.
Defaults to false - baseline routes feedback through configuration-set event destinations (SNS/CloudWatch/Firehose) instead of ad hoc inbox forwarding.
EOT
  type = map(object({
    email_identity_key       = string
    email_forwarding_enabled = optional(bool, false)
  }))
  default = {}
}

###############################################################################
# SESv2 - Mail-From attributes (priority resource)
###############################################################################

variable "mail_from_domains" {
  description = <<EOT
Map of custom MAIL FROM domains for SESv2 identities, each rendering one aws_sesv2_email_identity_mail_from_attributes. Setting a custom MAIL FROM domain lets SMTP bounces reference your own subdomain (required for DMARC alignment) instead of amazonses.com.

mail_from_domains = {
  main = {
    email_identity_key = "main"
    mail_from_domain = "bounce.example.com"
    behavior_on_mx_failure = "REJECT_MESSAGE"
  }
}

Per-entry fields:
- email_identity_key: (Required) Key into var.domain_identities OR var.email_identities identifying the verified identity this MAIL FROM domain applies to.
- mail_from_domain: (Required) Subdomain of the identity's domain used as the MAIL FROM address, e.g. "bounce.example.com". Requires a caller-managed MX record (10 feedback-smtp.<region>.amazonses.com) and, for DMARC alignment, a TXT SPF record - wire both from terraform-aws-route53-zone; this module does not create DNS records.
- behavior_on_mx_failure: (Optional) "USE_DEFAULT_VALUE" (default, secure baseline - falls back to the amazonses.com MAIL FROM domain so mail keeps flowing if the custom MX record is missing/broken) or "REJECT_MESSAGE" (bounces the send instead of falling back - stricter DMARC alignment at the cost of availability if DNS drifts).
EOT
  type = map(object({
    email_identity_key     = string
    mail_from_domain       = string
    behavior_on_mx_failure = optional(string, "USE_DEFAULT_VALUE")
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.mail_from_domains : contains(["USE_DEFAULT_VALUE", "REJECT_MESSAGE"], v.behavior_on_mx_failure)])
    error_message = "mail_from_domains[*].behavior_on_mx_failure must be \"USE_DEFAULT_VALUE\" or \"REJECT_MESSAGE\"."
  }
}

###############################################################################
# SESv2 - Configuration sets (priority resource)
###############################################################################

variable "configuration_sets" {
  description = <<EOT
Map of SESv2 configuration sets, each rendering one aws_sesv2_configuration_set. A configuration set is the sending-behavior + reputation-tracking + suppression-list envelope you attach to an identity or reference at send time.

configuration_sets = {
  transactional = {
    configuration_set_name = "transactional"
    delivery_options = {
      tls_policy = "REQUIRE"
    }
  }
}

Per-entry fields:
- configuration_set_name: (Required) Name of the configuration set.
- delivery_options: (Optional) object({
  max_delivery_seconds = optional(number)
  sending_pool_name = optional(string)
  tls_policy = optional(string, "REQUIRE")
})
- tls_policy defaults to "REQUIRE" (secure baseline - messages are only delivered over a TLS-negotiated hop; set "OPTIONAL" only with a documented exception).
- reputation_options: (Optional) object({reputation_metrics_enabled = optional(bool, true)}) - defaults to true so bounce/complaint reputation is tracked from day one.
- sending_options: (Optional) object({ sending_enabled = optional(bool, true) })
- suppression_options: (Optional) object({ suppressed_reasons = optional(list(string), ["BOUNCE", "COMPLAINT"]) }) - defaults to suppressing both BOUNCE and COMPLAINT addresses account-wide for sends using this set (secure baseline; PII-bearing notices should never retry a bounced/complained address).
- tracking_options: (Optional) object({
  custom_redirect_domain = string
  https_policy = optional(string)
}) - open/click tracking redirect domain.
- vdm_options: (Optional) object({
  dashboard_engagement_metrics = optional(string)
  guardian_optimized_shared_delivery = optional(string)
}) - per-configuration-set Virtual
Deliverability Manager overrides. Each value is "ENABLED" or "DISABLED".
EOT
  type = map(object({
    configuration_set_name = string
    delivery_options = optional(object({
      max_delivery_seconds = optional(number)
      sending_pool_name    = optional(string)
      tls_policy           = optional(string, "REQUIRE")
    }))
    reputation_options = optional(object({
      reputation_metrics_enabled = optional(bool, true)
    }), {})
    sending_options = optional(object({
      sending_enabled = optional(bool, true)
    }), {})
    suppression_options = optional(object({
      suppressed_reasons = optional(list(string), ["BOUNCE", "COMPLAINT"])
    }), {})
    tracking_options = optional(object({
      custom_redirect_domain = string
      https_policy           = optional(string)
    }))
    vdm_options = optional(object({
      dashboard_engagement_metrics       = optional(string)
      guardian_optimized_shared_delivery = optional(string)
    }))
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.configuration_sets :
      v.delivery_options == null || v.delivery_options.tls_policy == null || contains(["REQUIRE", "OPTIONAL"], v.delivery_options.tls_policy)
    ])
    error_message = "configuration_sets[*].delivery_options.tls_policy must be \"REQUIRE\" or \"OPTIONAL\"."
  }

  validation {
    condition = alltrue([
      for k, v in var.configuration_sets :
      alltrue([for r in coalesce(v.suppression_options.suppressed_reasons, []) : contains(["BOUNCE", "COMPLAINT"], r)])
    ])
    error_message = "configuration_sets[*].suppression_options.suppressed_reasons entries must be \"BOUNCE\" or \"COMPLAINT\"."
  }

  validation {
    condition = alltrue([
      for k, v in var.configuration_sets :
      v.tracking_options == null || v.tracking_options.https_policy == null || contains(["REQUIRE", "REQUIRE_OPEN_ONLY", "OPTIONAL"], v.tracking_options.https_policy)
    ])
    error_message = "configuration_sets[*].tracking_options.https_policy must be \"REQUIRE\", \"REQUIRE_OPEN_ONLY\", or \"OPTIONAL\"."
  }
}

###############################################################################
# SESv2 - Configuration set event destinations (priority resource)
###############################################################################

variable "configuration_set_event_destinations" {
  description = <<EOT
Map of SESv2 event destinations attached to a configuration set, each rendering one aws_sesv2_configuration_set_event_destination. Exactly one destination block per entry should be populated (sns_destination, cloud_watch_destination, event_bridge_destination, kinesis_firehose_destination, or pinpoint_destination) - supplying more than one on the same entry is accepted by the type system but only the first non-null block the provider schema permits will apply; keep entries single-purpose.

configuration_set_event_destinations = {
  bounce-complaint = {
    configuration_set_key = "transactional"
    event_destination_name = "bounce-complaint-to-sns"
    matching_event_types = ["BOUNCE", "COMPLAINT"]
    sns_destination = {
      topic_arn = module.sns_bounce_complaint.arn
    }
  }
}

Per-entry fields:
- configuration_set_key: (Required) Key into var.configuration_sets.
- event_destination_name: (Required) Name of the event destination.
- matching_event_types: (Required) List of event types to forward. Each entry one of: "SEND", "REJECT", "BOUNCE", "COMPLAINT", "DELIVERY", "OPEN", "CLICK", "RENDERING_FAILURE", "DELIVERY_DELAY", "SUBSCRIPTION".
- enabled: (Optional) Whether the destination is active. Defaults to true.
- sns_destination: (Optional) object({ topic_arn = string }). Wire topic_arn from terraform-aws-sns (arn output).
- cloud_watch_destination: (Optional) object({
  dimension_configurations = list(object({
    default_dimension_value = string
    dimension_name = string
    dimension_value_source = string # MESSAGE_TAG | EMAIL_HEADER | LINK_TAG
  }))
})
- event_bridge_destination: (Optional) object({ event_bus_arn = string }). Only the default EventBridge bus is supported by the provider.
- kinesis_firehose_destination: (Optional) object({
  delivery_stream_arn = string
  iam_role_arn = string
})
- pinpoint_destination: (Optional) object({ application_arn = string }).
EOT
  type = map(object({
    configuration_set_key  = string
    event_destination_name = string
    matching_event_types   = list(string)
    enabled                = optional(bool, true)
    sns_destination = optional(object({
      topic_arn = string
    }))
    cloud_watch_destination = optional(object({
      dimension_configurations = list(object({
        default_dimension_value = string
        dimension_name          = string
        dimension_value_source  = string
      }))
    }))
    event_bridge_destination = optional(object({
      event_bus_arn = string
    }))
    kinesis_firehose_destination = optional(object({
      delivery_stream_arn = string
      iam_role_arn        = string
    }))
    pinpoint_destination = optional(object({
      application_arn = string
    }))
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.configuration_set_event_destinations :
      alltrue([for e in v.matching_event_types : contains(["SEND", "REJECT", "BOUNCE", "COMPLAINT", "DELIVERY", "OPEN", "CLICK", "RENDERING_FAILURE", "DELIVERY_DELAY", "SUBSCRIPTION"],
      e)])
    ])
    error_message = "configuration_set_event_destinations[*].matching_event_types entries must be valid SESv2 event types."
  }
}

###############################################################################
# SESv2 - Contact lists
###############################################################################

variable "contact_lists" {
  description = <<EOT
Map of SESv2 contact lists (bulk mailing-list / topic-preference subscriber management), each rendering one aws_sesv2_contact_list.

contact_lists = {
  marketing = {
    contact_list_name = "marketing"
    description = "Member newsletter and product updates"
    topics = [
      {
        topic_name = "monthly-newsletter"
        display_name = "Monthly Newsletter"
        default_subscription_status = "OPT_IN"
      }
    ]
  }
}

Per-entry fields:
- contact_list_name: (Required) Name of the contact list.
- description: (Optional) Free-text description.
- topics: (Optional) List of topic objects:
- topic_name: (Required)
- display_name: (Required)
- description: (Optional)
- default_subscription_status: (Required) One of "OPT_IN" or "OPT_OUT".
EOT
  type = map(object({
    contact_list_name = string
    description       = optional(string)
    topics = optional(list(object({
      topic_name                  = string
      display_name                = string
      description                 = optional(string)
      default_subscription_status = string
    })), [])
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.contact_lists :
      alltrue([for t in v.topics : contains(["OPT_IN", "OPT_OUT"], t.default_subscription_status)])
    ])
    error_message = "contact_lists[*].topics[*].default_subscription_status must be \"OPT_IN\" or \"OPT_OUT\"."
  }
}

###############################################################################
# SESv2 - Dedicated IP pools
###############################################################################

variable "dedicated_ip_pools" {
  description = <<EOT
Map of SESv2 dedicated IP pools, each rendering one aws_sesv2_dedicated_ip_pool. Dedicated IPs themselves are requested out-of-band via an AWS support case (or Bring-Your-Own-IP) - this module only manages the pool container and, optionally, assignment of an already-provisioned IP into it (see dedicated_ip_assignments).

dedicated_ip_pools = {
  bulk = {
    pool_name = "bulk-mail-pool"
    scaling_mode = "MANAGED"
  }
}

Per-entry fields:
- pool_name: (Required) Name of the dedicated IP pool.
- scaling_mode: (Optional) "STANDARD" (default - caller manages IP count via support cases) or "MANAGED" (AWS automatically scales the number of dedicated IPs in the pool for you).
EOT
  type = map(object({
    pool_name    = string
    scaling_mode = optional(string, "STANDARD")
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.dedicated_ip_pools : contains(["STANDARD", "MANAGED"], v.scaling_mode)])
    error_message = "dedicated_ip_pools[*].scaling_mode must be \"STANDARD\" or \"MANAGED\"."
  }
}

variable "dedicated_ip_assignments" {
  description = <<EOT
Map assigning an already-provisioned "Standard" dedicated IP address into one of var.dedicated_ip_pools, each rendering one aws_sesv2_dedicated_ip_assignment. Removing an entry returns the IP to the AWS-managed ses-default-dedicated-pool, NOT to no pool at all.

dedicated_ip_assignments = {
  bulk-ip-1 = {
    ip = "100.100.100.10"
    pool_key = "bulk"
  }
}

Per-entry fields:
- ip: (Required) The dedicated IP address (already provisioned via an AWS support case or BYOIP - this module does not provision IPs  themselves).
- pool_key: (Required) Key into var.dedicated_ip_pools identifying the destination pool.
EOT
  type = map(object({
    ip       = string
    pool_key = string
  }))
  default = {}
}

###############################################################################
# SESv2 - Account-level suppression (SECURE DEFAULT - on)
###############################################################################

variable "account_suppression_attributes" {
  description = <<EOT
Account-level (per-Region) suppression-list configuration, rendering one aws_sesv2_account_suppression_attributes when non-null. SECURE DEFAULT: non-null, suppressing both BOUNCE and COMPLAINT addresses account-wide, so a hard-bounced or complained-about recipient is never retried by any identity or configuration set in this account/Region unless a caller explicitly overrides suppression_options on a specific configuration set. Set this variable to null only to fully hand suppression-list management to a downstream process outside Terraform - NOT recommended for PII-bearing notification workloads.

account_suppression_attributes = {
  suppressed_reasons = ["BOUNCE", "COMPLAINT"]
}

Fields:
- suppressed_reasons: (Required when non-null) List of reasons - each "BOUNCE" or "COMPLAINT".
EOT
  type = object({
    suppressed_reasons = list(string)
  })
  default = {
    suppressed_reasons = ["BOUNCE", "COMPLAINT"]
  }

  validation {
    condition     = var.account_suppression_attributes == null || alltrue([for r in var.account_suppression_attributes.suppressed_reasons : contains(["BOUNCE", "COMPLAINT"], r)])
    error_message = "account_suppression_attributes.suppressed_reasons entries must be \"BOUNCE\" or \"COMPLAINT\"."
  }
}

###############################################################################
# SESv2 - Account-level VDM (Virtual Deliverability Manager)
###############################################################################

variable "account_vdm_attributes" {
  description = <<EOT
Account-level (per-Region) Virtual Deliverability Manager configuration, rendering one aws_sesv2_account_vdm_attributes when non-null. Null (default) leaves VDM unmanaged by this module - the account keeps whatever VDM state it already has (VDM is OFF by default on a new SES account).

account_vdm_attributes = {
  vdm_enabled = "ENABLED"
  dashboard_engagement_metrics = "ENABLED"
  guardian_optimized_shared_delivery = "ENABLED"
}

Fields:
- vdm_enabled: (Required when non-null) "ENABLED" or "DISABLED".
- dashboard_engagement_metrics: (Optional) "ENABLED" or "DISABLED".
- guardian_optimized_shared_delivery: (Optional) "ENABLED" or "DISABLED".
EOT
  type = object({
    vdm_enabled                        = string
    dashboard_engagement_metrics       = optional(string)
    guardian_optimized_shared_delivery = optional(string)
  })
  default = null

  validation {
    condition     = var.account_vdm_attributes == null || contains(["ENABLED", "DISABLED"], var.account_vdm_attributes.vdm_enabled)
    error_message = "account_vdm_attributes.vdm_enabled must be \"ENABLED\" or \"DISABLED\"."
  }
}

###############################################################################
# SESv2 - Tenants (multi-tenant sending isolation)
###############################################################################

variable "tenants" {
  description = <<EOT
Map of SESv2 tenants, each rendering one aws_sesv2_tenant. Tenants let a single SES account isolate sending reputation, resources, and metrics per downstream customer/business unit.

tenants = {
  acme-corp = {
    tenant_name = "acme-corp"
  }
}

Per-entry fields:
- tenant_name: (Required) FORCE-NEW. Unique per account/Region.
EOT
  type = map(object({
    tenant_name = string
  }))
  default = {}
}

variable "tenant_resource_associations" {
  description = <<EOT
Map associating an SES resource (by ARN) with a tenant, each rendering one aws_sesv2_tenant_resource_association. Typically associates a configuration set, email identity, or contact list with the owning tenant.

tenant_resource_associations = {
  acme-config-set = {
    tenant_key = "acme-corp"
    resource_arn = module.this_ses.configuration_sets["acme-transactional"].arn
  }
}

Per-entry fields:
- tenant_key: (Required) Key into var.tenants.
- resource_arn: (Required) ARN of the SES resource to associate.
EOT
  type = map(object({
    tenant_key   = string
    resource_arn = string
  }))
  default = {}
}

###############################################################################
# Classic SES - Domain identities (priority - inbound processing lives only in classic SES; SESv2 has no receipt-rule equivalent yet)
###############################################################################

variable "classic_domain_identities" {
  description = <<EOT
Map of classic-API SES domain identities. Each entry renders one aws_ses_domain_identity plus, per the enable_dkim / verify flags, an auto-attached aws_ses_domain_dkim and aws_ses_domain_identity_verification.

classic_domain_identities = {
  inbound = {
    domain = "mail.example.com"
  }
}

Per-entry fields:
- domain: (Required) FORCE-NEW. Domain name to assign to SES.
- enable_dkim: (Optional) Whether to auto-create a matching aws_ses_domain_dkim for this identity, generating the dkim_tokens this module surfaces so a caller can create the three DKIM CNAME records (wire from terraform-aws-route53-zone). Defaults to true.
- verify: (Optional) Whether to auto-create a matching aws_ses_domain_identity_verification, which POLLS DNS and blocks apply (up to its 45-minute timeout) until the _amazonses TXT verification record is visible. Defaults to true. Set false when you want to create the identity without blocking apply on external DNS propagation (e.g. a first-pass plan before the Route 53 record exists) - see the README Provider Gotchas section.
EOT
  type = map(object({
    domain      = string
    enable_dkim = optional(bool, true)
    verify      = optional(bool, true)
  }))
  default = {}
}

variable "classic_mail_from_domains" {
  description = <<EOT
Map of classic-API custom MAIL FROM domains, each rendering one aws_ses_domain_mail_from.

classic_mail_from_domains = {
  inbound = {
    identity_key = "inbound"
    identity_source = "classic_domain"
    mail_from_domain = "bounce.mail.example.com"
    behavior_on_mx_failure = "UseDefaultValue"
  }
}

Per-entry fields:
- identity_key: (Required) Key into var.classic_domain_identities or var.classic_email_identities (per identity_source).
- identity_source: (Optional) "classic_domain" (default) or "classic_email" - which map identity_key looks up.
- mail_from_domain: (Required) Subdomain used as the MAIL FROM address. Requires a caller-managed MX record (10 feedback-smtp.<region>.amazonses.com).
- behavior_on_mx_failure: (Optional) "UseDefaultValue" (default, secure baseline) or "RejectMessage". NOTE: classic SES uses PascalCase enum values here - SESv2's mail_from_domains variable uses SCREAMING_SNAKE ("USE_DEFAULT_VALUE") for the same concept; do not mix the two casings across APIs.
EOT
  type = map(object({
    identity_key           = string
    identity_source        = optional(string, "classic_domain")
    mail_from_domain       = string
    behavior_on_mx_failure = optional(string, "UseDefaultValue")
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.classic_mail_from_domains : contains(["UseDefaultValue", "RejectMessage"], v.behavior_on_mx_failure)])
    error_message = "classic_mail_from_domains[*].behavior_on_mx_failure must be \"UseDefaultValue\" or \"RejectMessage\"."
  }

  validation {
    condition     = alltrue([for k, v in var.classic_mail_from_domains : contains(["classic_domain", "classic_email"], v.identity_source)])
    error_message = "classic_mail_from_domains[*].identity_source must be \"classic_domain\" or \"classic_email\"."
  }
}

variable "classic_email_identities" {
  description = <<EOT
Map of classic-API single-mailbox email identities, each rendering one aws_ses_email_identity. AWS emails a verification link to the address; Terraform cannot complete that step.

classic_email_identities = {
  info = {
    email = "info@example.com"
  }
}

Per-entry fields:
- email: (Required) FORCE-NEW. Email address to verify.
EOT
  type = map(object({
    email = string
  }))
  default = {}
}

###############################################################################
# Classic SES - Configuration sets + event destinations
###############################################################################

variable "classic_configuration_sets" {
  description = <<EOT
Map of classic-API SES configuration sets, each rendering one aws_ses_configuration_set. Prefer SESv2 configuration_sets for new work - this exists for callers whose inbound receipt-rule pipeline (classic-only) needs a matching classic configuration set / event destination for delivery notifications.

classic_configuration_sets = {
  inbound-notify = {
    name = "inbound-notify"
  }
}

Per-entry fields:
- name: (Required) Name of the configuration set.
- sending_enabled: (Optional) Defaults to true.
- reputation_metrics_enabled: (Optional) Defaults to true (secure baseline - reputation tracked from day one).
- tls_policy: (Optional) "Require" (default, secure baseline) or "Optional".
- custom_redirect_domain: (Optional) Open/click tracking redirect domain.
EOT
  type = map(object({
    name                       = string
    sending_enabled            = optional(bool, true)
    reputation_metrics_enabled = optional(bool, true)
    tls_policy                 = optional(string, "Require")
    custom_redirect_domain     = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.classic_configuration_sets : contains(["Require", "Optional"], v.tls_policy)])
    error_message = "classic_configuration_sets[*].tls_policy must be \"Require\" or \"Optional\"."
  }
}

variable "classic_configuration_set_event_destinations" {
  description = <<EOT
Map of classic-API SES event destinations, each rendering one aws_ses_event_destination. Exactly one of cloudwatch_destination / kinesis_destination / sns_destination should be populated per entry (the provider forbids both cloudwatch_destination and kinesis_destination on the same resource).

classic_configuration_set_event_destinations = {
  inbound-bounce = {
    configuration_set_key = "inbound-notify"
    name = "inbound-bounce-to-sns"
    matching_types = ["bounce", "complaint"]
    sns_destination = {
      topic_arn = module.sns_bounce.arn
    }
  }
}

Per-entry fields:
- configuration_set_key: (Required) Key into var.classic_configuration_sets.
- name: (Required) Name of the event destination.
- enabled: (Optional) Defaults to true.
- matching_types: (Required) List of: "send", "reject", "bounce", "complaint", "delivery", "open", "click", "renderingFailure".
- cloudwatch_destination: (Optional) object({
  default_value = string
  dimension_name = string
  value_source = string # messageTag | emailHeader | linkTag
})
- kinesis_destination: (Optional) object({
  stream_arn = string
  role_arn = string
})
- sns_destination: (Optional) object({ topic_arn = string })
EOT
  type = map(object({
    configuration_set_key = string
    name                  = string
    enabled               = optional(bool, true)
    matching_types        = list(string)
    cloudwatch_destination = optional(object({
      default_value  = string
      dimension_name = string
      value_source   = string
    }))
    kinesis_destination = optional(object({
      stream_arn = string
      role_arn   = string
    }))
    sns_destination = optional(object({
      topic_arn = string
    }))
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.classic_configuration_set_event_destinations :
      alltrue([for t in v.matching_types : contains(["send", "reject", "bounce", "complaint", "delivery", "open", "click", "renderingFailure"], t)])
    ])
    error_message = "classic_configuration_set_event_destinations[*].matching_types entries must be valid classic SES matching types."
  }
}

###############################################################################
# Classic SES - Identity notification topics + identity policies
###############################################################################

variable "identity_notification_topics" {
  description = <<EOT
Map wiring classic Bounce/Complaint/Delivery SNS notifications directly onto a verified identity (independent of any configuration set), each rendering one aws_ses_identity_notification_topic. Pass the identity string directly (a domain name, email address, or identity ARN emitted by this module's own outputs) rather than a key lookup, since this resource can target any verified identity from either the SESv2 or classic surface.

identity_notification_topics = {
  inbound-bounce = {
    identity = "mail.example.com"
    notification_type = "Bounce"
    topic_arn = module.sns_bounce.arn
    include_original_headers = true
  }
}

Per-entry fields:
- identity: (Required) Identity name or ARN.
- notification_type: (Required) "Bounce", "Complaint", or "Delivery".
- topic_arn: (Optional) SNS topic ARN. Empty string ("") disables publishing for this notification type. Null defaults to "" (disabled).
- include_original_headers: (Optional) Defaults to false.
EOT
  type = map(object({
    identity                 = string
    notification_type        = string
    topic_arn                = optional(string, "")
    include_original_headers = optional(bool, false)
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.identity_notification_topics : contains(["Bounce", "Complaint", "Delivery"], v.notification_type)])
    error_message = "identity_notification_topics[*].notification_type must be \"Bounce\", \"Complaint\", or \"Delivery\"."
  }
}

variable "classic_identity_policies" {
  description = <<EOT
Map of classic-API sending - authorization policies, each rendering one aws_ses_identity_policy. Pass the identity string (name or ARN) directly.

classic_identity_policies = {
  cross-account = {
    identity = "mail.example.com"
    name = "cross-account-send"
    policy = data.aws_iam_policy_document.cross_account.json
  }
}

Per-entry fields:
- identity: (Required) Identity name or ARN.
- name: (Required) Name of the policy.
- policy: (Required) JSON sending-authorization policy document.
EOT
  type = map(object({
    identity = string
    name     = string
    policy   = string
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.classic_identity_policies : can(jsondecode(v.policy))])
    error_message = "classic_identity_policies[*].policy must be valid JSON."
  }
}

###############################################################################
# Classic SES - Account-level receipt filters (IP allow/block list)
###############################################################################

variable "receipt_filters" {
  description = <<EOT
Map of account-level IP address receipt filters, each rendering one aws_ses_receipt_filter. Applies to ALL inbound mail for the account/Region, independent of any receipt rule set.

receipt_filters = {
  block-known-spammer = {
    name = "block-known-spammer"
    cidr = "10.10.10.10/32"
    policy = "Block"
  }
}

Per-entry fields:
- name: (Required) Name of the filter.
- cidr: (Required) IP address or CIDR range to filter.
- policy: (Required) "Block" or "Allow".
EOT
  type = map(object({
    name   = string
    cidr   = string
    policy = string
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.receipt_filters : contains(["Block", "Allow"], v.policy)])
    error_message = "receipt_filters[*].policy must be \"Block\" or \"Allow\"."
  }
}

###############################################################################
# Classic SES - Receipt rule sets + rules (priority - inbound processing)
###############################################################################

variable "receipt_rule_sets" {
  description = <<EOT
Map of SES receipt rule sets, each rendering one aws_ses_receipt_rule_set. A rule set is an ordered container for receipt_rules; only one rule set per account/Region can be ACTIVE at a time (see active_receipt_rule_set_key).

receipt_rule_sets = {
  main = {
    rule_set_name = "main-rules"
  }
}

Per-entry fields:
- rule_set_name: (Required) FORCE-NEW. Name of the rule set.
EOT
  type = map(object({
    rule_set_name = string
  }))
  default = {}
}

variable "receipt_rules" {
  description = <<EOT
Map of SES receipt rules, each rendering one aws_ses_receipt_rule. Rules execute their action blocks in position order; this module supports at most one block of each action type per rule (chain multiple rules via `after` for more complex pipelines).

receipt_rules = {
  store-and-notify = {
    rule_set_key = "main"
    name = "store-and-notify"
    recipients = ["inbox@mail.example.com"]
    s3_action = {
      bucket_name = module.s3_inbound.id
      position = 1
      kms_key_arn = module.kms_inbound.arn
    }
    lambda_action = {
      function_arn = module.lambda_process_inbound.arn
      invocation_type = "Event"
      position = 2
    }
  }
}

Per-entry fields:
- rule_set_key: (Required) Key into var.receipt_rule_sets.
- name: (Required) Name of the rule.
- after: (Optional) Name of an existing rule (within the same rule set) to place this rule after.
- recipients: (Optional) List of recipient email addresses/domains this rule matches. Empty list (default) matches all recipients on the rule set's verified domains.
- enabled: (Optional) Defaults to true.
- scan_enabled: (Optional) Spam/virus scanning. Defaults to true (secure baseline - inbound PII-bearing mail is scanned before further processing).
- tls_policy: (Optional) "Require" or "Optional". Null (default) uses the AWS default (Optional).
- add_header_action: (Optional) object({ header_name, header_value, position }).
- bounce_action: (Optional) object({ message, sender, smtp_reply_code, status_code = optional(string), topic_arn = optional(string), position }).
- lambda_action: (Optional) object({ function_arn, invocation_type = optional(string), topic_arn = optional(string), position }).
- s3_action: (Optional) object({ bucket_name, iam_role_arn = optional(string), kms_key_arn = optional(string), object_key_prefix = optional(string), topic_arn = optional(string), position }). kms_key_arn null (default) stores the object under Amazon S3-managed keys (SSE-S3) supply a CMK for PII-bearing inbound mail (secure baseline recommends always setting this).
- sns_action: (Optional) object({ topic_arn, encoding = optional(string, "UTF-8"), position }).
- stop_action: (Optional) object({ scope = optional(string, "RuleSet"), topic_arn = optional(string), position }).
- workmail_action: (Optional) object({ organization_arn, topic_arn = optional(string), position }).
EOT
  type = map(object({
    rule_set_key = string
    name         = string
    after        = optional(string)
    recipients   = optional(list(string), [])
    enabled      = optional(bool, true)
    scan_enabled = optional(bool, true)
    tls_policy   = optional(string)

    add_header_action = optional(object({
      header_name  = string
      header_value = string
      position     = number
    }))
    bounce_action = optional(object({
      message         = string
      sender          = string
      smtp_reply_code = string
      status_code     = optional(string)
      topic_arn       = optional(string)
      position        = number
    }))
    lambda_action = optional(object({
      function_arn    = string
      invocation_type = optional(string)
      topic_arn       = optional(string)
      position        = number
    }))
    s3_action = optional(object({
      bucket_name       = string
      iam_role_arn      = optional(string)
      kms_key_arn       = optional(string)
      object_key_prefix = optional(string)
      topic_arn         = optional(string)
      position          = number
    }))
    sns_action = optional(object({
      topic_arn = string
      encoding  = optional(string, "UTF-8")
      position  = number
    }))
    stop_action = optional(object({
      scope     = optional(string, "RuleSet")
      topic_arn = optional(string)
      position  = number
    }))
    workmail_action = optional(object({
      organization_arn = string
      topic_arn        = optional(string)
      position         = number
    }))
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.receipt_rules : v.tls_policy == null || contains(["Require", "Optional"], v.tls_policy)])
    error_message = "receipt_rules[*].tls_policy must be \"Require\", \"Optional\", or null."
  }

  validation {
    condition     = alltrue([for k, v in var.receipt_rules : v.stop_action == null || v.stop_action.scope == "RuleSet"])
    error_message = "receipt_rules[*].stop_action.scope only accepts \"RuleSet\" in the current AWS provider schema."
  }
}

variable "active_receipt_rule_set_key" {
  description = "Key into var.receipt_rule_sets designating that rule set as the account's single ACTIVE receipt rule set, rendering one aws_ses_active_receipt_rule_set. Null (default) leaves the active rule set unmanaged by this module - no inbound mail will be processed by ANY rule set until either this module or an out-of-band process activates one."
  type        = string
  default     = null
}

###############################################################################
# Classic SES - Templates
###############################################################################

variable "ses_templates" {
  description = <<EOT
Map of classic SES email templates, each rendering one aws_ses_template.

ses_templates = {
  welcome = {
    name = "welcome-email"
    subject = "Welcome, {{name}}!"
    html = "<h1>Welcome {{name}}</h1>"
    text = "Welcome {{name}}"
  }
}

Per-entry fields:
- name: (Required) Name of the template (max 64 characters).
- subject: (Required) Subject line.
- html: (Optional) HTML body. html + text combined must be < 500KB.
- text: (Optional) Plain-text body.
EOT
  type = map(object({
    name    = string
    subject = string
    html    = optional(string)
    text    = optional(string)
  }))
  default = {}
}

###############################################################################
# Universal tail
###############################################################################

variable "tags" {
  description = "A map of tags to assign to all taggable resources created by this module. Only 5 of the 27 resource types in this composite accept a tags argument in the current AWS provider schema: aws_sesv2_email_identity (both domain_identities and email_identities), aws_sesv2_configuration_set, aws_sesv2_contact_list, aws_sesv2_dedicated_ip_pool, and aws_sesv2_tenant. Every other resource here - including the ENTIRE classic SES surface (aws_ses_domain_identity, aws_ses_receipt_rule, aws_ses_template, etc.) and several SESv2 sub-resources (mail-from attributes, event destinations, tenant associations, account-level attributes) - has no tags/tags_all attribute at all in the AWS provider schema. These merge with provider-level default_tags; resource tags win on key conflict. The per-collection tags_all outputs reflect the merged set only for the 5 taggable resource types."
  type        = map(string)
  default     = {}
}

variable "timeouts" {
  description = "Optional Terraform operation timeouts. Only aws_ses_domain_identity_verification (create, default 45m - it polls DNS for the _amazonses TXT record) and aws_sesv2_dedicated_ip_assignment (create/delete, default 30m each) expose configurable timeouts blocks in the current AWS provider schema; every other resource in this composite uses the provider's fixed internal timeout."
  type = object({
    domain_identity_verification_create = optional(string, "45m")
    dedicated_ip_assignment_create      = optional(string, "30m")
    dedicated_ip_assignment_delete      = optional(string, "30m")
  })
  default = {}
}
