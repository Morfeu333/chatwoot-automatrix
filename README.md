# chatwoot-automatrix

Production Chatwoot deployment for **automatrix.site** — self-hosted on a Xeon server, exposed via Cloudflare Tunnel, with WhatsApp Cloud API, Instagram Business Login, and a custom patch to route Instagram comments to n8n.

> **Image size note:** The Chatwoot Docker image is ~1.72 GB. This repo contains only config files and overrides — no image data. Run `docker compose pull` to fetch the image on the server.

---

## Architecture

```
Internet
   │
   ▼
Cloudflare (TLS termination)
   │  chatwoot.automatrix.site → tunnel CNAME
   ▼
cloudflared (Cloudflare Tunnel daemon)
   │  ingress: localhost:3200
   ▼
Docker: chatwoot-rails  (port 3200 → container 3000)
Docker: chatwoot-sidekiq
Docker: chatwoot-postgres  (pgvector/pg16)
Docker: chatwoot-redis
```

**Server:** `automatrix-X99` (Tailscale `100.88.89.9`), Ubuntu, 64 GB RAM  
**Chatwoot image:** `chatwoot/chatwoot:latest` (the deployed digest/version has not been re-verified)

Before changing the image tag, record the version and digest currently running on the server and take a database backup. Do not assume the current deployment is v4.12.1 based on the original setup note.

---

## Repository Structure

```
.
├── docker-compose.yml
├── .env.example                              # copy to .env and fill values
└── overrides/
    ├── app/
    │   ├── jobs/webhooks/
    │   │   └── instagram_events_job.rb       # routes comments to n8n
    │   └── controllers/concerns/
    │       └── instagram_concern.rb          # fixes Instagram OAuth URL
```

Both override files are bind-mounted into the container (see `docker-compose.yml`), so they survive image updates. When Chatwoot releases a new version, diff these files against the upstream before upgrading.

---

## Meta Apps

Two separate Meta Developer apps are used — one per product line:

| App | App ID | Used for |
|-----|--------|----------|
| **wepwep** | `1920100368710512` | WhatsApp Cloud API |
| **autocem** | `1170128801145266` | Facebook Pages + Instagram Business Login |

### App selection and readiness

These are the apps documented for the existing installation, not a verified recommendation for a customer onboarding product. The October 12, 2026 read-only Meta audit found that none of the 33 apps whose App Review status could be checked had Advanced Access for both `whatsapp_business_management` and `whatsapp_business_messaging`. The two restricted apps could not be confirmed. Do not offer third-party customer onboarding through these apps until the selected app has the required access and the Tech Provider setup is complete.

The historical separation between WhatsApp and Instagram apps is a deployment choice, not a Meta requirement. Reassess it against the selected business, app permissions, and review status before changing app IDs or secrets.

---

## Step 1 — Cloudflare Tunnel

On the server, add the ingress rule to `/etc/cloudflared/config.yml`:

```yaml
ingresses:
  - hostname: chatwoot.automatrix.site
    service: http://localhost:3200
  # ... other services ...
  - service: http_status:404
```

Create the DNS record:

```bash
cloudflared tunnel route dns <TUNNEL_ID> chatwoot.automatrix.site
systemctl restart cloudflared
```

Cloudflare handles TLS. The tunnel sends plain HTTP to `localhost:3200`, so set `FORCE_SSL=false` in `.env`.

---

## Step 2 — Deploy Chatwoot

```bash
git clone https://github.com/morfeu333/chatwoot-automatrix.git /home/automatrix/chatwoot
cd /home/automatrix/chatwoot

cp .env.example .env
# Edit .env with your values (see configuration section below)

docker compose pull
docker compose up -d
docker exec chatwoot-rails bundle exec rails db:chatwoot_prepare
```

Wait ~60 seconds for Rails to boot, then open `https://chatwoot.automatrix.site`.

### Create superadmin

```bash
docker exec -it chatwoot-rails bundle exec rails c
```

```ruby
SuperAdmin.create!(
  name: "Your Name",
  email: "you@example.com",
  password: "strong-password-here"
)
```

Log in at `https://chatwoot.automatrix.site/super_admin`.

---

## Step 3 — Environment Configuration

Copy `.env.example` to `.env` and set:

