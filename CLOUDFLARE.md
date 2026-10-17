# BLNK Cloudflare migration

This branch preserves the Vercel handlers and the original project. No existing deployment or data is deleted.

## Build and deploy

- Cloudflare Workers Git repository: `mediabogy-hue/tito-store`; select this migration branch.
- Build command: `node scripts/build-cloudflare.mjs`
- Deploy command: `npx wrangler deploy`
- Configuration: `wrangler.jsonc`. Do not set the repository root as the static asset directory.
- Alternatively run the build then Wrangler locally from an authenticated Cloudflare session.

Only `dist-cloudflare/` is uploaded as static assets. The builder uses a web-file allowlist, excludes Git, dependency/APK/build folders, SQL and customer records, and fails with the exact filename if any asset exceeds 25 MiB. API handlers are bundled as Worker modules, never served as public source.

## Runtime configuration

Copy existing runtime configuration securely into Cloudflare settings; never commit secrets:

- SUPABASE_URL
- SUPABASE_PUBLISHABLE_KEY (or SUPABASE_ANON_KEY for public-config)
- SUPABASE_SERVICE_ROLE_KEY (Telegram intake only)
- ADMIN_KEY and GITHUB_TOKEN (legacy catalog/customer APIs)
- TELEGRAM_BOT_TOKEN, TELEGRAM_WEBHOOK_SECRET
- BLNK_SITE_URL: final HTTPS deployment origin

The existing Supabase database and access policies are retained. Set the new allowed authentication redirect URL in Supabase when required. Set up Telegram webhook against the final origin only after deployment verification. Do not rotate credentials or alter database data as part of migration.

## Validation

Run `node scripts/build-cloudflare.mjs` and `node scripts/test-cloudflare.mjs`.
These checks cover page routing, aliases, adapter responses, missing-credential protection, malformed JSON and private-file exclusion. They do not prove authenticated database flows or an actual Cloudflare deployment.

After deployment verify storefront catalog; admin login and denied access for non-admin; supplier login/upload; customer order placement; admin status update; supplier order visibility; session persistence. Use designated test accounts and products. Verify database writes and rollback test data only with authorization. Preserve the existing Vercel deployment until these tests pass.
