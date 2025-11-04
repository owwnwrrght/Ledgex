# Payment Integration Feature

## Overview

Ledgex now supports one-click settlement payments through multiple payment providers, allowing users to instantly pay their debts directly within the app.

## Supported Payment Providers

### 1. Apple Pay Cash
- **Type**: Native iOS integration
- **Requires**: Merchant ID configuration in Apple Developer Console
- **Implementation**: PassKit framework
- **Status**: Implemented

### 2. Venmo
- **Type**: Deep link integration
- **URL Scheme**: `venmo://paycharge`
- **Requires**: Venmo app installed
- **Status**: Implemented

### 3. PayPal
- **Type**: SDK + Web fallback
- **Integration**: PayPalCheckout SDK (added to Podfile)
- **Fallback**: PayPal.me web links
- **Status**: Implemented

### 4. Zelle
- **Type**: Deep link integration
- **URL Scheme**: `zelle://send`
- **Requires**: Zelle-supported banking app
- **Status**: Implemented

### 5. Cash App
- **Type**: Deep link integration
- **URL Scheme**: `cashapp://cash.app`
- **Requires**: Cash App installed
- **Status**: Implemented

## Architecture

### New Models

#### `PaymentProvider` (PaymentMethod.swift)
Enum representing all supported payment providers with:
- Display names
- System icons
- URL schemes for deep linking
- SDK requirements flags

#### `PaymentStatus` (PaymentMethod.swift)
Tracks payment lifecycle:
- `pending`: Payment initiated
- `processing`: In progress
- `completed`: Successfully completed
- `failed`: Transaction failed
- `cancelled`: User cancelled
- `refunded`: Payment refunded

#### `PaymentTransaction` (PaymentMethod.swift)
Record of payment attempts with:
- Settlement linkage
- Provider information
- Amount and currency
- User IDs (from/to)
- External transaction IDs
- Error messages
- Timestamps

#### `LinkedPaymentAccount` (PaymentMethod.swift)
User's linked payment accounts:
- Provider type
- Account identifier (email, username, phone)
- Verification status
- Last used timestamp

### Updated Models

#### `Settlement` (Settlement.swift)
Enhanced with payment tracking:
- `paymentTransactionId`: Link to transaction
- `paymentProvider`: Which provider was used
- `paymentStatus`: Current payment status
- `paymentInitiatedAt`: When payment started
- `paymentCompletedAt`: When payment finished
- `externalTransactionId`: Provider's transaction ID

#### `UserProfile` (UserProfile.swift)
Added payment preferences:
- `linkedPaymentAccounts`: Array of linked accounts
- `defaultPaymentProvider`: User's preferred provider

### Services

#### `PaymentService` (PaymentService.swift)
Core payment orchestration service:

**Key Methods:**
- `isProviderAvailable(_ provider:)`: Check if payment app is installed
- `availableProviders()`: Get list of available providers
- `initiatePayment(settlement:provider:recipientAccount:)`: Start payment flow
- `processApplePayCash()`: Handle Apple Pay transactions
- `processVenmoPayment()`: Open Venmo with prefilled data
- `processPayPalPayment()`: Launch PayPal SDK or web
- `processZellePayment()`: Open Zelle app
- `processCashAppPayment()`: Open Cash App

**Payment Flow:**
1. Validate amount and provider availability
2. Check user has linked account for provider
3. Route to provider-specific handler
4. Generate deep link or launch SDK
5. Record transaction in Firebase
6. Auto-mark settlement as received on success

### Views

#### `PaymentMethodsView` (PaymentMethodsView.swift)
Account management interface:
- View all linked payment accounts
- Add new payment accounts
- Set default payment provider
- Verify account identifiers
- Delete accounts
- Educational information about payment security

**Features:**
- Visual provider icons with brand colors
- Account verification badges
- Default provider indication
- Provider availability checking
- Inline account validation

#### `SettlementsView` (SettlementsView.swift)
Enhanced with payment buttons:
- "Pay Now" button for users who owe money
- Payment method selector dialog
- Quick pay with default provider
- Payment status badges
- Error handling and retry
- Manual fallback option

**User Experience:**
- Tap settlement row to initiate payment
- Choose from linked payment accounts
- Automatic provider app launch
- Real-time payment status updates
- Error messages with recovery options

## Configuration

### 1. Entitlements

Both `Ledgex.entitlements` and `Ledgex.production.entitlements` now include:

```xml
<key>com.apple.developer.in-app-payments</key>
<array>
    <string>merchant.com.ledgex.app</string>
</array>
<key>com.apple.developer.payment-pass-provisioning</key>
<true/>
```

### 2. Info.plist (AppInfo.plist)

