#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

for key in YC_CLOUD_ID YC_FOLDER_ID YC_SERVICE_ACCOUNT_ID TF_STATE_BUCKET YC_SERVICE_ACCOUNT_KEY YC_SERVICE_ACCOUNT_KEY_FILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY API_ALLOWED_CIDRS; do
  [[ -n "${!key:-}" ]] || { printf 'Missing GitHub Actions setting: %s\n' "$key" >&2; exit 1; }
done
for key in YC_CLOUD_ID YC_FOLDER_ID YC_SERVICE_ACCOUNT_ID; do
  [[ "${!key}" =~ ^[a-z0-9]{20}$ ]] || { printf 'Invalid ID setting: %s\n' "$key" >&2; exit 1; }
done
[[ "$TF_STATE_BUCKET" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]] || { echo 'Invalid bucket name.' >&2; exit 1; }

jq -e 'type == "array" and length > 0 and all(.[]; type == "string" and test("^[0-9]{1,3}(\\.[0-9]{1,3}){3}/32$"))' <<< "$API_ALLOWED_CIDRS" >/dev/null
while IFS= read -r cidr; do printf '::add-mask::%s\n' "$cidr"; done < <(jq -r '.[]' <<< "$API_ALLOWED_CIDRS")

printf '%s' "$YC_SERVICE_ACCOUNT_KEY" > "$YC_SERVICE_ACCOUNT_KEY_FILE"
jq -e --arg id "$YC_SERVICE_ACCOUNT_ID" '.service_account_id == $id and (.private_key | type == "string" and length > 100)' "$YC_SERVICE_ACCOUNT_KEY_FILE" >/dev/null

jq -n --arg cloud "$YC_CLOUD_ID" --arg folder "$YC_FOLDER_ID" --arg account "$YC_SERVICE_ACCOUNT_ID" --argjson cidrs "$API_ALLOWED_CIDRS" \
  '{cloud_id:$cloud, folder_id:$folder, service_account_id:$account, project_name:"diplom", api_allowed_cidrs:$cidrs}' > terraform/terraform.auto.tfvars.json

cat > terraform/backend.ci.hcl <<EOF
bucket = "$TF_STATE_BUCKET"
key    = "diploma/infrastructure.tfstate"
region = "ru-central1"
endpoints = { s3 = "https://storage.yandexcloud.net" }
skip_region_validation      = true
skip_credentials_validation = true
skip_requesting_account_id  = true
skip_metadata_api_check     = true
skip_s3_checksum            = true
use_path_style              = true
use_lockfile                = true
EOF
echo 'Terraform credentials and existing S3 backend prepared.'
