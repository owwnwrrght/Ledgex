# Ledgex App Store Review Brief

## 1. Overview
Ledgex is an expense tracking and bill-splitting assistant for shared trips and events. Groups can log purchases, assign costs to participants, and track settlements without moving money. The latest build focuses on the guided “Add Expense” entry flow for quicker manual logging.

## 2. Money Movement Statement
- **Ledgex does *not* move money**. There are no integrations with payment processors, bank accounts, or wallets.
- Users record that someone paid outside the app (cash, bank transfer, Venmo, etc.) and optionally mark settlements as “received” for bookkeeping.
- No card numbers, bank details, or payment authorizations are collected or stored. The app only maintains ledgers for informational purposes, similar to Splitwise.

## 3. Primary User Flows

### 3.1 Authentication
- Launch the app to the sign-in hub.
- Available methods from top to bottom:
  1. **Sign in with Apple** (primary CTA). Handles Hide My Email and multiple scenes.  
  2. **Sign in with Google** using Firebase Auth.  
  3. **Email & Password** via “Prefer email and password?” link.
- All options feed into the same profile record (no duplicate accounts).

### 3.2 Create or Join a Trip
- After signing in, the Trips list displays existing active and archived trips plus a `+` button.
- Tap `+` → “Create Trip” to set the trip name, base currency, and emoji flag.  
- Alternatively, tap **Join by Code** to enter an invite code or scan the QR code sent by an organizer.

### 3.3 Add People (Setup Phase)
- Inside a trip, switch to **People** tab.
- Use `Add Person` to invite contacts, add manual entries, or share the join link/QR code.
- Once everyone is in, tap “Start Trip” to move from setup to active phase (enables expense entry).

### 3.4 Guided Expense Entry (New Flow)
1. Navigate to the **Expenses** tab and tap the `+` button.
2. The guided **Add Expense** form opens directly with current members prefilled and recent-expense templates available.
3. Advanced controls remain behind “Edit Details,” keeping the default path fast while still exposing currency conversion and split tweaks when needed.

### 3.5 Manual Expense Flow Highlights
- Fields: description, amount, payer, split method (equal, percentage, shares, custom amounts).
- Advanced options exposed via “Edit Details” allow currency conversion, split adjustments, and participant toggles.
- On save, the expense appears in the list with receipts (if any) and contributes to balances.

### 3.8 Settlements & Balances
- **Settle Up** tab lists each person’s net balance.
- Tapping an entry reveals suggested payments; marking “Received” updates both sides for record keeping.
- Again: this is a ledger only—no payment is processed.

### 3.9 Account Management & Deletion
- From the trip toolbar, select the gear icon → **Account Management**.
- “Delete My Account” triggers a confirmation flow that erases the user profile, trips, and receipts from Firebase.
- This flow is also accessible via the profile avatar on the Trips list.

## 4. Privacy & Security Highlights
- Expense data and optional receipt photo attachments stay within Firebase (Firestore + Storage); no third-party OCR services process receipts.
- Camera and photo library permissions are requested only when a user chooses to attach a receipt photo for reference.
- Database reads/writes are scoped to the authenticated user’s trips; invites require either a signed-in member or a valid invite code.

## 5. Known Limitations
- Receipt photo uploads require connectivity because images are stored in Firebase Storage.
- Offline mode: manual expenses queue locally; attachments upload automatically once the device is back online.

## 6. Support Contact
If you encounter issues during review, please reach out through App Store Connect or email **support@ledgex.app**. We can provide sandbox accounts, diagnostic builds, or additional documentation on short notice.
