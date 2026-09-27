# Apple subscription readiness — 26 September 2026

## Latest setup update

The account holder reports manual items 1–4 complete: banking/agreement, EU trader declaration, the In-App Purchase key, and AWS billing secret configuration. These account-side completions are user-reported. The release and drift workflows now forward all eight uppercase Apple billing variables and mask private-key lines. Deployment and sandbox/device verification remain to be confirmed.

## Completed

- iOS bundle: `com.bettermusicsheet.app`; App Store app ID: `6814721766`.
- StoreKit products: `com.bettermusicsheet.app.premium.monthly` and `com.bettermusicsheet.app.premium.yearly`.
- Purchases require sign-in and carry the account UUID as Apple's appAccountToken. Server delivery must succeed before the transaction is finished or Premium is enabled.
- Launch, foreground, sign-in and Restore retry unfinished transactions. Offline entitlement snapshots are tied to their owner and expire at the server's period end.
- Paywall uses Apple's per-product introductory eligibility and displays Privacy/EULA links and renewal disclosures.
- Backend rejects transaction ownership mismatches, handles Apple's signedPayload JSON envelope, re-queries Apple's server for authoritative status, handles grace periods and tries sandbox only after production returns 404.
- Terraform and deployment secret loaders now pass the Apple billing variables to the API Lambda. The privacy page has been updated locally.
- App Store Connect: both products at level 1; seven-day free trials in all 175 regions with no end date; production and sandbox notification URLs saved; description includes renewal and legal disclosures.

## Remaining blockers

1. Create the In-App Purchase key in Users and Access → Integrations → In-App Purchase. The prepared request is awaiting explicit approval because it creates persistent security-sensitive access. Download the .p8 once and retain it securely.
2. Configure AWS credentials locally. Add the following uppercase keys to the existing deployment secret without replacing its other entries: APPLE_KEY_ID, APPLE_ISSUER_ID and APPLE_PRIVATE_KEY (PEM with real newlines). These are distinct from lowercase Sign in with Apple credentials. Obtain explicit approval before transmitting the private key to AWS.
3. Deploy the backend, Terraform and privacy page through the existing deployment workflow. Defaults supply APPLE_APP_ID=6814721766, APPLE_BUNDLE_ID=com.bettermusicsheet.app, APPLE_ENV=auto and the two product IDs. The live webhook currently returns 503 because Apple billing is not configured. Terraform HCL parses; a real Terraform plan has not run.
4. Account holder must complete Business banking information, activate the Paid Apps Agreement (currently Pending User Info), and complete the EU trader declaration. Financial information and legal acceptance require the account holder's action.
5. Test on a real device using Apple's sandbox: monthly/yearly purchase, eligible and ineligible trial display, renewal, cancellation, expiry, refund, Restore, different app accounts, offline delivery and delivery retry. Check server notifications and premium access in both iOS and the website. No real purchase test has been completed.
6. Capture authentic app screenshots and a paywall screenshot for each subscription's review information. Upload the signed build; select it for version 1.0; attach both first subscriptions; finish remaining version/privacy/review metadata; submit the app and subscriptions together. No review has been submitted.

## Validation and artifacts

214 runnable Swift tests passed; the existing everyInstrumentShipsWithTheApp test requires resources absent from SwiftPM and was excluded. Backend subscription/sign-in/deletion tests passed. Website Next type generation and TypeScript checking passed. Signed iOS Release archive and App Store IPA export succeeded. The final archive is `/tmp/bms-subscriptions.xcarchive`; the exported IPA is retained in `/Users/tonyxone/Desktop/workspace/bms-subscription-release/ipa`. Source fixes are local and have not been deployed or submitted.

Source references: https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase and https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases
