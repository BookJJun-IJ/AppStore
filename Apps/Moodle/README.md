# Moodle LMS for Yundera

## Overview
This is a Yundera-optimized Moodle Learning Management System with **automatic HTTPS and CSS loading fix**.

## The CSS Loading Problem (and Solution)

### Why CSS Doesn't Load
Yundera uses HTTPS via NSL router (`https://8080-moodle-{user}.nsl.sh`), but Moodle's Bitnami image defaults to HTTP in its config.php. When a browser loads an HTTPS page that references HTTP resources (CSS/JS), it blocks them due to **Mixed Content** security policy.

Result: **Only text displays, no styling.**

### Our Solution
This docker-compose.yml includes an **automatic HTTPS fix** that:

1. Waits for Moodle to generate `config.php` during first boot
2. Automatically injects these settings:
   ```php
   $CFG->sslproxy = true;
   $CFG->wwwroot = 'https://' . $_SERVER['HTTP_HOST'];
   $CFG->reverseproxy = true;
   ```
3. Forces HTTPS detection so all CSS/JS/images load correctly

### Key Configuration
```yaml
command: >
  bash -c '
    # Background script waits for config.php
    # Then automatically injects HTTPS settings
    # Moodle runs normally with full styling!
  '
```

## Installation Notes

- **First install takes 5-10 minutes** - be patient!
- CSS will load automatically after config.php is fixed
- Check logs: `docker logs moodle-moodle-1`
- Look for: `✓ HTTPS fix applied! CSS will load correctly.`

## Default Credentials
- Username: `admin`
- Password: `$default_pwd` (set in CasaOS)

## Troubleshooting

### CSS Still Not Loading?
1. Check logs: `docker logs moodle-moodle-1 | grep "HTTPS fix"`
2. Verify config: `docker exec moodle-moodle-1 tail -30 /bitnami/moodle/config.php`
3. Should see: `// ===== YUNDERA HTTPS FIX =====`
4. Restart if needed: `docker restart moodle-moodle-1`

### Installation Stuck?
- Check MariaDB health: `docker ps` (should show "healthy")
- Wait full 10 minutes before troubleshooting
- Check database logs: `docker logs moodle-mariadb-1`

## Files Needed
- `icon.png` - Moodle logo (512x512)
- `thumbnail.png` - App thumbnail
- `screenshot-1.png` - Dashboard screenshot
- `screenshot-2.png` - Course view
- `screenshot-3.png` - Quiz interface

## Technical Details
- Bitnami Moodle 4.5.1
- MariaDB 11.3
- PHP with OpCache
- Auto-configured for HTTPS
- NSL router compatible