Added URL schemes for payment app detection:

```xml
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>venmo</string>
    <string>cashapp</string>
    <string>zelle</string>
    <string>paypal</string>
</array>
```

### 3. Dependencies (Podfile)

Added PayPal SDK:

```ruby
pod 'PayPalCheckout', '~> 1.0'
```

## Setup Instructions

### For Developers

1. **Install Dependencies:**
   ```bash
   cd /path/to/Ledgex
   pod install
   ```

2. **Configure Merchant ID:**
   - Log in to Apple Developer Console
   - Create Merchant ID: `merchant.com.ledgex.app`
   - Add to Xcode project capabilities
   - Update `PaymentService.swift` line 134 with your Merchant ID

3. **Test Payment Providers:**
   - Install Venmo, Cash App, Zelle, PayPal on simulator/device
   - Link test accounts in PaymentMethodsView
   - Create test settlements
   - Verify deep links work correctly

### For End Users

1. **Link Payment Accounts:**
   - Navigate to Settle Up tab
   - Tap credit card icon (top right)
   - Tap "Add Payment Method"
   - Choose provider and enter account details
   - Set default provider (optional)

2. **Make Payments:**
   - Go to Settle Up tab
   - Tap "Pay Now" on any settlement you owe
   - Choose payment method from dialog
   - Confirm in payment app
   - Settlement auto-marks as received

## Deep Link Formats

### Venmo
```
venmo://paycharge?txn=pay&recipients=USERNAME&amount=AMOUNT&note=NOTE
```

### Cash App
```
cashapp://cash.app/$CASHTAG/AMOUNT
```

### Zelle
```
zelle://send?amount=AMOUNT&email=EMAIL&note=NOTE
```

### PayPal
```
https://www.paypal.me/USERNAME/AMOUNT
```

## Security Considerations

1. **No Financial Data Storage:**
   - App only stores account identifiers (usernames, emails)
   - No card numbers, bank details, or sensitive financial data
   - All actual payment processing happens in provider apps

2. **Account Verification:**
   - Users must verify accounts in payment apps
   - App validates format but not ownership
   - Production should implement server-side verification

3. **Transaction Tracking:**
   - All payment attempts logged in Firebase
   - Includes timestamps, amounts, providers
   - Helps with dispute resolution

4. **Privacy:**
   - Account identifiers stored in user's Firebase profile
   - Not shared with other trip members
   - Can be deleted at any time

## Firebase Backend Integration

### Firestore Collections

#### `paymentTransactions` (new)
```javascript
{
  id: UUID,
  settlementId: UUID,
  provider: string,
  status: string,
  amount: number,
  currency: string,
  fromUserId: UUID,
  toUserId: UUID,
  externalTransactionId: string?,
  errorMessage: string?,
  createdAt: timestamp,
  updatedAt: timestamp,
  completedAt: timestamp?
}
```

#### `userProfiles` (updated)
```javascript
{
  // ... existing fields ...
  linkedPaymentAccounts: [
    {
      id: UUID,
      provider: string,
      accountIdentifier: string,
      displayName: string?,
      isVerified: boolean,
      linkedAt: timestamp,
      lastUsed: timestamp?
    }
  ],
  defaultPaymentProvider: string?
}
```

#### `trips/{tripId}/settlements` (updated)
```javascript
{
  // ... existing fields ...
  paymentTransactionId: UUID?,
  paymentProvider: string?,
  paymentStatus: string?,
  paymentInitiatedAt: timestamp?,
  paymentCompletedAt: timestamp?,
  externalTransactionId: string?
}
```

### Cloud Functions (Recommended)

#### `verifyPaymentWebhook`
Webhook endpoint for PayPal/other SDKs to confirm payments:
```javascript
exports.verifyPaymentWebhook = functions.https.onRequest(async (req, res) => {
  // Verify webhook signature
  // Update transaction status
  // Mark settlement as received
  // Send notifications
});
```

#### `recordPaymentAttempt`
Logs all payment attempts:
```javascript
exports.recordPaymentAttempt = functions.firestore
  .document('paymentTransactions/{transactionId}')
  .onCreate(async (snap, context) => {
    // Log to analytics
    // Send confirmation email
    // Update settlement status
  });
```

## Error Handling

### Common Errors

1. **Provider Not Available:**
   - User: "Payment provider app is not installed"
   - Action: Prompt to install app or choose different provider

2. **Account Not Linked:**
   - User: "Please link your payment account first"
   - Action: Navigate to PaymentMethodsView

3. **Invalid Amount:**
   - User: "Invalid payment amount"
   - Action: Check settlement calculation

