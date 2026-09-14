# Developer Guide — Adding an App

Quick reference for adding a new app to the Yundera AppStore. For the full spec, see [CONTRIBUTING.md](CONTRIBUTING.md).

---

## File Structure

```
Apps/
└── MyApp/
    ├── docker-compose.yml   # required
    ├── icon.png             # 192×192 px, transparent bg
    ├── thumbnail.png        # 784×442 px
    ├── screenshot-1.png     # 1280×720 px (at least one)
    └── rationale.md         # required if any exception is made
```

---

## Minimal Template

```yaml
name: myapp   # lowercase alnum + hyphen only. Must match container_name and store_app_id.

services:
  myapp:                                    # ← sidecar (public-facing)
    image: ghcr.io/yundera/nginx-hash-lock:main
    container_name: myapp                   # load-bearing — see Naming below
    restart: unless-stopped
    user: "0:0"
    expose:
      - "80"
    labels:
      caddy_0: myapp-${APP_DOMAIN}
      caddy_0.import: gateway_tls
      caddy_0.reverse_proxy: "{{upstreams 80}}"
      caddy_1: myapp-${APP_PUBLIC_IP_DASH}.nip.io
      caddy_1.import: gateway_tls
      caddy_1.reverse_proxy: "{{upstreams 80}}"
      caddy_2: myapp-${APP_PUBLIC_IP_DASH}.sslip.io
      caddy_2.reverse_proxy: "{{upstreams 80}}"
    environment:
      OIDC_REGISTRAR_URL: "http://auth-registrar:9092"
      BACKEND_HOST: "myapp-backend"
      BACKEND_PORT: "80"
      LISTEN_PORT: "80"
    depends_on:
      - myapp-backend
    cpu_shares: 80
    networks:
      - pcs

  myapp-backend:                            # ← actual app (internal only)
    image: someimage:1.2.3
    container_name: myapp-backend
    restart: unless-stopped
    user: "0:0"
    expose:
      - "80"
    environment:
      TZ: $TZ
    volumes:
      - /DATA/AppData/$AppID/data:/app/data
    cpu_shares: 50
    networks:
      - pcs

networks:
  pcs:
    name: pcs
    external: true

x-casaos:
  architectures:
    - amd64
    - arm64
  main: myapp                  # must point to the sidecar
  store_app_id: myapp          # must match top-level name:
  webui_port: 80
  index: /
  author: Yundera Team
  category: Utilities
  developer: OriginalDevName
  icon: https://cdn.jsdelivr.net/gh/BookJJun-IJ/AppStore@create/Apps/MyApp/icon.png
  thumbnail: https://cdn.jsdelivr.net/gh/BookJJun-IJ/AppStore@create/Apps/MyApp/thumbnail.png
  screenshot_link:
    - https://cdn.jsdelivr.net/gh/BookJJun-IJ/AppStore@create/Apps/MyApp/screenshot-1.png
  title:
    en_us: My App
  tagline:
    en_us: One-line description
    ko_kr: 한 줄 설명
  description:
    en_us: |
      Full description here.
    ko_kr: |
      전체 설명.
```

---

## Naming Convention (Critical)

The top-level `name:`, the sidecar service name, and `container_name` **must all match**.

```
name: myapp
services:
  myapp:           ← service name
    container_name: myapp   ← container_name
```

**Why it matters:** `auth-registrar` derives the OIDC `client_id` from the container name via PTR lookup on the `pcs` network. If these don't match, SSO registration silently breaks.

**Do NOT use** `auth-${APP_DOMAIN}` in any Caddy label — it collides with Authelia's own domain.

---

## Auth Patterns

### Pattern 1 — SSO only (app has no self-auth)
The minimal template above. SSO is handled entirely by the nginx-hash-lock sidecar. Nothing else needed.

**Examples:** Excalidraw, Gatus, Sist2

---

### Pattern 2 — SSO + disable app's self-auth
Some apps have their own login that must be disabled so users aren't prompted twice.

```yaml
  myapp-backend:
    environment:
      SECURITY_ENABLELOGIN: "false"    # example: Stirling-PDF
      # or
      AUTHENTICATION_ENABLED: "false"  # example: NoteDiscovery
      # or
      AUTH_MODE: "none"                # example: Suwayomi
```

