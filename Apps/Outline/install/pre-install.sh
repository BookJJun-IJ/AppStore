#!/bin/bash
set -e

# Check required PCS environment variables
if [ -z "$PCS_DOMAIN" ]; then
  echo "Error: PCS_DOMAIN is not set"
  exit 1
fi

if [ -z "$PCS_DEFAULT_PASSWORD" ]; then
  echo "Error: PCS_DEFAULT_PASSWORD is not set"
  exit 1
fi

if [ -z "$APP_DOMAIN" ]; then
  echo "Error: APP_DOMAIN is not set"
  exit 1
fi

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

# Create directories
echo "Creating directories..."
mkdir -p /DATA/AppData/outline/data /DATA/AppData/outline/pgdata /DATA/AppData/outline/redis /DATA/AppData/outline/dex
mkdir -p /DATA/AppData/casaos/apps/outline
chown -R ${PUID}:${PGID} /DATA/AppData/outline || true
chown -R ${PUID}:${PGID} /DATA/AppData/casaos/apps/outline || true

# Generate .env secrets if not already present (idempotent)
ENV_FILE="/DATA/AppData/casaos/apps/outline/.env"
if [ ! -s "$ENV_FILE" ]; then
  echo "Generating secrets..."

  OUTLINE_SECRET_KEY=$(openssl rand -hex 32)
  OUTLINE_UTILS_SECRET=$(openssl rand -hex 32)
  OUTLINE_OIDC_SECRET=$(openssl rand -hex 32)

  cat > "$ENV_FILE" << EOF
OUTLINE_SECRET_KEY=${OUTLINE_SECRET_KEY}
OUTLINE_UTILS_SECRET=${OUTLINE_UTILS_SECRET}
OUTLINE_OIDC_SECRET=${OUTLINE_OIDC_SECRET}
EOF

  chown ${PUID}:${PGID} "$ENV_FILE" || true
  echo "Secrets generated."
else
  echo "Secrets already exist, skipping generation."
fi

# Source secrets for Dex config generation
. "$ENV_FILE"

# Generate Dex config if not already present (idempotent)
DEX_CONFIG="/DATA/AppData/outline/dex/config.yaml"
if [ ! -f "$DEX_CONFIG" ]; then
  echo "Generating Dex OIDC configuration..."

  # Generate bcrypt hash for default password using Dex container
  echo "Generating password hash..."
  BCRYPT_HASH=$(docker run --rm ghcr.io/dexidp/dex:v2.45.1 dex hash "$PCS_DEFAULT_PASSWORD" 2>/dev/null || true)

  # Fallback: use htpasswd if dex hash fails
  if [ -z "$BCRYPT_HASH" ]; then
    echo "Dex hash failed, trying htpasswd fallback..."
    BCRYPT_HASH=$(docker run --rm python:3.12-alpine sh -c "pip install -q bcrypt && python3 -c \"import bcrypt; print(bcrypt.hashpw(b'$PCS_DEFAULT_PASSWORD', bcrypt.gensalt(10)).decode())\"" 2>/dev/null)
  fi

  if [ -z "$BCRYPT_HASH" ]; then
    echo "Error: Failed to generate bcrypt hash"
    exit 1
  fi

  PCS_EMAIL="${PCS_EMAIL:-admin@${PCS_DOMAIN}}"

  # Write Dex config with placeholders
  cat > "$DEX_CONFIG" << 'DEXEOF'
issuer: https://outline-auth-__APP_DOMAIN__

storage:
  type: sqlite3
  config:
    file: /data/dex.db

web:
  http: 0.0.0.0:5556

staticClients:
  - id: outline
    secret: __OIDC_SECRET__
    name: Outline
    redirectURIs:
      - https://outline-__APP_DOMAIN__/auth/oidc.callback

enablePasswordDB: true

staticPasswords:
  - email: "__PCS_EMAIL__"
    hash: "__BCRYPT_HASH__"
    username: admin
DEXEOF

  # Replace placeholders with actual values
  sed -i "s|__APP_DOMAIN__|${APP_DOMAIN}|g" "$DEX_CONFIG"
  sed -i "s|__OIDC_SECRET__|${OUTLINE_OIDC_SECRET}|g" "$DEX_CONFIG"
  sed -i "s|__PCS_EMAIL__|${PCS_EMAIL}|g" "$DEX_CONFIG"
  sed -i "s|__BCRYPT_HASH__|${BCRYPT_HASH}|g" "$DEX_CONFIG"

  chown ${PUID}:${PGID} "$DEX_CONFIG" || true
  echo "Dex configuration generated."
else
  echo "Dex configuration already exists, skipping generation."
fi

echo ""
echo "=== Pre-Install Complete! ==="
echo "Default login: ${PCS_EMAIL:-admin@${PCS_DOMAIN}} / (your PCS default password)"
echo ""
