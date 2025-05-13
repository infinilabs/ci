#!/bin/sh
set -e

# Initialize Terraform for a given directory
terraform_init() {
  local dir=$1
  
  # Check main.tf file in the directory
  # If it exists, run terraform init
  # If it doesn't exist, check for subdirectories and run terraform init on them
  if [ -f "${dir}/main.tf" ]; then
    until [ -d "${dir}/.terraform" ]; do
      echo "Setting args with -chdir=${dir} for terraform init"
      /terraform/terraform -chdir="${dir}" init
    done
  else
    for subdir in "${dir}"/*/; do
      terraform_init "$subdir"
    done
  fi
}

terraform_init "/terraform"