**Examples:** Stirling-PDF, FileBrowser (`--noauth`), Ollama (`WEBUI_AUTH=false`), qBittorrent (AuthSubnetWhitelist via pre-install-cmd)

---

### Pattern 3 — App handles auth but can't be disabled
Add the sidecar as normal. On first visit the user will need to create an account inside the app. Document default credentials in `tips.before_install`.

```yaml
x-casaos:
  tips:
    before_install:
      en_us: |
        ## Default Credentials
        | Username | Password |
        |----------|----------|
        | `admin`  | `$APP_DEFAULT_PASSWORD` |
```

**Examples:** Jellyfin, Immich, n8n

---

## Pre-install Commands

Run on the host **before** any container starts. Use for directory setup, config file generation, or one-time initialization.

```yaml
x-casaos:
  pre-install-cmd: |
    mkdir -p /DATA/AppData/$AppID/config &&
    [ -f /DATA/AppData/$AppID/config/settings.ini ] || \
      printf '[server]\nport=80\n' > /DATA/AppData/$AppID/config/settings.ini
```

**Rules:**
- Always idempotent (guard with `[ -f ... ] ||` or `[ -d ... ] ||`)
- No `:latest` image tags if using `docker run`
- No hardcoded passwords — use `$APP_DEFAULT_PASSWORD`

---

## System Variables

| Variable | Example value | Usage |
|---|---|---|
| `$APP_DOMAIN` | `user.nsl.sh` | `https://myapp-${APP_DOMAIN}` |
| `$APP_PUBLIC_IP_DASH` | `192-168-1-1` | nip.io / sslip.io labels |
| `$APP_DEFAULT_PASSWORD` | (generated) | First-boot admin password |
| `$APP_EMAIL` | `admin@user.nsl.sh` | Admin email |
| `$AppID` | `myapp` | Volume paths: `/DATA/AppData/$AppID/` |
| `$PUID` / `$PGID` | `1000` / `1000` | File ownership |
| `$TZ` | `Asia/Seoul` | Timezone |

---

## CPU Shares

**Required on every service.**

| Value | Use case |
|---|---|
| `80` | Sidecars, web frontends |
| `70` | Main app with background tasks |
| `50` | Standard backend services |
| `30` | Databases, caches |
| `20` | ML / batch processing |

---

## Volume Paths

```yaml
volumes:
  - /DATA/AppData/$AppID/config/:/app/config    # app config
  - /DATA/AppData/$AppID/data/:/app/data        # app data / DB
  - /DATA/Media/Music/:/music:ro                 # shared media (read-only)
```

**Important:** Always add a trailing `/` to the **host side** (left side) of volume paths. Without it, CasaOS cannot resolve the `$AppID` path correctly and will create files directly in `/DATA/AppData/` instead of inside the app's folder.

```yaml
# CORRECT — host path ends with /
- /DATA/AppData/$AppID/config/:/etc/myapp
- /DATA/AppData/$AppID/data/:/app/data

# WRONG — missing trailing / on host path, files end up in /DATA/AppData/ directly
- /DATA/AppData/$AppID/config:/etc/myapp
- /DATA/AppData/$AppID/data:/app/data
```

The same rule applies to `pre-install-cmd`. Directory paths must end with `/`:

```yaml
# CORRECT
pre-install-cmd: |
  mkdir -p /DATA/AppData/$AppID/config/ /DATA/AppData/$AppID/data/

# WRONG — directories may be created at the wrong level
pre-install-cmd: |
  mkdir -p /DATA/AppData/$AppID/config /DATA/AppData/$AppID/data
```

User-facing directories (`/DATA/Documents/`, `/DATA/Downloads/`, `/DATA/Media/`, `/DATA/Gallery/`) require `user: $PUID:$PGID`.
AppData-only containers can use `user: 0:0`.

---

## Checklist Before PR

- [ ] `name:`, service name, `container_name`, `store_app_id` all match (lowercase alnum + `-`)
- [ ] Caddy labels only on the sidecar, not the backend
- [ ] `x-casaos.main` points to the sidecar
- [ ] No `:latest` image tags
- [ ] `cpu_shares` set on every service
- [ ] All data in `/DATA/AppData/$AppID/`
- [ ] `pre-install-cmd` is idempotent
- [ ] Auth is documented in `tips.before_install` or disabled
- [ ] `rationale.md` added if any exception applies
- [ ] Tested: fresh install → uninstall → reinstall (data survives)
