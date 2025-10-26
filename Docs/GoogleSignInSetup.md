# Google Sign-In Configuration Checklist

To finish enabling Google Sign-In in Ledgex, complete the steps below after pulling the latest code.

---

## 1. Install the Google Sign-In SDK

```bash
cd /path/to/Ledgex
bundle exec pod install   # or just `pod install` if you don't use Bundler
```

> The Podfile now declares `GoogleSignIn`; running `pod install` updates `Pods/` and `Podfile.lock`. Commit both.

---

## 2. Register the reversed client ID URL scheme

1. Open `Ledgex/GoogleService-Info.plist` and copy the value of `REVERSED_CLIENT_ID` (looks like `com.googleusercontent.apps.123…`).
2. Replace the placeholder in `Ledgex/AppInfo.plist`:
   ```xml
   <string>com.googleusercontent.apps.REPLACE_WITH_REVERSED_CLIENT_ID</string>
   ```
3. Save. This enables iOS to route the Google callback back into the app.

---

## 3. Enable the OAuth consent screen

1. In the [Google Cloud Console](https://console.cloud.google.com/apis/credentials), locate the iOS OAuth client tied to this bundle ID.
2. Verify the bundle ID is `com.owenwright.Ledgex`.
3. Make sure the OAuth consent screen is in **Production** and lists `https://www.googleapis.com/auth/userinfo.email` and `openid` scopes (the defaults).

---

## 4. Test end-to-end

1. Build and run the app on device or simulator.
2. On the sign-in screen, tap **Sign in with Google**.
3. Confirm the Google web sheet appears and returns to the app.
4. Verify Firebase Auth shows the user with provider `google.com`.
5. Trigger a full sign-out (`Profile → Sign Out`) and sign back in with Google to ensure repeat logins work.

---

## 5. App Store Review notes

When replying in App Store Connect, mention:

- Google Sign-In is available as an alternative to Apple and email/password.
- The app uses Firebase Auth and never handles raw Google passwords.
- Reviewers can use their Google test accounts; the button is on the same screen as Sign in with Apple.

Attach `Docs/GoogleSignInSetup.md` if reviewers want the setup summary.
