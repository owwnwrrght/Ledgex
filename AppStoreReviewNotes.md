# App Store Review Notes (v1.0 resubmission #3)

## Fixes Applied (October 16, 2025)

### 1. Camera Capture Crash (CRITICAL)
- **Issue**: App crashed when accessing the camera via Expenses → + → Add manually → Add Receipt Photos → Camera.
- **Root Causes**:
  - Missing privacy usage descriptions in the main Info.plist.
  - The legacy `ActionSheet` presentation crashed on iPad because it lacked a popover anchor, and the camera was being presented inside a sheet.
- **Fixes**:
  - Added `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` to `AppInfo.plist`.
  - Replaced the deprecated action sheet with a modern `confirmationDialog` that works on iPhone and iPad.
  - Present the camera picker with a full-screen cover and guard against unavailable hardware, preventing UIKit from throwing an exception.
- **Testing**: Exercised the exact review steps on device—camera permission prompts appear once and capturing/selecting photos now works without crashing.

### 2. Sign in with Apple Error Messaging
- **Issue**: Reviewers saw a generic error banner after tapping “Sign in with Apple.”
- **Improvements**:
  - Refined the Sign in with Apple error handling so normal user cancellations no longer surface as app errors.
  - Added friendly, actionable messaging for real failures (network loss, iCloud not signed in, etc.) while keeping the detailed debug log for support.
  - Ensured the spinner always stops on failure so the sign-in button is immediately usable again.
- **Reviewer Tips**:
  - Please confirm the device is signed into iCloud and has network access.
  - If Sign in with Apple is unavailable, the app now falls back gracefully and suggests email/password as an alternative.

### 3. Money Transfer Functionality
**Does your app allow users to send and/or receive money?**

**Answer: NO**

Ledgex is an expense tracking and splitting calculator, similar to Splitwise. The app:
- ✅ Tracks shared expenses in groups (trips, events, etc.)
- ✅ Calculates who owes whom and by how much
- ✅ Allows users to mark settlements as "received" for record-keeping
- ❌ Does NOT facilitate actual money transfers
- ❌ Does NOT integrate with payment processors (Stripe, PayPal, etc.)
- ❌ Does NOT handle real currency transactions

Users settle debts outside the app (via Venmo, Cash App, bank transfer, cash, etc.) and simply mark the payment as received in Ledgex for tracking purposes.

---

## Previous Fixes

- **Crash Fix**: The invite icon on `TripDetailView` now opens our in-app `Share Group` sheet instead of presenting a native share controller directly, eliminating the crash seen during review. The sheet still lets reviewers share or copy the invite link.
- **Account Deletion Location**: Open any group → tap the gear icon → scroll to **Account Management** → tap **Delete My Account**. This presents a dedicated flow describing the data impact and deletes the account without any re-authentication prompts. The same flow remains accessible from the profile sheet (`Trips` list → avatar button → **Delete Account**).

## Test Suggestions

1. **Sign In**: Use Sign in with Apple (ensure device is signed into iCloud) or use email/password option
2. **Create a Group**: Create a trip/group and add expenses with receipt photos via camera
3. **Camera Test**: Tap Expenses > + > Add manually > Add Receipt Photos > Camera - should work without crash
4. **Account Deletion**: Open any group → gear icon → Account Management → Delete My Account
