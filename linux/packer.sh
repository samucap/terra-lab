#!/usr/bin/env bash
# =============================================================================
# packer.sh — wrapper that loads .env and runs packer with mapped variables
# Usage: ./packer.sh build ubuntu-template.pkr.hcl
#        ./packer.sh validate ubuntu-template.pkr.hcl
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env file not found at $ENV_FILE" >&2
  exit 1
fi

# Source .env (handles quoted values)
set -a
source "$ENV_FILE"
set +a

# Map .env vars → PKR_VAR_* (Packer auto-reads these)
export PKR_VAR_initial_user="${INITIAL_USER:-samworker}"
export PKR_VAR_ssh_password=$(LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*()_+=' < /dev/urandom | head -c 20)
export PKR_VAR_allowed_subnet="${ALLOWED_SUBNET:-192.168.1.0/24}"
export PKR_VAR_iso_checksum="sha256:${ISO_CHECKSUM:-}"

# Generate SHA-512 hash of the password for cloud-init identity
export PKR_VAR_ssh_password_hash
PKR_VAR_ssh_password_hash=$(openssl passwd -6 "${PKR_VAR_ssh_password}")

exec packer "$@"
