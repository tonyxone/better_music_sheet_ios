# App Store release copy — 27 September 2026

## Account setup verified this session

AdMob: published **Better Music Sheet — European consent** for Better Music Sheet,
English, targeting EEA, UK and Switzerland. Consent, Do not consent and Manage
options are enabled; the decline choice is enabled for every region. Published
**Better Music Sheet — US privacy choices**, English, targeting all current and
future supported US states. Both display `1 active` in Privacy & messaging.
Privacy policy URL: https://bettermusicsheet.com/privacy/.

Evidence: `/Users/tonyxone/Desktop/workspace/bms-subscription-release/consent-evidence/both-active.png`.
These publications do not prove real-device consent or ad delivery. Google says
publication can take up to an hour to propagate.

After the account holder signed back in, App Store Connect was updated:
- Saved this description and app-review notes explaining Free and Premium.
- Saved support URL https://bettermusicsheet.com/about/ after verifying its public contact details.
- Corrected age-rating Advertising to Yes; Apple's calculated rating remains 4+.
- Published all six missing AdMob data categories and corrected Device ID purposes/linkage.
  Thirteen total data types are now disclosed; no unfinished setup warnings remain.
- Verified the privacy-policy URL and both production/sandbox notification URLs.
  The current notification URL editor does not show a protocol-version selector.
- Verified both subscription review screenshots. Yearly notes now contain the detailed
  instructions below. Monthly has existing notes and is locked after being added
  to a review draft; the app-level notes now provide the detailed monthly steps too.
- Verified build 1 selected with its icon, three iPhone previews and ten iPhone
  screenshots. The required iPad 13-inch slot is empty (0 screenshots).
- Created Better Music Sheet Internal with automatic distribution off; added
  build 1 (Ready to Test) and the existing account holder Tao Liang as its sole
  tester. Apple shows Invited. No other testers were invited.

Evidence: `/Users/tonyxone/Desktop/workspace/bms-subscription-release/asc-evidence/privacy-published.png`.
TestFlight evidence: `/Users/tonyxone/Desktop/workspace/bms-subscription-release/asc-evidence/testflight-invited.png`.
No App Review submission was made. The account holder reports that a subscription
purchase works in TestFlight build 1. Renewal, cancellation, refund, expiry,
restore and notification delivery are not established by that report.
Earlier readiness documents contain older states.

## Description

Make piano sheet music easier to read and practise. Better Music Sheet adds
letter names to the notes in your PDF or photo, then plays the music with a
keyboard that lights up as each note sounds.

• Import a PDF or choose a photo of your sheet music.
• Read your score with note names, including sharps and flats.
• Follow synchronized playback and highlighted measures.
• Rotate to landscape to practise with falling notes and a piano keyboard.
• Adjust playback speed, loop a passage, or step through the notes.
• Customize note labels and add handwritten marks or text notes.
• Export your customized sheet as a PDF.
• Try the sample score without creating an account.

The Free plan lets a signed-in account keep one sheet at a time and includes ads.
Premium adds unlimited sheet storage and removes ads. Premium access is shared
across the website, iPhone and iPad when you sign in to the same account.

Premium is available as a monthly or yearly auto-renewable subscription. Eligible
new subscribers receive a 7-day free trial. Prices and eligibility are shown in
the app before purchase. Payment is charged to your Apple Account at purchase
confirmation, or after an eligible free trial. The subscription renews unless
cancelled at least 24 hours before the current period ends. Your account is
charged for renewal within 24 hours before the end of the current period. Manage
or cancel subscriptions in your Apple Account settings. Any unused portion of a
free trial is forfeited when you purchase a subscription, where applicable.

Note recognition is automatic and may make mistakes. Check the generated notes
against your original score. Upload and recognition require an internet connection.

Privacy Policy: https://bettermusicsheet.com/privacy/
Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

## Other listing fields

- Suggested subtitle: Note names & piano practice
- Suggested keywords: piano,sheet music,note names,sight reading,practice,keyboard,score,playback,pdf,music learning
- Suggested primary category: Music
- Suggested secondary category: Education
- Privacy policy: https://bettermusicsheet.com/privacy/
- Support destination: use a public page with visible contact details. The website's
  About page is a candidate; verify it before saving. Public contact on the live
  site: bettermusicsheet@gmail.com.
- Copyright: enter the account holder's preferred legal attribution.
- Age rating: answer from actual content and features. The app contains advertising;
  confirm AdMob content-rating and sensitive-category settings. Do not claim
  parental controls, age assurance, public chat or a public user-content feed.
  Private uploads are not a public social feed. Do not select the Kids category
  based solely on its educational purpose.

## Reviewer and subscription notes

Better Music Sheet converts a user's PDF or image into a score with note names
and synchronized piano playback. From the Library, open the sample score to
review reading and practice without signing in. For your own uploads and Premium
purchases, open Account and sign in using the supplied review account.

Free accounts can keep one sheet at a time and show banner ads. Premium offers
unlimited sheet storage and no ads. Monthly and yearly plans offer the same
Premium features and are alternatives in the same subscription group. Eligible
new subscribers receive a seven-day introductory trial; the paywall uses Apple's
eligibility result and localized prices. Premium is linked to the signed-in app
account and works on the website, iPhone and iPad with that account.

To reach the paywall: Account → See Premium Plans. Choose Monthly or Yearly,
then use the displayed purchase button. Restore Purchases is available in the
paywall and Account screen. Apple-billed subscriptions can be managed through
Account. Rotate an open score to landscape to see the practice keyboard and
falling notes. Ad privacy choices are available in Account when required by
Google's consent platform.

