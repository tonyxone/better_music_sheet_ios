# Manual Apple subscription setup

Checked 26 September 2026. Items 1–4 have now been completed by the account holder. Workflow forwarding is fixed in source. The steps below remain a reference; do not recreate the key or replace completed account settings. Deployment, upload, device testing and review submission still need verification.

1. **Business / Paid Apps Agreement** — Sign in as Account Holder in App Store Connect. Open Business and the Paid Apps Agreement. Complete required legal/contact information, add the bank account and confirm ownership, complete any outstanding tax forms, accept any pending agreement, and wait for Active. Last audit: Pending User Info; no bank account; W-9 Active.

2. **EU trader declaration** — In Business/compliance, complete the Digital Services Act trader declaration. Choose the status that accurately applies to you, supply/verify requested business contact information and supporting documents, and check EU distribution availability. Apple displays trader contact information publicly. Last audit: incomplete.

3. **In-App Purchase API key** — Users and Access → Integrations → Keys → In-App Purchase → Generate In-App Purchase Key. Name it BetterMusicSheet Billing, generate, record Key ID and Issuer ID, download the .p8 once and store securely. This is separate from Sign in with Apple. Do not commit or paste the private key into chat.

4. **AWS secret** — In the correct AWS account, open Secrets Manager in us-west-1, find better_music_sheet_singin_provider, retrieve/edit its existing JSON, and preserve all existing entries. Add APPLE_KEY_ID, APPLE_ISSUER_ID and APPLE_PRIVATE_KEY. The private key value is the full PEM, including BEGIN/END lines; use escaped newline characters if editing JSON text. Optionally add the defaults below explicitly. Save a new secret version.

| Variable | Value |
| --- | --- |
| APPLE_APP_ID | 6814721766 |
| APPLE_BUNDLE_ID | com.bettermusicsheet.app |
| APPLE_ENV | auto |
| APPLE_PRODUCT_MONTHLY | com.bettermusicsheet.app.premium.monthly |
| APPLE_PRODUCT_YEARLY | com.bettermusicsheet.app.premium.yearly |

Uppercase APPLE_* variables are billing credentials; lowercase apple_* variables are Sign in with Apple. Keep both sets.

5. **Deployment access and workflow prerequisite** — If deploying from this Mac, install AWS CLI, Terraform and jq, configure the existing account's AWS profile (SSO preferred where available), and verify identity with aws sts get-caller-identity. If using GitHub Actions, existing OIDC roles can be used instead of local AWS credentials. The explicit environment-persistence loops in .github/workflows/release.yml and drift.yml now include all eight APPLE_* variables and mask private-key lines. The loader alone was insufficient because its environment does not persist to the later Terraform step. Review/commit/merge the local subscription changes in both repositories, keeping unrelated work separate. Then in the BetterMusicSheet GitHub repository: Actions → Release → Run workflow → select the branch containing the fixes → enable Deploy after building. Verify the active target is serverless and all image build, Apply Terraform, backend deployment, web build/deployment and cache invalidation jobs succeed. If using local Terraform, use the existing terraform-with-secrets wrapper and current backend/tfvars; review a plan before applying. Do not reset existing deployed image tags.

6. **Live verification** — Confirm the API Lambda has all eight Apple variables, without exposing the private key in logs. Confirm https://bettermusicsheet.com/privacy/ serves the updated page. Both notification URLs are already https://api.bettermusicsheet.com/api/webhooks/apple. Validate Apple TEST notification delivery and an actual sandbox subscription state update; a successful TEST alone does not prove authenticated transaction lookup works. Last audit: live endpoint returned 503, Apple billing unconfigured.

7. **Subscription metadata** — Apps → Better Music Sheet → Monetization → Subscriptions → BetterMusicSheetPremiumSubscribtion. Open monthly and yearly. Verify prices/storefronts, display names/descriptions, tax category and availability. Both are already level 1 with seven-day introductory trials in 175 regions and no end date. Keep the existing product IDs. Upload an authentic paywall screenshot under each product's Review Information and explain how to reach the paywall. Resolve every missing-metadata warning. Family Sharing is off; do not turn it on without implementing/testing the intended behavior. Review Streamlined Purchasing before release: the present account-binding flow assumes purchases originate after in-app sign-in; disable out-of-app purchasing if that flow cannot provide appAccountToken, or implement/test support first.

8. **Build upload / TestFlight** — The signed IPA is /Users/tonyxone/Desktop/workspace/bms-subscription-release/ipa/better_music_sheet_ios.ipa. Upload using Apple's Transporter, or open the final archive /tmp/bms-subscriptions.xcarchive in Xcode Organizer → Distribute App → App Store Connect → Upload. Keep a durable copy of the archive before temporary-file cleanup. If code changes, rebuild; increment build number if Apple has already received the previous number. Wait for processing, complete export-compliance prompts accurately, and enable internal TestFlight testing.

9. **Sandbox testing** — Users and Access → Sandbox → create Sandbox Apple Accounts. Use a fresh eligible account for each plan's introductory-offer test. For development builds, enable Developer Mode on the device and sign into the Sandbox Apple Account in Settings → Developer. Install the development build from Xcode, or follow Apple's TestFlight sandbox instructions for the uploaded build. Sign into a normal BetterMusicSheet test account inside the app. Test monthly and yearly purchase, trial eligibility after purchase history, renewal/cancellation/expiry, Restore, reinstall, app-account switching, backend-unavailable delivery and retry, and website entitlement access. Use a separate sandbox tester to exercise another subscription in the same group without misleading trial history. Verify notifications update the server and expired subscriptions remove access. No real-device purchase tests have been completed.

10. **App Store version metadata and screenshots** — Apps → Better Music Sheet → Distribution → iOS version 1.0. Select the processed build. Upload genuine iPhone and iPad screenshots in the sizes App Store Connect requests; the app supports both. Complete description, keywords, category, age rating, support URL, copyright, pricing/availability, App Privacy questionnaire and privacy-policy URL https://bettermusicsheet.com/privacy/. Answer privacy questions from actual backend/app data use. Verify the saved description retains the Apple standard EULA link https://www.apple.com/legal/internet-services/itunes/dev/stdeula/. Complete encryption/export-compliance prompts accurately. Supply a working reviewer login and contact information, and exact steps to reach the paywall, purchase/restore and sample content. Existing review login must be verified to work.

11. **Submit together** — After deployment and testing, use version 1.0's In-App Purchases and Subscriptions selection to attach both monthly/yearly products. Clear all remaining validation errors. Choose your release option, Add for Review, inspect the submission and Submit for Review. The first subscriptions must accompany a new app version. Monitor App Review messages and respond to concrete issues. Nothing has been submitted yet.

Apple references:
- https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/generate-keys-for-in-app-purchases
- https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases
- https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements
- https://developer.apple.com/help/app-store-connect/test-in-app-purchases/overview-of-testing-in-sandbox
- https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase
