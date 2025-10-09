# Firebase Backend for Group Share Links

This folder contains the Firebase configuration for generating dynamic group invite links and serving a lightweight fallback join page.

## Structure

- `functions/` – TypeScript Cloud Functions:
  - `createTripInvite` (optional short-link generator)
  - `onTripUpdated` (Firestor​e trigger that sends FCM notifications when groups change)
- `hosting/public/join/` – Static landing page used when users open the invite link without the app installed.
- `hosting/public/.well-known/apple-app-site-association` – Enables iOS universal links for `splyt-4801c.web.app/join/*`.
- `firebase.json` – Hosting + Functions configuration.

## Setup

1. Install dependencies:
   ```bash
   cd firebase/functions
   npm install
   ```
2. Log in to Firebase and set the project (staging/prod):
   ```bash
   firebase login
   firebase use <project-id>
   ```
3. Store the Dynamic Links REST API key as a Secret (only once per project):
   ```bash
   firebase functions:secrets:set FDL_API_KEY
   ```
4. Deploy Hosting + Functions:
   ```bash
   npm run build --prefix firebase/functions
   firebase deploy --only functions:createTripInvite hosting
   ```

5. (Optional) Deploy the notification trigger once you are ready to send push alerts:
   ```bash
   firebase deploy --only functions:onTripUpdated
   ```

## Local emulation

```bash
cd firebase
firebase emulators:start --only functions,hosting
```
Send a `POST` request with JSON `{ "groupCode": "ABC123" }` (or the legacy `tripCode`) to
`http://localhost:5001/<project-id>/us-central1/createTripInvite` or use the emulator UI. Firestore writes to `trips/*` inside the emulator will trigger `onTripUpdated` so you can inspect outgoing messages.
