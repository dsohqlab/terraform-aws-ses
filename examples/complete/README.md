# Complete Amazon SES example

This example uses the Registry module with a public Route 53 hosted zone to
configure:

- An SESv2 domain identity with Easy DKIM and a custom MAIL FROM domain.
- A TLS-required configuration set that publishes sending, delivery, bounce,
  complaint, and rejection events to SNS and an encrypted SQS queue.
- An opt-in newsletter contact list, a welcome template, and account-level
  bounce/complaint suppression.
- An optional classic SES receipt rule and private, SSE-S3-encrypted S3 bucket
  for inbound email.

The identity does not have a default configuration set. Specify the
`configuration_set_name` output in each send request to publish its events.
The example creates the queue but not a consumer; configure a consumer to
process its messages before the 14-day retention period expires.

## Prerequisites

- Terraform >= 1.12 and AWS provider >= 6.45, < 7.0. Terraform 1.12 is needed
  for the module's nullable input validations.
- AWS credentials with permissions for SES, Route 53, SNS, SQS, and, if enabled,
  S3. Use a test account; SES sending starts in a regional sandbox, where
  recipients must also be verified.
- A dedicated domain or subdomain and an existing public Route 53 hosted zone
  authoritative for it. Use a domain without existing conflicting SES
  identities or DNS records. The example creates records under that domain.
- For inbound mail, choose a [Region that supports SES email receiving](https://docs.aws.amazon.com/general/latest/gr/ses.html#ses_inbound_endpoints).
  Inbound TLS is required, so senders without TLS will be rejected.

**Account-wide changes:** this example manages the SES account suppression
settings for the entire account and Region. It sets both `BOUNCE` and
`COMPLAINT`, potentially changing settings used by other senders. Coordinate
with any existing Terraform state that manages those settings. Destroying the
example does not restore the previous settings.

Activating inbound mail replaces the account's existing active receipt rule
set in that Region and publishes an MX record for `domain_name`. It can disrupt
existing mail delivery. Review the current rule set and DNS before activating;
destroying this example will not restore the previous active rule set or DNS.

The example incurs AWS charges. SQS uses SQS-managed encryption (SSE-SQS) and
S3 uses SSE-S3; the SNS topic is not encrypted. For production, review message
retention, access controls, and SNS encryption, including the KMS permissions
needed for SES to publish to an encrypted topic.

## Run the example

The module source is `dsohqlab/ses/aws` version `1.0.0`, matching the module's
Registry documentation. It must be published before Registry-based
`terraform init` can succeed. If the first published version differs, update
the version in `main.tf`. To run against a checkout before publication, change
the module source to `../..` and remove its `version` argument.

From this directory, create an untracked `terraform.tfvars` with your own
values:

```hcl
aws_region      = "us-east-1"
name            = "ses-example"
domain_name     = "mail.example.com"
route53_zone_id = "Z1234567890"

tags = {
  Environment = "test"
}
```

```bash
terraform init
terraform plan
terraform apply
```

The first apply creates the identity and MAIL FROM records, but deliberately
does not create DKIM records yet. The AWS provider and module output the three
tokens but do not expose the per-identity `SigningHostedZone`. Obtain it from
the SES console or a current AWS CLI:

```bash
aws sesv2 get-email-identity \
  --region us-east-1 \
  --email-identity mail.example.com \
  --query 'DkimAttributes.SigningHostedZone' \
  --output text
```

Replace the region and domain with your values. Add the returned DNS name
(without a trailing dot) to `terraform.tfvars`, then run `terraform apply`
again:

```hcl
dkim_signing_hosted_zone = "dkim.us-east-1.amazonses.com" # Replace with the value returned by SES.
```

SES can return a different hosted zone for each identity and Region; do not
assume the example value. If the CLI does not return a hosted zone, obtain the
exact DKIM records from the SES console and publish them yourself instead.
Wait until SES reports the identity and MAIL FROM domain as verified before
sending. DNS propagation and verification can take time. Manage an appropriate
DMARC record separately.

To send a test message and inspect events, replace the example region and
addresses below with your own. The sender must belong to the verified domain;
in the SES sandbox, the recipient must also be verified. Your credentials need
permission to send email and receive SQS messages.

```bash
aws sesv2 send-email \
  --region us-east-1 \
  --from-email-address sender@mail.example.com \
  --destination '{"ToAddresses":["verified-recipient@example.com"]}' \
  --content '{"Simple":{"Subject":{"Data":"SES example"},"Body":{"Text":{"Data":"Hello from SES."}}}}' \
  --configuration-set-name "$(terraform output -raw configuration_set_name)"

aws sqs receive-message \
  --region us-east-1 \
  --queue-url "$(terraform output -raw events_queue_url)" \
  --wait-time-seconds 10
```

Receiving a queue message makes it temporarily invisible; delete it only
after processing it successfully.

### Optional inbound email

1. After verifying the identity, set `enable_inbound = true` and apply. This
   creates the bucket and receipt rule set but does not activate the rule set
   or publish the inbound MX record.
2. Verify the rule and S3 permissions, and confirm replacing any existing
   active rule set and MX record is safe. Set
   `activate_receipt_rule_set = true` and apply again. This activates the
   prepared rule set and publishes the inbound MX record. Messages addressed
   to the domain are stored under `emails/` in the `inbound_bucket_name` bucket.

Only one SES receipt rule set can be active per account and Region. Route 53
will not overwrite an unmanaged existing MX record automatically. An active
receipt rule set is not an IMAP mailbox; applications must read the stored S3
objects. The example manages activation separately from the module so it can
wait until the module has created the receipt rule.

## Cleanup and tests

After reviewing the account-wide effects, run `terraform destroy`. The inbound
bucket is not force-destroyed, so remove or retain any received messages
deliberately before destroying it. Suppression settings remain as configured.

Once initialized, `terraform test` runs the example's mocked tests without
creating AWS resources. Before publication, use the local source change
described above to test the current checkout.

Dedicated IPs, VDM, tenants, and cross-account authorization are intentionally
omitted because they require separate quotas, costs, or account-specific
configuration; see the module inputs for those options.
