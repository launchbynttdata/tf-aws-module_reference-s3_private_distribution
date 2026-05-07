# EC2 Windows Validation Example (Manual Reference)

Manual-use reference harness that validates end-to-end private S3 access from
a Windows Server 2022 instance via SSM Run Command (no public internet path).

**⚠️ This example is NOT part of the automated test suite.** Automated testing now uses the `examples/complete/` example, which deploys a Lambda function for faster, simpler network-path-only validation. 

**Use this example when**: You need to manually verify Windows-to-S3 endpoint connectivity in your own account, or you're debugging SSM/Session Manager behavior.

## Prerequisites

- AWS credentials with EC2, S3, SSM, and IAM permissions
- A `test.tfvars` based on the variable defaults (see `variables.tf`)

## Usage

```bash
terraform init
terraform apply -var-file test.tfvars

# Wait for the Windows instance to appear Online in SSM (typically 5–15 minutes).
# Check status:
aws ssm describe-instance-information \
  --region us-east-2 \
  --filters Key=InstanceIds,Values=$(terraform output -raw windows_instance_id)

# Run the 200/403/403 validation:
aws ssm send-command \
  --region us-east-2 \
  --document-name $(terraform output -raw ssm_validation_document_name) \
  --instance-ids $(terraform output -raw windows_instance_id)

# Retrieve results (replace COMMAND_ID):
aws ssm get-command-invocation \
  --region us-east-2 \
  --command-id COMMAND_ID \
  --instance-id $(terraform output -raw windows_instance_id)
```

## Networking

All SSM endpoints and the Windows instance are placed in `local.primary_az`
(the first available AZ). The S3 interface endpoint spans two AZs via the
`app_private_subnets`. No IGW or NAT — all AWS API traffic flows via VPC
interface endpoints.

## Validation Probes

| Probe | Expected | Meaning |
|---|---|---|
| `valid_existing_object` | 200 | Object reachable via endpoint |
| `invalid_missing_object` | 403 | Missing object returns 403 (not 404) over interface endpoint |
| `disallowed_bucket_object` | 403 | Endpoint policy blocks access to non-allowlisted bucket |
