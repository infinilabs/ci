#!/bin/sh
set -e

# Initialize Terraform for a given directory
terraform_init() {
  local dir=$1
  if [ -f "${dir}/main.tf" ]; then
    until [ -d "${dir}/.terraform" ]; do
      /terraform/terraform -chdir="${dir}" init
    done
  else
    for subdir in "${dir}"/*/; do
      terraform_init "$subdir"
    done
  fi
}

# Loop through terraform templates and initialize them
for template in ${terraform_templates}; do
  terraform_init "/terraform"
done
