# Meta MCP connection handoff

This note is a setup and audit handoff for the official Meta remote MCP servers. It contains no Meta credentials or account-specific configuration.

## Official Meta MCP servers

Meta's [MCP overview](https://developers.facebook.com/documentation/mcp) currently lists these three hosted servers:

| Server | Endpoint | Use |
|---|---|---|
| WhatsApp Business Tools | `https://mcp.facebook.com/whatsapp_business_tools` | Discover authorized businesses, WhatsApp Business Accounts (WABAs), and numbers; onboard/register numbers; manage templates and webhooks; send messages. Beta and rolling out. |
| Meta Social Technologies (formerly Meta Developer Tools) | `https://mcp.facebook.com/devtools` | Inspect developer apps, app review, compliance, API health, webhooks, and Meta developer documentation. |
| Meta Ads | `https://mcp.facebook.com/ads` | Inspect and manage advertising assets and campaigns. Optional for this WhatsApp project. |

The official Meta docs list ChatGPT Web, Codex App, and Codex CLI as supported clients. The WhatsApp server requires an admin role on the business and its WhatsApp-enabled app, and acceptance of the WhatsApp Business Cloud API terms. OAuth consent lets the user select which businesses/apps to share.

## Connect from Codex CLI on the Linux computer

Run these in the user's own Linux terminal, using the normal Codex profile and its usual sandbox/approval settings:

```sh
codex mcp add devtools --url https://mcp.facebook.com/devtools
codex mcp login devtools

codex mcp add whatsapp-business-tools --url https://mcp.facebook.com/whatsapp_business_tools
codex mcp login whatsapp-business-tools

codex mcp list
```

`codex mcp login` opens the Meta OAuth flow. If the Linux computer has no browser available, use the CLI's manual flow:

```sh
codex mcp login devtools --no-browser
codex mcp login whatsapp-business-tools --no-browser
```

The CLI prints the authorization URL and accepts the callback URL after Meta consent. The user can open the authorization URL on their phone, sign in to Meta, choose the intended business/apps, and paste the resulting callback URL into the waiting terminal. Keep the callback inside the terminal flow; do not paste it into GitHub, chat, or this document.

Optional, only if ad-account access is needed:

```sh
codex mcp add meta-ads --url https://mcp.facebook.com/ads
codex mcp login meta-ads
```

The Meta MCP guide for [WhatsApp Business Tools](https://developers.facebook.com/documentation/mcp/whatsapp-business-tools-mcp) also describes adding the endpoint in ChatGPT under Settings → Plugins → Browse plugins → `+`, with OAuth. If that control is absent in the mobile app, use Codex CLI on Linux instead.

## Official Meta skills

Meta's [`facebook/agentic-tools`](https://github.com/facebook/agentic-tools) repository contains the official `devtools` plugin and skills for Codex/Claude Code/Cursor. The skills are:

- `app-health-check`
- `webhook-setup`
- `app-review-prep`
- `debug-webhooks`
- `compliance-check`
- `api-health`
- `api-integration`
- `search-docs`
- `debug-access-token`

The skills complement the `devtools` MCP and are not required to connect it. Meta's official repo does not currently list a separate WhatsApp MCP skill bundle; use the WhatsApp MCP's own docs and tool descriptions.

## First run: read-only audit

After OAuth, ask Codex to do this audit first:

> Use only the connected Meta `devtools` and `whatsapp-business-tools` MCP servers. Do a read-only inventory of the businesses and apps I explicitly authorized; list the WhatsApp Business Accounts and phone numbers, their states, the app's WhatsApp permissions and App Review status, webhook subscriptions, and any compliance or setup blockers. Do not create or register numbers, edit templates or webhooks, send messages, generate tokens, change payments, or change account settings. Report the exact next actions that require my decision.

The WhatsApp tools expose actions such as `whatsapp_biz_businesses`, `whatsapp_biz_accounts`, `whatsapp_biz_phone_numbers`, adding/verifying/registering numbers, template CRUD, webhook configuration/subscription, and message sending. The MCP can perform changes when authorized; keep the first audit read-only and approve later changes individually.

## Number provisioning boundary

The WhatsApp MCP can help add, verify, and register a number against an authorized WABA. That is not the same as allocating a telephone number from a carrier. A customer onboarding product should either have each business bring a number they control and verify it, or add a separate telecom/BSP integration for number purchasing and provisioning.

## SaaS onboarding path to evaluate

For a platform that onboards customer companies, evaluate Meta Embedded Signup and the Tech Provider/App Review process. The Meta sample [`business-messaging-sample-tech-provider-app`](https://github.com/fbsamples/business-messaging-sample-tech-provider-app) demonstrates Embedded Signup, WABA/phone management, messaging, and webhooks. The production path includes business verification, App Review/advanced permissions, privacy disclosures, tenant-isolated token storage, webhook verification, and customer-owned number verification.

Before building an AI-first WhatsApp product, review the current [WhatsApp Business Solution Terms](https://www.whatsapp.com/legal/business-solution-terms), including the AI-provider clause and its country-specific treatment.

## Sources

- [Meta MCP overview](https://developers.facebook.com/documentation/mcp)
- [WhatsApp Business Tools MCP docs](https://developers.facebook.com/documentation/mcp/whatsapp-business-tools-mcp)
- [Meta Social Technologies MCP docs](https://developers.facebook.com/documentation/mcp/devtools-mcp)
- [Meta Ads MCP docs](https://developers.facebook.com/documentation/mcp/ads-mcp-server)
- [Meta agentic-tools and skills](https://github.com/facebook/agentic-tools)
- [Meta Tech Provider sample app](https://github.com/fbsamples/business-messaging-sample-tech-provider-app)