4. **Network Error:**
   - User: "Network connection error"
   - Action: Retry with exponential backoff

5. **User Cancelled:**
   - User: Silent dismissal
   - Action: Keep settlement unpaid, allow retry

### Error Recovery

- All errors show inline in SettlementRow
- Users can retry immediately
- Fallback to manual "Mark Received" always available
- Error messages include actionable guidance

## Testing Checklist

### Unit Tests Needed
- [ ] PaymentProvider availability checking
- [ ] Deep link URL generation
- [ ] Account identifier validation
- [ ] Payment status transitions
- [ ] Error handling paths

### Integration Tests Needed
- [ ] Venmo app launch with correct data
- [ ] Cash App deep link format
- [ ] Zelle deep link format
- [ ] PayPal web fallback
- [ ] Apple Pay merchant ID validation

### UI Tests Needed
- [ ] Link payment account flow
- [ ] Set default provider
- [ ] Initiate payment from settlement
- [ ] Handle provider not installed
- [ ] Payment success confirmation
- [ ] Payment error display
- [ ] Delete payment account

### Manual Testing
1. Link accounts for each provider
2. Create test settlements
3. Initiate payments for each provider
4. Verify correct app opens with prefilled data
5. Complete payment in provider app
6. Verify settlement marks as received
7. Test error scenarios (no app, wrong identifier)
8. Test on different iOS versions (16.0+)

## Future Enhancements

### Phase 2
- [ ] Stripe Direct API integration
- [ ] Google Pay support
- [ ] Cryptocurrency payment options
- [ ] Payment request system (recipient can request payment)
- [ ] Recurring payment scheduling
- [ ] Split payment across multiple methods
- [ ] Payment reminders and nudges

### Phase 3
- [ ] In-app payment processing (become money transmitter)
- [ ] Escrow service for disputed payments
- [ ] Automatic expense reimbursement
- [ ] Integration with bank accounts (Plaid)
- [ ] International payment support
- [ ] Currency conversion at payment time

## Compliance & Legal

### Important Notes

1. **Money Transmitter License:**
   - Current implementation does NOT move money
   - App only initiates external payments
   - No MTL required for deep linking approach

2. **Apple App Store Guidelines:**
   - Complies with 3.1.5(h) - peer-to-peer payments
   - No Apple In-App Purchase required
   - Physical services/person-to-person payments exempt

3. **User Agreement Updates:**
   - Update Terms of Service to mention payment integration
   - Add disclaimer about third-party payment processors
   - Clarify Ledgex is not responsible for failed payments

4. **Privacy Policy:**
   - Disclose payment account identifiers storage
   - Explain data sharing with payment providers
   - Detail transaction logging practices

## Support & Troubleshooting

### Common User Issues

**Q: Why can't I see payment buttons?**
- A: Link at least one payment account via Settings

**Q: Payment app doesn't open**
- A: Ensure app is installed and up to date

**Q: Payment completed but settlement not marked**
- A: Tap "Mark Received" manually, or wait for auto-sync

**Q: Wrong amount showing in payment app**
- A: Check currency conversion settings

**Q: Can I use multiple payment methods?**
- A: Yes, link multiple accounts and choose per payment

### Developer Contact

For implementation questions or bug reports:
- Email: dev@ledgex.app
- GitHub Issues: [link]
- Slack: #payments channel

## Rollout Plan

### Phase 1: Beta Testing (Week 1-2)
- Deploy to TestFlight
- Limit to 50 beta testers
- Collect feedback on UX
- Monitor error rates
- Fix critical bugs

### Phase 2: Staged Rollout (Week 3-4)
- Release to 10% of users
- Monitor payment success rates
- Analyze most-used providers
- Optimize deep link flows
- Add missing providers based on demand

### Phase 3: Full Release (Week 5+)
- Release to 100% of users
- App Store feature request
- Marketing campaign
- Blog post and tutorial videos
- Monitor support tickets

## Metrics & Analytics

### Key Metrics to Track

1. **Adoption:**
   - % of users who link payment accounts
   - Average accounts linked per user
   - Most popular providers

2. **Usage:**
   - Payments initiated per week
   - Payment success rate
   - Average time to complete payment
   - Provider availability issues

3. **Conversion:**
   - Settlements paid via app vs. manual
   - Time from expense to settlement
   - Dispute rate after payment integration

4. **Errors:**
   - Top error types and frequencies
   - Provider-specific failure rates
   - Retry success rates

## Credits

**Developed by:** Ledgex Engineering Team
**Design:** UX Team
**Security Review:** Security Team
**Date:** 2025-11
**Version:** 1.0

---

*This feature represents a major milestone in making expense settlements frictionless and instant for Ledgex users.*
