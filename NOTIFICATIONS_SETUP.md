# Push Notifications Setup Guide

## Overview
Your Ledgex app now has complete push notification infrastructure. This guide will help you deploy the necessary Cloud Functions and test notifications on real devices.

## What's Already Configured

### iOS App (✅ Complete)
- ✅ FCM (Firebase Cloud Messaging) integration in `NotificationService.swift`
- ✅ APNs token registration and storage
- ✅ Permission request flow in `ContentView` and `ProfileView`
- ✅ Background notification support in `AppInfo.plist`
- ✅ Development APNs entitlements in `Ledgex.entitlements`

### Backend Cloud Functions (✅ Ready to Deploy)
The following Cloud Functions are implemented in `functions/src/index.ts`:

1. **`onTripUpdated`** (Firestore Trigger) - Main notification dispatcher
   - Detects new expenses and sends notifications to participants
   - Detects new members joining and notifies existing members
   - Detects trip phase changes (setup → active)
   - Detects when all members are ready to settle

2. **Notification Types Supported:**
   - ✅ New expense added (you requested this!)
   - ✅ New member joined (you requested this!)
   - ✅ Trip started
   - ✅ Ready to settle

## Deployment Steps

### 1. Deploy Cloud Functions

The critical step is deploying the `onTripUpdated` Cloud Function that triggers notifications:

```bash
cd functions
npm run deploy
```

This will:
- Build the TypeScript functions
- Deploy ALL functions including the notification trigger
- Configure the Firestore trigger on `trips/{tripId}`

**Verify Deployment:**
After deployment completes, verify in Firebase Console:
1. Go to Firebase Console → Functions
2. Confirm these functions are deployed:
   - `createTripInvite`
   - `joinTrip`
   - `forceDeleteAccount`
   - `onTripUpdated` ← **This is critical for notifications!**

### 2. Configure APNs in Firebase Console

For notifications to work on real iOS devices, you need to upload your APNs certificate or key to Firebase:

#### Option A: APNs Authentication Key (Recommended)
1. Go to [Apple Developer Portal](https://developer.apple.com/account/resources/authkeys/list)
2. Create a new APNs Authentication Key
3. Download the .p8 file
4. Go to Firebase Console → Project Settings → Cloud Messaging → Apple app configuration
5. Upload the .p8 key with your Key ID and Team ID

#### Option B: APNs Certificate
1. Generate an APNs certificate in Xcode or Apple Developer Portal
2. Export as .p12 file
3. Upload to Firebase Console → Project Settings → Cloud Messaging

### 3. Update Xcode Project for Production (Optional)

For App Store or TestFlight builds, you may need to:

1. **Create a production entitlements file** (if not using automatic provisioning):
   - Duplicate `Ledgex.entitlements` → `Ledgex.production.entitlements`
   - Change `aps-environment` from `development` to `production`
   - Update Xcode build settings to use the correct entitlements for Release builds

2. **Verify Signing & Capabilities:**
   - Open Xcode project
   - Select target "Ledgex"
   - Go to "Signing & Capabilities"
   - Ensure "Push Notifications" capability is enabled
   - Ensure "Background Modes" includes "Remote notifications"

## Testing Notifications

### Test on Real Devices (Simulator won't work for push notifications!)

1. **Build and install on a physical iPhone:**
   ```bash
   # From Xcode: Product → Destination → Your iPhone
   # Then: Product → Run (Cmd+R)
   ```

2. **Grant notification permissions:**
   - Sign in to the app
   - When prompted, tap "Allow" for notifications
   - Or go to Profile tab → Enable notifications manually

3. **Test new member notification:**
   - Device A: Create a new trip and get the invite code
   - Device B: Join the trip using the code
   - Device A should receive: "New member joined [Trip Name]"

4. **Test new expense notification:**
   - Device A: Add an expense to the trip
   - Device B should receive: "New expense in [Trip Name] - [Description] – $[Amount]"

### Debugging Tips

**If notifications don't arrive:**

1. **Check FCM tokens are being stored:**
   - Open Firebase Console → Firestore
   - Navigate to `users` collection
   - Find your user document (by firebaseUID)
   - Verify the `tokens` array contains FCM tokens

2. **Check Cloud Function logs:**
   - Firebase Console → Functions → Logs
   - Look for `onTripUpdated` executions
   - Check for errors like "Failed to send message"

3. **Check device notification settings:**
   - iOS Settings → Ledgex → Notifications → Ensure enabled

4. **Verify APNs configuration:**
   - Firebase Console → Project Settings → Cloud Messaging
   - Ensure APNs certificate/key is uploaded and valid

5. **Check entitlements:**
   ```bash
   # Extract entitlements from installed app
   codesign -d --entitlements :- /path/to/Ledgex.app
   # Should show aps-environment = development or production
   ```

## Implementation Details

### How It Works

1. **User signs in** → FCM token is generated and stored in Firestore `users/{uid}/tokens`
2. **Trip is updated** (expense added, member joined) → Firestore trigger fires
3. **Cloud Function `onTripUpdated`** detects the change and:
   - Identifies affected users
   - Fetches their FCM tokens from Firestore
   - Sends multicast notification via Firebase Admin SDK
4. **iOS device receives notification** → Displayed to user

### Notification Payload

Each notification includes:
- **title**: e.g., "New expense in Weekend Trip"
- **body**: e.g., "Dinner – $45.50"
- **data**: Custom payload with:
  - `type`: "newExpense" | "newMember" | "tripStarted" | "readyToSettle"
  - `tripId`: Firestore trip document ID
  - `tripCode`: 10-character trip code
  - `expenseId` or `memberId`: Related document ID

### Customizing Notifications

To add more notification types, edit:
1. `functions/src/index.ts` → Add new handlers in `onTripUpdated`
2. `Ledgex/Services/NotificationService.swift` → Add new `NotificationType` cases
3. Redeploy Cloud Functions: `cd functions && npm run deploy`

## Production Checklist

Before releasing to App Store:

- [ ] Deploy all Cloud Functions to production Firebase project
- [ ] Upload production APNs certificate/key to Firebase Console
- [ ] Test notifications on physical devices (not simulator)
- [ ] Verify entitlements for production (`aps-environment: production`)
- [ ] Test across multiple devices to verify delivery
- [ ] Test foreground, background, and killed app scenarios
- [ ] Verify notification settings in iOS Settings app

## Troubleshooting Common Issues

### "Failed to send message" in Cloud Function logs
- **Cause**: Invalid FCM token or APNs not configured
- **Fix**: Check APNs certificate in Firebase Console

### Notifications work in development but not in TestFlight
- **Cause**: Using development APNs certificate for production build
- **Fix**: Upload production APNs certificate and rebuild

### Token not being stored in Firestore
- **Cause**: User not signed in or permissions not granted
- **Fix**: Ensure user is authenticated and grants notification permissions

### "messaging/registration-token-not-registered"
- **Cause**: Stale FCM token (user uninstalled/reinstalled app)
- **Fix**: Cloud Function automatically removes invalid tokens

## Next Steps

1. Deploy the Cloud Functions: `cd functions && npm run deploy`
2. Configure APNs in Firebase Console
3. Test on two physical devices
4. Verify all notification types work as expected

For questions or issues, check Firebase Cloud Messaging logs and Xcode console output.