| Variable | Value | Notes |
|----------|-------|-------|
| `SECRET_KEY_BASE` | `rails secret` output | Generate with `docker run --rm chatwoot/chatwoot:latest bundle exec rails secret` |
| `FRONTEND_URL` | `https://chatwoot.automatrix.site` | Must match Cloudflare subdomain |
| `FORCE_SSL` | `false` | Cloudflare handles TLS |
| `POSTGRES_PASSWORD` | strong password | |
| `REDIS_PASSWORD` | strong password | |
| `SMTP_USERNAME` | Gmail address | Requires Gmail App Password (2FA must be enabled) |
| `SMTP_PASSWORD` | Gmail App Password | Generate at myaccount.google.com/apppasswords |
| `MAILER_SENDER_EMAIL` | Same Gmail address | |
| `FACEBOOK_APP_ID` | `1170128801145266` | autocem app |
| `FACEBOOK_APP_SECRET` | from Meta Developers | autocem app secret |
| `FACEBOOK_VERIFY_TOKEN` | any random string | must match Meta webhook config |
| `INSTAGRAM_COMMENTS_N8N_WEBHOOK_URL` | `https://n8n.automatrix.site/webhook/instagram-comments` | comment patch destination |

---

## Step 4 — WhatsApp Cloud API Inbox

### Meta Developers setup (app: wepwep)

1. Go to `developers.facebook.com` → **wepwep** app → **WhatsApp** → **Configuration**
2. Set webhook URL: `https://chatwoot.automatrix.site/webhooks/whatsapp/%2B15556315763`
   - Replace `%2B15556315763` with your URL-encoded phone number (leading `+` → `%2B`)
   - The verify token must match `FACEBOOK_VERIFY_TOKEN` in `.env`
3. For this existing, manually configured inbox, subscribe to `messages`. A customer onboarding flow also needs the app's `account_update` webhook subscription.
4. Create a token with the required WhatsApp permissions and store it only in Chatwoot's protected configuration. Tokens can be revoked and permissions can change; do not rely on a token being permanent.

> **Critical:** Chatwoot matches the webhook by **phone number**, not by phone number ID. The URL path must be the actual number (e.g., `+15556315763` → `%2B15556315763`), not the numeric Phone Number ID from Meta.

### Chatwoot inbox setup

1. Settings → Inboxes → New Inbox → WhatsApp (Cloud)
2. Fill:
   - Phone Number: `+15556315763` (the one registered in Meta)
   - Phone Number ID: from Meta WhatsApp dashboard
   - Business Account ID: from Meta Business Manager
   - API Key: the System User token

### Token replacement

