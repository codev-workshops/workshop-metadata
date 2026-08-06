#!/usr/bin/env bash
# Credential-free IaC gate for hosting-client-timesheet-app: every stack must be formatted and
# valid. Runs `terraform init -backend=false` so no S3 backend or AWS credentials are needed.
#
# Usage: ./verify-terraform.sh [hosting_repo_path]
set -uo pipefail

REPO="${1:-$HOME/repos/hosting-client-timesheet-app}"
pass=0; fail=0

command -v terraform >/dev/null || { echo "terraform CLI not installed" >&2; exit 2; }

for dir in "$REPO"/terraform/*/; do
  stack=$(basename "$dir")
  out=$( (cd "$dir" && terraform init -backend=false -input=false -no-color \
          && terraform validate -no-color) 2>&1 )
  if [ $? -eq 0 ]; then printf 'PASS  %s validates\n' "$stack"; pass=$((pass+1))
  else printf 'FAIL  %s\n%s\n' "$stack" "$(printf '%s' "$out" | tail -n 12)"; fail=$((fail+1)); fi
done

out=$(terraform fmt -check -recursive "$REPO/terraform" 2>&1)
if [ -z "$out" ]; then printf 'PASS  terraform fmt is clean\n'; pass=$((pass+1))
else printf 'FAIL  terraform fmt would rewrite:\n%s\n' "$out"; fail=$((fail+1)); fi

echo
echo "SUMMARY: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
