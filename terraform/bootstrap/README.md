# Aegis Terraform bootstrap

> **Applied once per AWS account. Do not re-apply.**
> Last applied: 2026-04-28 against account `023202272343` (eu-west-2).

This config creates the account-level resources every other env in this
repo depends on. It is **the one imperative step** in the project — every
later config uses the resources this bootstrap creates.

## What it creates

| Resource | Why |
|---|---|
| `aws_s3_bucket aegis-tf-state-<account_id>` | Remote state for every other env. Versioned, SSE-encrypted, public access blocked, deny-unencrypted/deny-insecure-transport bucket policy, 90-day non-current version expiry. `prevent_destroy = true`. |
| `module "budget"` (5 USD/day) | Account-level budget alarm with SNS fan-out (PROJECT.md §9 third teardown safety net). Two notifications: 80% and 100% ACTUAL. Email subscriber confirmed once on first apply. |

## State

This config keeps **local state** (no `backend "s3"` block) — the
chicken-and-egg of using S3 for state to manage the S3 bucket. The state
file is gitignored. If lost, see *Recovery* below.

Every other env (`envs/burst/`, future envs) uses the S3 backend that
this bootstrap created. Their `backend.tf` hardcodes the bucket name
including the account ID; switching accounts means editing those by hand.

## How to verify it's applied

```sh
AWS_PROFILE=aegis aws s3 ls s3://aegis-tf-state-023202272343
AWS_PROFILE=aegis aws budgets describe-budgets \
  --account-id 023202272343 \
  --query 'Budgets[].BudgetName'
```

Expected: bucket exists; budget list contains `aegis-daily-5usd`.

## Extending it

Add a new account-level resource (e.g. an OIDC provider for GitHub
Actions) here, **only if** it must outlive any individual env. Anything
env-specific belongs in `envs/<env>/`, not here.

After adding a resource, `terraform plan` (then `apply`) runs in this
directory. The bucket is `prevent_destroy`-protected so no replacement
operation will ever destroy it accidentally.

## Recovery

The state bucket has `prevent_destroy = true`, but if it disappears (e.g.
account compromised, hand-disposed):

1. Flip `prevent_destroy = false` on `aws_s3_bucket.tf_state` in
   `main.tf`, only as a deliberate edit on a feature branch.
2. `terraform apply` in this directory to re-create the bucket. Note the
   bucket name is deterministic (`<prefix>-<account_id>`).
3. Every other env's state is **lost** — you will need to either restore
   from S3 versioning (if the bucket was deleted but later versions
   recovered) or `terraform import` every resource manually. There is no
   automatic recovery; this is why the bucket has versioning + lifecycle
   protection in the first place.
4. Budget + SNS topic + subscription are recreated by the same apply.
   You'll need to click the new SNS confirmation email.

## Why not a `backend "s3"` block here?

The bootstrap manages the very bucket that backend would point at. If the
bucket doesn't exist yet, `terraform init` against an S3 backend fails.
Local state is the standard escape hatch and is documented as such in
`main.tf:8-13`. The state file is small (~5 KB) and committed-friendly,
but is gitignored as a precaution against accidental disclosure of
resource ARNs.

## Why not DynamoDB locking?

Terraform 1.10+ supports S3-native locking via `use_lockfile = true` in
the backend block. Every env in this repo uses that. Bootstrap doesn't
need locking because it's applied by exactly one human, exactly once.
See `main.tf:192-199` for the rationale.
