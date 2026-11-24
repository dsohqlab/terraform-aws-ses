# Amazon SES SMTP authentication example

This standalone example creates an SESv2 domain identity and a dedicated IAM
user using `terraform-aws-modules/iam/aws//modules/iam-user`. The user has no
console login and can only call `ses:SendRawEmail` for the example identity.
Its SMTP username is the IAM access key ID; its regional SMTP password is
derived from the secret key and encrypted with your PGP public key.

## Prerequisites

- Terraform >= 1.12, AWS provider >= 6.45 and < 7.0, AWS CLI, GnuPG, and AWS
  credentials authorized to manage SES identities, Route 53 records, IAM
  users, inline policies, and access keys.
- A dedicated domain or subdomain and an existing public Route 53 hosted zone
  authoritative for it. Do not manage the same SES identity or DNS records in
  multiple Terraform states. To use an existing identity, reuse its ARN and
  omit these resources, or migrate ownership deliberately.
- An encryption-capable PGP key pair, for example an RSA key pair created
  with `gpg --full-generate-key`. Keep the private key secure.
- A Region with SES SMTP and IAM-based SMTP credentials. AWS recommends
  [Mail Manager](https://docs.aws.amazon.com/ses/latest/dg/smtp-credentials-mail-manager.html);
  it is the only SMTP credential option in opt-in Regions and the European
  Sovereign Cloud. This example does not provision Mail Manager.
- A sender in the verified domain. In the SES sandbox, recipients must also
  be verified unless using the mailbox simulator; request production access
  to send to unverified recipients.

This example deliberately leaves account-level suppression settings unchanged
and unmanaged. It creates AWS resources that can incur charges.

## Deploy

The SES module source is `dsohqlab/ses/aws` version `1.0.0`, matching the
Registry documentation. It must be published before Registry-based
`terraform init` can succeed. If the first published version differs, update
the version in `main.tf`. To test a checkout before publication, change the SES
module source to `../..` and remove its `version` argument. The IAM module
continues to use the published Registry source.

From this directory, create an untracked `terraform.tfvars` with your values:

```hcl
aws_region      = "us-east-1"
domain_name     = "mail.example.com"
route53_zone_id = "Z1234567890"
iam_user_name   = "ses-smtp-example"

tags = {
  Environment = "test"
}
```

IAM user names are account-wide; select a unique name. Export the **binary**
public key, without ASCII armor, as a Terraform variable. Replace the
fingerprint with your own:

```bash
gpg --list-secret-keys --keyid-format LONG
export TF_VAR_pgp_public_key="$(gpg --export 'YOUR_PGP_FINGERPRINT' | base64 | tr -d '\n')"

terraform init
terraform plan
terraform apply
```

Keep `TF_VAR_pgp_public_key` available for subsequent Terraform commands. The
first apply creates the identity and user but does not publish DKIM records.
Obtain the identity-specific hosted zone from the SES console or AWS CLI:

```bash
aws sesv2 get-email-identity \
  --region us-east-1 \
  --email-identity mail.example.com \
  --query 'DkimAttributes.SigningHostedZone' \
  --output text
```

Replace the region and domain with your values. Add the returned DNS name
without a trailing dot to `terraform.tfvars`, and apply again:

```hcl
dkim_signing_hosted_zone = "dkim.us-east-1.amazonses.com" # Replace with the value returned by SES.
```

```bash
terraform apply
```

SES can return a different hosted zone for each identity and Region; do not
assume the example value. If SES does not return a hosted zone, obtain the
exact DKIM records from the SES console and publish them yourself instead.
Wait for DNS propagation and for SES to report the identity as verified
before sending. Manage an appropriate DMARC record separately.

## Configure and test SMTP

Use the `smtp_endpoint` output with STARTTLS on port 587, the `smtp_username`
output as the username, and the **decrypted** `smtp_password_encrypted` output
as the password. The provider derives this password for `aws_region`: use the
same Region for the identity and endpoint. The AWS secret access key is not
the SMTP password. Verify `smtp_pgp_key_fingerprint` matches your public key.

These commands reveal the username and password on your terminal; run them
only in a secure session and avoid logging or saving plaintext credentials:

```bash
terraform output -raw smtp_endpoint
terraform output -raw smtp_username
terraform output -raw smtp_password_encrypted | base64 --decode | gpg --decrypt
```

Alternatively, after verification, send a test message without printing the
password. Replace both email addresses below. Python 3 and access to the PGP
private key are required:

```bash
python3 - <<'PY'
import base64
import smtplib
import ssl
import subprocess
from email.message import EmailMessage

sender = "sender@mail.example.com"
recipient = "verified-recipient@example.com"

def output(name):
    return subprocess.check_output(["terraform", "output", "-raw", name], text=True)

encrypted = base64.b64decode(output("smtp_password_encrypted"), validate=True)
password = subprocess.run(
    ["gpg", "--decrypt"], input=encrypted, stdout=subprocess.PIPE, check=True
).stdout.decode()

message = EmailMessage()
message["From"] = sender
message["To"] = recipient
message["Subject"] = "SES SMTP example"
message.set_content("Hello from Amazon SES.")

with smtplib.SMTP(output("smtp_endpoint"), 587, timeout=30) as client:
    client.ehlo()
    client.starttls(context=ssl.create_default_context())
    client.ehlo()
    client.login(output("smtp_username"), password)
    client.send_message(message)
print("Message accepted by SES.")
PY
```

With the required PGP key, the AWS provider stores encrypted credentials
rather than the plaintext AWS secret or SMTP password in Terraform state.
The state still contains the access key ID and encrypted secrets: protect it
with encrypted storage and restricted access, protect the PGP private key,
and do not enable credential-revealing logs. Rotate credentials using an
overlapping replacement user or key, update clients, and then retire the old
credentials. The access key can also authenticate AWS API calls permitted by
the IAM policy.

## Cleanup and tests

Run `terraform destroy` when the example is no longer needed; this deletes its
IAM user, access key, SES identity, and managed DKIM records. Once initialized,
`terraform test` runs mocked tests without creating AWS resources. Before SES
module publication, use the local source change described above.
