#!/bin/bash

# Auto postinstall on first run
if [ ! -f /etc/yunohost/installed ]; then
  DOMAIN="${PCS_DOMAIN:-yunohost.local}"
  PASSWORD="${PCS_DEFAULT_PASSWORD:-admin}"
  EMAIL="${PCS_EMAIL:-admin@${DOMAIN}}"

  echo "[YunoHost] Running postinstall with domain: $DOMAIN"

  yunohost tools postinstall \
    --domain "$DOMAIN" \
    --username admin \
    --fullname "Admin" \
    --password "$PASSWORD" \
    --force-diskspace \
    --i-have-read-terms-of-services || {
      echo "[YunoHost] Postinstall failed, will retry on next start"
    }
fi

# Start systemd as PID 1
exec /sbin/init
