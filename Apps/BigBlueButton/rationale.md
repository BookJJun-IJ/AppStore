# BigBlueButton — Rationale

BigBlueButton 4.0.3 (community bbb-docker images) with Greenlight 3, meetings only:
audio, video, screen sharing, chat, shared notes, whiteboard, PDF/image presentations.
Recording, Collabora (office conversion), SIP dial-in, webhooks, the Prometheus exporter
and bbb-docker's own HTTPS proxy are left out.

## What exception is requested

1. **Published ports, and `requires: [public-ip]`.**
   - `7882/udp` on LiveKit: WebRTC media (audio, video, screen sharing) for every
     participant, multiplexed on one UDP port (`rtc.udp_port`).
   - `3479/udp` and `3479/tcp` on coturn: TURN (and STUN) for participants whose network
     blocks UDP 7882.
   Neither is HTTP. Every HTTP path (client, API, GraphQL, LiveKit signalling, notes,
   Greenlight) goes through the platform's proxy to `bigbluebutton-router`.
2. **amd64 only.** The bbb-docker images (`alangecker/bbb-docker-*`, LiveKit build
   included) and `bigbluebutton/greenlight` are published for amd64 only.
3. **A fixed subnet for the app network** (`10.213.78.0/24`, LiveKit at `10.213.78.20`,
   Docker assigns the others from `10.213.78.128/25`).
4. **A deliberately public part.** Greenlight's landing page and each room's join page
   open without a login, and so does the BigBlueButton client once a join link has been
   issued.
5. **Root containers** writing only to the app folder: bbb-web (its entrypoint creates
   and re-owns `/var/bigbluebutton`, then drops to uid 998 with gosu), Greenlight (the
   image has no `USER`), and the stock nginx, postgres and redis entrypoints.
6. **TURN on 3479 instead of the standard 3478, and no TURN over 443.**

## Why it is necessary

1. Media cannot go through an HTTP reverse proxy: browsers send RTP over UDP to the
   address LiveKit announces (the box's public IPv4, `APP_PUBLIC_IPV4`). Behind NAT or
   the mesh tunnel the app installs but calls have no audio or video, hence
   `requires: [public-ip]` and the `needs-public-ip` tag.
2. No arm64 builds exist upstream.
3. bbb-docker runs LiveKit and coturn with host networking and hard-codes 10.7.7.x
   addresses. Host networking is not acceptable here, so LiveKit and coturn run on the
   bridge network exactly as BigBlueButton's own 4.1 compose setup does: coturn relays
   only to LiveKit's address (`allowed-peer-ip`, everything else denied), which needs a
   fixed address, which needs a fixed subnet. Putting LiveKit on a second, smaller
   network was rejected: with two networks its UDP replies can leave through the other
   interface and break the published port's NAT. The subnet sits outside Docker's
   default pools (172.17–31.x, 192.168.x); no other store app fixes a subnet.
   Every other hard-coded address is gone: service names are network aliases on the app
   network, and the files that named 10.7.7.x or `host.docker.internal` are replaced by
   `configs:` (akka-apps, nginx's LiveKit and SFU locations, LiveKit, coturn, bbb-web's
   TURN list); webrtc-sfu takes its addresses from environment variables.
4. Conferencing is for people without an account: a guest opens the room link, types a
   name, and joins. Putting a login gate in front would make that impossible.
5. These are the upstream images' own entrypoints; none touches a user folder.
6. The platform's proxy owns 443 and does not carry TURN. 3478 is the standard TURN port,
   but Nextcloud Talk already publishes it, and two apps cannot publish the same host
   port: on 3479 BigBlueButton and Nextcloud run side by side. The cost is that a
   network allowing exactly 3478 and nothing else gets no TURN; browsers learn the port
   from bbb-web's TURN list, so nothing on the client side is configured by hand.

## Mitigations

- **Login.** Greenlight's own login is mandatory for everything except joining a room.
  The first administrator is created with Greenlight's CLI (`rake admin:create`) from a
  generated secret, shown in Maison's Credentials. Greenlight 3 has no environment
  variable or config key for the registration method (its default is *open*), so the
  started step switches it to **invitation-only** through Greenlight's admin API, signed
  in as that administrator: the request its Admin panel sends. Nothing is written into
  its database directly. Rooms can additionally require moderator approval or an access
  code.
- **Client and API.** The BigBlueButton API only answers calls signed with
  `BBB_SHARED_SECRET` (Greenlight holds it); the client needs a session token from a join
  link; the media and notes endpoints check that token with bbb-web (`auth_request`).
  Hasura, Postgres, Redis and every BigBlueButton service are on the app network only.
- **TURN.** coturn uses a generated shared secret (short-lived credentials issued by
  bbb-web), refuses TCP relays and relays to LiveKit's address only, so it cannot be used
  to reach anything else on the box or the internet.
- **Ports.** Nothing else listens on 7882/udp (LiveKit's TCP fallback is off) or 3479.
- **Resources.** Every service has a memory limit and a CPU weight;
  `resources.recommended` is 4 CPU / 8G, BigBlueButton's own minimum.

## Alternatives considered

- **AppShield in front of Greenlight**: guests could no longer join by link.
- **Host networking for LiveKit and coturn** (bbb-docker's way): refused by the store's
  permissions rule and unnecessary since LiveKit's single-port mode.
- **A port range for media**: one UDP port is LiveKit's supported mode and keeps the
  published surface to one port.
- **TURN on 443**: needs its own TLS listener on 443, which the platform proxy holds.
- **Setting the registration method in the database (rails runner)**: rejected, the
  store accepts only documented means; the admin API is what the app's own UI uses.

## Data protection

- All state is under `/DATA/AppData/bigbluebutton/`: `postgres/` (Greenlight users,
  rooms and settings; shared notes), `greenlight/storage/` (avatars, branding,
  pre-uploaded presentations), `bigbluebutton/` (slides converted for live meetings),
  `redis/`, and `presentation/default.pdf` (the default slide, seeded).
- `bigbluebutton/` and `redis/` are excluded from backups: they hold only live-meeting
  data, recreated on start. Without recordings, nothing of a finished meeting is kept.
- No user folder is mounted.

## Known limits (only a test on a public-IP server can confirm)

- Audio/video over UDP 7882 and the TURN fallback (needs the ports open in the provider's
  firewall).
- Greenlight and bbb-web reach the app's public address for the API and the default
  slide (hairpin through the platform proxy), as bbb-docker does.
- The shared-notes image creates its own database role with a fixed password inside the
  image (`blocknote_app`); Postgres is reachable only on the app network.
- webrtc-sfu is tagged `v2.25.0-beta.3`: that is the version bbb-docker v4.0.3 ships.
