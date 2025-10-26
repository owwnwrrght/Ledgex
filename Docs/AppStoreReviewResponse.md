# Ledgex App Store Review Brief

## 1. Overview
Ledgex is an expense tracking and bill-splitting assistant for shared trips and events. Groups can log purchases, assign costs to participants, and track settlements without moving money. The latest build introduces a guided “Add Expense” entry flow and an AI-assisted receipt scanner that extracts line items for precise splitting.

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
2. A new **Add Expense** selector appears with two clear options:
   - **Enter manually**: Opens the traditional form pre-filled with current members; supports currency changes, equal/custom splits, and templates from recent expenses.
   - **Scan a receipt**: Launches an improved scanner with “Take Photo” and “Choose from Library” buttons at the top.

### 3.5 Manual Expense Flow Highlights
- Fields: description, amount, payer, split method (equal, percentage, shares, custom amounts).
- Advanced options exposed via “Edit Details” allow currency conversion, split adjustments, and participant toggles.
- On save, the expense appears in the list with receipts (if any) and contributes to balances.

### 3.6 Receipt Scanning (New UX)
1. From the selector, choose **Scan a receipt**.
2. Pick **Take Photo** or **Choose from Library** (buttons are visible without scrolling).
3. The app captures the image and sends it to a Firebase Cloud Function.
4. Backend flow:
   - Validates the user is signed in (prevents abuse).
   - Calls OpenAI Vision (`gpt-4o-mini`) with the image; **no Google Vision is used**.
   - Parses merchant, totals, tax, tips, and each line item into structured JSON.
   - Returns only the structured data; the raw image is not persisted.
5. The **Split Receipt** screen opens, showing detected items. Reviewers can tap each item, assign participants, and adjust quantities or prices before saving.

### 3.7 Itemized Expense Review
- Post-scan, the **Itemized Expense** view summarizes subtotal, tax, tip, per-person amounts, and provides a preview of the original image.
- Users can still edit any line item, remove items, or reassign participants before tapping **Add Expense**.

### 3.8 Settlements & Balances
- **Settle Up** tab lists each person’s net balance.
- Tapping an entry reveals suggested payments; marking “Received” updates both sides for record keeping.
- Again: this is a ledger only—no payment is processed.

### 3.9 Account Management & Deletion
- From the trip toolbar, select the gear icon → **Account Management**.
- “Delete My Account” triggers a confirmation flow that erases the user profile, trips, and receipts from Firebase.
- This flow is also accessible via the profile avatar on the Trips list.

## 4. Privacy & Security Highlights
- Receipt parsing runs entirely on secure Cloud Functions. API keys live in Secret Manager; the client only sends Base64 images via HTTPS.
- Images are processed in-memory and discarded; only structured results are returned.
- Camera and photo library permissions are requested solely for capturing receipts.
- Database reads/writes are scoped to the authenticated user’s trips; invites require either a signed-in member or a valid invite code.

## 5. Known Limitations
- Extremely long receipts (>8 MB encoded) trigger a friendly error asking for a clearer/lighter image.
- The AI parser occasionally mislabels items; users can edit any field before saving.
- Offline mode: manual expenses queue locally, but receipt scanning requires connectivity since the function runs server-side.

## 6. Support Contact
If you encounter issues during review, please reach out through App Store Connect or email **support@ledgex.app**. We can provide sandbox accounts, diagnostic builds, or additional documentation on short notice.