Supply and verify a working **Free-tier** review account through App Store
Connect's dedicated sign-in fields. A master or already-Premium account may hide
the subscription offer. Do not put credentials in this document or git.

Monthly review notes: use the steps above and select Monthly.
Yearly review notes: use the steps above and select Yearly.
Existing review captures are real iPad app UI with local StoreKit test products;
they do not establish that live Apple sandbox purchases work.

## App Privacy evidence and draft answers

Apple's questions must cover the app and its third-party SDKs. Website-only Google
Analytics and Stripe card entry do not automatically belong in the iOS answers.
Apple processes iOS payment details; the backend stores purchase/entitlement records.

First-party collection, linked to the signed-in user, for App Functionality:
Name, Email Address, User ID, Purchase History, uploaded Photos or Videos (images),
and Other User Content (PDFs, edits and notes). Confirm the current backend's
processing and storage before final publication.

The archived Google Mobile Ads SDK privacy manifest declares:

| Apple data type | Linked | Purposes |
| --- | --- | --- |
| Coarse Location | Yes | Third-Party Advertising, Developer Advertising or Marketing, Analytics |
| Device ID | Yes | Third-Party Advertising, Developer Advertising or Marketing, Analytics |
| Advertising Data | Yes | Third-Party Advertising, Developer Advertising or Marketing, Analytics |
| Product Interaction | Yes | Third-Party Advertising, Developer Advertising or Marketing, Analytics |
| Performance Data | No | Third-Party Advertising, Developer Advertising or Marketing, Analytics |
| Other Diagnostic Data | No | Third-Party Advertising, Developer Advertising or Marketing, Analytics |
| Crash Data | No | Analytics |

User Messaging Platform also declares Coarse Location, Performance Data and
Product Interaction, not linked, for App Functionality. Include App Functionality
among those types' purposes when consolidating the answers.

The Google SDK manifest marks Device ID as potentially used for tracking. The
current app requests non-personalized ads (`npa=1`), does not request ATT authorization,
has no mediation adapters, and its own manifest declares no tracking. The current
App Privacy answers say no tracking: Google documents that unavailable ATT permission
prevents IDFA being sent, and publisher first-party IDs use data from the publisher's
own apps. Device ID is still disclosed as linked and used for advertising/analytics.
Reassess the answers if ATT, personalized ads, mediation or new SDKs are introduced.
This is configuration-based assessment, not a captured network-traffic audit.
Non-personalized ads do not justify claiming no collection. Precise GPS location
is not inferred from IP-based coarse location.

Sources:
- https://developers.google.com/admob/ios/privacy/data-disclosure
- https://developers.google.com/admob/ios/privacy/idfa
- https://developers.google.com/admob/ios/privacy/strategies
- https://developer.apple.com/app-store/user-privacy-and-data-use/
- Archived SDK manifests in `bms-subscription-release/BetterMusicSheet.xcarchive/Products/Applications/better_music_sheet_ios.app/Frameworks/`
- Current iOS account, upload, subscription and ads source.

The website privacy source has been updated locally to describe iOS AdMob and
the one-sheet Free plan. Targeted ESLint and `git diff --check` passed. Deployment
and live policy verification are still required.

## Notification and testing checks

Use https://api.bettermusicsheet.com/api/webhooks/apple for production and sandbox,
with Server Notifications V2. Previous account setup records both URLs saved;
verify rather than replace them unnecessarily. Deployment records show an invalid
signedPayload returns 400 rather than the old unconfigured 503; actual Apple TEST
delivery and subscription state updates still require testing.

Test the actual TestFlight build: consent in a supported region, banner delivery
for Free and no ads for Premium, monthly/yearly purchases, restore, renewal,
cancellation, expiry and refund. Confirm server changes while the app is closed.
An uploaded icon does not by itself prove the purchase sheet will show it.
Build 1 was uploaded before the ads and consent changes were merged on 27 September.
The account holder confirms it lacks the current ads and that its subscription
purchase works. The latest Release archive (1.0 build 2) uploaded successfully at
13:00 on 27 September. Apple processing completed and build 1.0 (2) is
enabled with status Testing in Better Music Sheet Internal. The archive
contains the production AdMob banner unit and Ad Privacy Choices. Google SDK
dSYM upload warnings did not prevent the successful upload.
Nothing was submitted for App Review in this session.

## Ad verification and first-launch correction

On 27 September, the connected iPad Air (4th generation), iOS 27, ran a
separate Debug app (`com.bettermusicsheet.app.adverification`, BMS Ad Test)
with Google's test banner unit, without replacing TestFlight.
With UMP consent reset, the original empty Group in AdBannerSlot never ran
its consent task and produced no ad lifecycle callbacks. A persistent ZStack
with a clear placeholder ran the task: canRequestAds=true followed by
bannerViewDidReceiveAd at 13:26:17. The fixed 320x50 banner is centered within
the slot. The slot has zero height while consent/loading is pending or a
banner fails; it expands only after a successful load. Errors are confined
to developer logs. Consent and banner errors now have diagnostic logging.
Evidence logs are in the sibling bms-subscription-release folder:
ad-original-layout-console.log and ad-fixed-fresh-console.log.
This confirms test-ad loading; production inventory remains subject to
AdMob readiness review and fill. The zero-height loading version was also verified on the iPad after UMP reset:
canRequestAds=true and Banner loaded at 13:29:18. Build 3 archived and uploaded
successfully at 13:34:38 on 27 September. Apple processing completed;
build 1.0 (3) is enabled with Testing status in Better Music Sheet Internal.
