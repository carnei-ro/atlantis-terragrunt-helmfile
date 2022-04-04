#!/bin/sh

# New workspaces at Terraform Cloud are created with "Execution Mode" set to "Remote".
#   This script will patch the "Execution Mode" to "Local"

curl -s --connect-timeout 5 --retry 3 --retry-delay 10 \
  -o /dev/null -w "%{http_code}\n" \
  --header "Authorization: Bearer $(jq -r '.credentials."app.terraform.io".token' ~/.terraform.d/credentials.tfrc.json)" \
  --header 'Content-Type: application/vnd.api+json' --request PATCH \
  --data '{"data": {"type": "workspaces", "attributes": {"operations": false}}}' \
  https://app.terraform.io/api/v2/organizations/$1/workspaces/$2
