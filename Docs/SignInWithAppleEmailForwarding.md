# Sign in with Apple — Email Forwarding Checklist

App Review flagged that Sign in with Apple fails when the user chooses **Hide My Email**. Apple’s private relay only forwards messages from domains that you explicitly register in the developer portal, so password-reset and verification emails sent by Firebase are getting rejected.

Follow the steps below to bring email forwarding into compliance.

---

## 1. Identify the sending addresses

Firebase Auth sends messages from one of these domains (check the templates in the Firebase console):

- `noreply@ledgex.app` (if you set a custom domain)
- `noreply@ledgex.firebaseapp.com`
- `noreply@ledgex.web.app`

You must register **every** domain that ever appears in the `From:` header. If you keep Firebase’s default, register both `ledgex.firebaseapp.com` and `ledgex.web.app`. If you configured a custom email, register its parent domain (for example, `ledgex.app`).

---

## 2. Add the domains in App Store Connect

1. Go to [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) using the Apple ID that manages Ledgex.
2. In the sidebar, choose **More** ▸ **Sign in with Apple**.
3. Click your **App ID** for Ledgex, then click **Configure**.
4. Under **Email Communication**, click **Add Domain**.
5. Enter the domain (e.g., `ledgex.app`) and add an email address that will appear in the `From:` field (e.g., `support@ledgex.app`).
6. Download the generated DNS records (TXT + MX) and leave this window open.

---

## 3. Publish Apple’s DNS records

In your DNS provider (Cloudflare, Route53, etc.), add the records Apple provided:

- **TXT** record at the root of the domain (used for verification).
- **MX** record that points to `relay-smtp.apple.com` with priority `10`.

Propagation can take a few minutes. Use `dig`/`nslookup` or an online checker to confirm the records are live.

Once the records resolve, return to Apple’s configuration screen and click **Verify** next to each domain. Apple should mark the domain as `Verified`.

---

## 4. Repeat for every Firebase domain

If Firebase still uses the default `firebaseapp.com` sender:

1. Repeat steps 2–3 for `ledgex.firebaseapp.com`.
2. Apple will provide unique TXT/MX records for that subdomain—add them exactly as shown.

You only need to do this once; the relay covers all Sign in with Apple users afterwards.

---

## 5. Update Firebase (optional)

- If you want all outgoing mail to appear from `support@ledgex.app`, configure that address under **Firebase Console → Authentication → Templates → Email Template**.
- Make sure the chosen address matches the one you whitelisted with Apple.

---

## 6. Re-test

1. Install the latest build.
2. Sign out of iCloud or use a fresh sandbox tester.
3. Sign in with Apple, choose **Hide My Email**, and trigger an email (password reset or invite).
4. Confirm that the message arrives via Apple’s relay.

Attach these results in the App Review reply so the reviewer knows the forwarding issue is resolved.
