# App Store submission

Little While is an iPhone-only app for iOS 18 or later. Prepare a release with the publish skill in stop-before-submission mode (`mise publish:stop_before_submit`) when the build and metadata should be ready for a final App Review submission.

## Release assets

`config.json` contains the description, keywords, screenshots, App Review contact, and review instructions. The iPhone 6.9-inch screenshot set uses `APP_IPHONE_67`; the supplied iPhone 6.3-inch captures use `APP_IPHONE_61`, the API display group for those devices. The larger screenshot is captured directly from iPhone 17 Pro Max with `mise publish:simulate iphone` and `xcrun simctl io <device-id> screenshot --type=jpeg`.

The app includes `PrivacyInfo.xcprivacy` declaring no tracking or collected data and the `CA92.1` reason for accessing its own UserDefaults. Settings links to the public privacy policy.

Support and marketing currently link to the public [support document](https://github.com/grahamotte/LittleWhile/blob/master/docs/support.md). The [privacy policy](https://github.com/grahamotte/LittleWhile/blob/master/docs/privacy-policy.md) is also publicly hosted in this repository. The littlewhile.app domain must resolve and serve these pages before switching the listing URLs to it.

## App-level settings

These settings are managed separately from the version metadata uploaded by the publish task:

- Primary category: Productivity.
- Subtitle: Focus for a little while.
- Privacy policy URL: https://github.com/grahamotte/LittleWhile/blob/master/docs/privacy-policy.md
- Content rights: no third-party content.
- Age rating: no restricted content, advertising, chat, public user-generated content, gambling, or unrestricted web access. Use the age rating calculated by Apple.
- App Privacy: select “No, we do not collect data from this app” and publish the answers in App Store Connect. The public API does not expose this questionnaire.
- Confirm pricing, territory availability, and any account-level agreements or compliance notices in App Store Connect before submission.

The app requires no sign-in or demo account. Allow notifications and, on iOS 26 or later, alarms to test background completion alerts. The review notes in `config.json` explain the timer, themes, history, and Live Activities.