When a token expires (you'll see "Failed to send" errors):

```bash
docker exec -it chatwoot-rails bundle exec rails c
```

```ruby
channel = Channel::Whatsapp.find_by(phone_number: '+15556315763')
channel.update!(provider_config: channel.provider_config.merge('api_key' => 'NEW_TOKEN_HERE'))
```

Do not paste tokens into this repository, issue comments, or logs. Prefer rotating the credential through Meta and Chatwoot's supported settings, then verify the channel without sending a customer message.

### Customer onboarding with Embedded Signup

The steps above create a manually configured inbox for a number already under your control. They do not provide self-serve onboarding for other businesses. Chatwoot v4.12.1 includes a native Embedded Signup flow; the code path must be checked against the exact deployed version before enabling it.

For a controlled implementation, configure the WhatsApp app in Meta for Facebook Login for Business and Embedded Signup v4, then set these Chatwoot global configuration values in Super Admin → Settings → App Config (or as protected environment configuration):

| Chatwoot setting | Value |
|---|---|
| `WHATSAPP_APP_ID` | The selected Meta app ID |
| `WHATSAPP_APP_SECRET` | The selected Meta app secret; treat as a secret |
| `WHATSAPP_CONFIGURATION_ID` | The Embedded Signup configuration ID |
| `WHATSAPP_API_VERSION` | A Graph API version supported by the selected Chatwoot release |

Use placeholders in documentation and keep real values out of Git. The public HTTPS application URL, OAuth configuration, Meta app review, required Advanced Access, business verification, and webhook subscriptions must all be ready before customer onboarding. Subscribe to both `messages` and `account_update` as required by the chosen Meta flow.

Embedded Signup leaves business assets owned by the customer and exchanges the authorization code server-side. Treat business, WABA, phone-number, and inbox IDs as strings throughout integrations; never coerce them to JavaScript numbers. Reconcile the WABA and number returned by the flow before creating an inbox. Provide distinct paths for a new number, an already registered number, migration, and WhatsApp Business App Coexistence. For Coexistence, follow Meta's flow and do not register a number that is already registered.

The Meta audit on October 12, 2026 found no confirmed Advanced Access for both required WhatsApp permissions among the reviewable apps. It also found that the currently configured `wepwep` webhook exposes only `messages`; the audit did not test event delivery. These are blockers to third-party onboarding, not evidence that the existing manually configured inbox is broken.

---

## Step 5 — Facebook & Instagram Inboxes

### Meta Developers setup (app: autocem)

**Facebook product:**
- Add **Facebook Login** product
- Valid OAuth redirect URIs: `https://chatwoot.automatrix.site/`
- Webhook: `https://chatwoot.automatrix.site/webhooks/facebook`
- Verify token: same as `FACEBOOK_VERIFY_TOKEN`
- Subscribe to: `messages`, `message_deliveries`, `message_reads`, `messaging_postbacks`

**Instagram product:**
- Add **Instagram** product (Instagram Business Login, not Instagram Basic Display)
- Valid OAuth redirect URIs: `https://chatwoot.automatrix.site/auth/sign_in`
- Webhook: `https://chatwoot.automatrix.site/webhooks/instagram`
  - Subscribe to: `messages`, `comments`, `live_comments`
- **App ID for Instagram OAuth:** use the **Instagram Client ID** (found under Instagram → Settings → Client OAuth settings), NOT the Facebook App ID. These are different numbers.

### ⚠️ Critical: Two different App IDs in the same Meta app

The `autocem` app has two distinct IDs:

| Field | Value | Used for |
|-------|-------|---------|
| Facebook App ID | `1170128801145266` | `FACEBOOK_APP_ID` env var, FB OAuth |
| Instagram Client ID | `1331322001413996` | Chatwoot Super Admin → Instagram App ID |

Chatwoot uses the Facebook App ID for Facebook pages but needs the Instagram Client ID for Instagram Business Login. Mixing them up causes `Invalid platform app` errors.

### Chatwoot Super Admin settings

Go to `https://chatwoot.automatrix.site/super_admin` → Settings → and set:

| Key | Value |
|-----|-------|
| `INSTAGRAM_APP_ID` | `1331322001413996` (Instagram Client ID) |
| `INSTAGRAM_APP_SECRET` | Instagram client secret (from Instagram → Settings) |
| `INSTAGRAM_VERIFY_TOKEN` | same as `FACEBOOK_VERIFY_TOKEN` |
| `FB_VERIFY_TOKEN` | same as `FACEBOOK_VERIFY_TOKEN` |

Or via Rails console:

```ruby
[
  ['INSTAGRAM_APP_ID',     '1331322001413996'],
  ['INSTAGRAM_APP_SECRET', 'your_instagram_client_secret'],
  ['INSTAGRAM_VERIFY_TOKEN', 'your_verify_token'],
  ['FB_VERIFY_TOKEN',      'your_verify_token'],
].each do |key, value|
  config = InstallationConfig.find_or_initialize_by(name: key)
  config.update!(value: value)
end
```

### Create the Instagram inbox

1. Settings → Inboxes → New Inbox → Instagram
2. Click "Sign in with Instagram" — this triggers the Instagram Business Login OAuth
3. Select the Instagram Business Account connected to your Facebook Page
4. The inbox is created with a 60-day token; Chatwoot auto-refreshes it

---

## Patch 1: Instagram OAuth Authorize URL

**File:** `overrides/app/controllers/concerns/instagram_concern.rb`

**Problem:** Chatwoot v4.x uses `https://api.instagram.com/oauth/authorize` (deprecated). Since Meta's Graph API v16 migration, Instagram Business Login requires `https://www.instagram.com/oauth/authorize`. Using the old URL returns:

```
Invalid Request: Invalid platform app
```

**Fix:** The override changes one line:

```diff
- authorize_url: 'https://api.instagram.com/oauth/authorize',
+ authorize_url: 'https://www.instagram.com/oauth/authorize',
```

This is mounted via Docker volume in `docker-compose.yml` so it survives container restarts and image updates.

---

## Patch 2: Instagram Comments → n8n

**File:** `overrides/app/jobs/webhooks/instagram_events_job.rb`

**Problem:** Chatwoot only handles `[:message, :read]` events. Instagram comment webhooks arrive as `entry[:changes]` with `field: "comments"` or `field: "live_comments"`. The original code routes all `entry[:changes]` payloads to `Instagram::TestEventService`, which silently discards them.

**Fix:** The override intercepts comment events before they reach `TestEventService` and forwards them to n8n via `WebhookJob`:

```ruby
def process_test_event(entry)
  changes = entry[:changes] || []
  changes.each do |change|
    field = change[:field].to_s
    value = change[:value]

    if field == 'comments' || field == 'live_comments'
      forward_comment_to_n8n(entry[:id], field, value)
    else
      # Real Meta test events for DMs have field "messages" — handle normally
      Instagram::TestEventService.new(value).perform if value.present?
    end
  end
end

def forward_comment_to_n8n(ig_account_id, field, value)
  n8n_url = ENV.fetch('INSTAGRAM_COMMENTS_N8N_WEBHOOK_URL', nil)
  return if n8n_url.blank?

  payload = {
    ig_account_id: ig_account_id,
    field: field,
    value: value,
    received_at: Time.now.utc.iso8601
  }

  WebhookJob.perform_later(n8n_url, payload)
rescue StandardError => e
  Rails.logger.error("Failed to forward Instagram comment to n8n: #{e.message}")
end
```

### n8n webhook payload structure

```json
{
  "ig_account_id": "17841400000000000",
  "field": "comments",
  "value": {
    "id": "18111011614888863",
    "text": "Great post!",
    "from": {
      "id": "1234567890",
      "username": "user_handle"
    },
    "media": {
      "id": "18074687404866376",
      "media_product_type": "FEED"
    }
  },
  "received_at": "2026-05-01T13:00:00Z"
}
```

**Media IDs explained:**
- `value.media.id` → the carousel or post ID (what you pass to reply to the comment's post)
- `value.id` → the individual comment ID (what you pass to reply directly to the comment)

### Replying to comments via n8n

To reply to a comment via Meta Graph API from n8n:

```
POST https://graph.instagram.com/v21.0/{{value.id}}/replies
Body: { "message": "Your reply text", "access_token": "YOUR_LONG_LIVED_TOKEN" }
```

To send a DM triggered by a comment:

```
POST https://graph.instagram.com/v21.0/me/messages
Body: {
  "recipient": { "id": "{{value.from.id}}" },
  "message": { "text": "Your DM text" },
  "access_token": "YOUR_LONG_LIVED_TOKEN"
}
```

Required Meta app permission: `instagram_business_manage_comments`

---

## Maintenance

### Upgrading Chatwoot

```bash
cd /home/automatrix/chatwoot
docker compose pull
docker compose up -d --force-recreate rails sidekiq
```

Before upgrading, diff the override files against the new image:

```bash
docker run --rm chatwoot/chatwoot:latest cat /app/app/jobs/webhooks/instagram_events_job.rb > /tmp/upstream_events_job.rb
diff /tmp/upstream_events_job.rb overrides/app/jobs/webhooks/instagram_events_job.rb

docker run --rm chatwoot/chatwoot:latest cat /app/app/controllers/concerns/instagram_concern.rb > /tmp/upstream_concern.rb
diff /tmp/upstream_concern.rb overrides/app/controllers/concerns/instagram_concern.rb
```

If the upstream changed significantly, re-apply the patches manually.

### Checking logs

```bash
# Rails logs
docker logs chatwoot-rails -f --tail 100

# Sidekiq (background jobs including WebhookJob)
docker logs chatwoot-sidekiq -f --tail 100

# Filter for Instagram comment forwarding
docker logs chatwoot-sidekiq 2>&1 | grep -i "instagram comment\|n8n"
```

### n8n password reset

If the n8n password is lost:

```bash
# Generate bcrypt hash
docker exec -it n8n-main node -e "
const bcrypt = require('bcryptjs');
const hash = bcrypt.hashSync('new-password', 10);
console.log(hash);
"

# Write SQL to file (avoids shell variable interpolation of $2a$...)
echo "UPDATE public.user SET password = 'HASH_HERE' WHERE email = 'you@example.com';" > /tmp/reset.sql

docker cp /tmp/reset.sql n8n-postgres:/tmp/reset.sql
docker exec n8n-postgres psql -U n8n -d n8n -f /tmp/reset.sql
```

---

## Known Limitations

- **Instagram token expiry:** Tokens last 60 days. Chatwoot attempts auto-refresh but it may fail if the Meta app permissions change. Re-authenticate via the inbox settings if DMs stop working.
- **WhatsApp System User token:** Never expires if generated correctly. If regenerated, update via Rails console (see Step 4).
- **Comments permission:** `instagram_business_manage_comments` must be approved in the Meta app review for comment replies to work in production. In development mode, only testers can trigger it.
- **Chatwoot drops comment events natively:** Even with the patch, Chatwoot itself doesn't create conversations or messages from comments — only n8n handles them. If `INSTAGRAM_COMMENTS_N8N_WEBHOOK_URL` is blank, comments are silently ignored.
