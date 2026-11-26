# Greenlight's first administrator, then invitation-only sign-up.
#
# Runs as a `started` step (bash -euo pipefail, in the app folder, after
# `docker compose up`). Guarded on the data: the marker lives in the app folder, so it
# travels with backups and a reinstall over kept data does nothing.
#
# 1. The account is created with Greenlight's documented CLI: rake admin:create.
# 2. Sign-up is switched from Greenlight's default (open) to invitation-only through
#    Greenlight's own admin API, signed in as that administrator: the same request
#    its Admin panel sends. Greenlight 3 has no environment variable or config key for
#    the registration method, and nothing is written to its database directly.

marker="$APP_DIR/greenlight/.admin-initialized"
[ -e "$marker" ] && exit 0

GL_ADMIN_EMAIL="${APP_EMAIL:-admin@$APP_DOMAIN}"
# Greenlight requires a lower-case letter, a capital, a digit and a symbol; the suffix
# guarantees them (same value as the `credentials` entry).
GL_ADMIN_PASSWORD="$GREENLIGHT_ADMIN_PASSWORD-Aa1"
GL_HOST="${APP_HOST:-bigbluebutton-$APP_DOMAIN}"
export GL_ADMIN_EMAIL GL_ADMIN_PASSWORD GL_HOST

# Greenlight precompiles its assets and migrates its database on every start: retry
# until its roles exist. An existing account ("has already been taken") is fine.
result=""
out=""
for _ in $(seq 1 40); do
  if out=$(compose exec -e GL_ADMIN_EMAIL -e GL_ADMIN_PASSWORD bigbluebutton-greenlight \
      sh -c 'bundle exec rake "admin:create[Administrator,$GL_ADMIN_EMAIL,$GL_ADMIN_PASSWORD]"' 2>&1); then
    result=created
    break
  fi
  case "$out" in
    *"already been taken"*) result=existing; break ;;
  esac
  sleep 15
done
if [ -z "$result" ]; then
  echo "Greenlight is not ready yet; retrying on the next start." >&2
  printf '%s\n' "$out" | tail -n 3 >&2
  exit 1
fi
echo "Greenlight administrator: $result ($GL_ADMIN_EMAIL)."

# Sign in as the administrator and set RegistrationMethod=invite, over HTTP to
# Greenlight inside its own container (Host = the app's address for Rails' host check,
# X-Forwarded-Proto = https for its force_ssl). Exit 2 = the login was refused.
# The rake task above runs before Puma listens on :3000, so this half retries too:
# until it succeeds, sign-up would stay open.
lock_signup() {
compose exec -T -e GL_ADMIN_EMAIL -e GL_ADMIN_PASSWORD -e GL_HOST bigbluebutton-greenlight \
  ruby - <<'RUBY'
require "net/http"
require "json"

http = Net::HTTP.new("127.0.0.1", 3000)
http.read_timeout = 60
cookies = {}

send_req = lambda do |req, accept|
  req["Host"] = ENV.fetch("GL_HOST")
  req["X-Forwarded-Proto"] = "https"
  req["Accept"] = accept
  req["Cookie"] = cookies.map { |k, v| "#{k}=#{v}" }.join("; ") unless cookies.empty?
  res = http.request(req)
  Array(res.get_fields("set-cookie")).each do |c|
    k, v = c.split(";", 2).first.split("=", 2)
    cookies[k] = v
  end
  res
end

page = send_req.call(Net::HTTP::Get.new("/"), "text/html")
token = page.body.to_s[/name="csrf-token" content="([^"]+)"/, 1]
abort("no CSRF token from Greenlight (HTTP #{page.code})") unless token

api = lambda do |req, body|
  req["Content-Type"] = "application/json"
  req["X-CSRF-Token"] = token
  req.body = body.to_json
  send_req.call(req, "application/json")
end

login = api.call(Net::HTTP::Post.new("/api/v1/sessions.json"),
                 session: { email: ENV.fetch("GL_ADMIN_EMAIL"),
                            password: ENV.fetch("GL_ADMIN_PASSWORD"),
                            extend_session: false })
exit 2 if login.code.start_with?("4")
abort("sign-in failed (HTTP #{login.code})") unless login.is_a?(Net::HTTPSuccess)

set = api.call(Net::HTTP::Patch.new("/api/v1/admin/site_settings/RegistrationMethod.json"),
               site_setting: { value: "invite" })
abort("setting the registration method failed (HTTP #{set.code})") unless set.is_a?(Net::HTTPSuccess)
RUBY
}

status=1
for _ in $(seq 1 40); do
  status=0
  lock_signup || status=$?
  case "$status" in 0|2) break ;; esac
  sleep 15
done

case "$status" in
  0) echo "Greenlight sign-up set to invitation only." ;;
  2) echo "Greenlight refused the generated administrator login (password already changed?); sign-up setting left as it is." ;;
  *) echo "Could not set Greenlight's sign-up method; retrying on the next start." >&2; exit 1 ;;
esac

touch "$marker"
