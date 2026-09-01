# TransitOps push notifications

TransitOps stores every alert in the existing notification inbox and delivers
the same event through Firebase Cloud Messaging (FCM). A failed push never
blocks a trip, driver review, expense, or maintenance operation.

## Event and recipient matrix

| Event | Mobile recipients |
| --- | --- |
| Trip created, dispatched, started, completed, or cancelled | Active operations users and the assigned driver |
| Driver profile submitted | Submitting driver, Owner, Admin, Fleet Manager, Safety Officer |
| Driver profile approved or rejected | The linked driver |
| Driver receipt processed by OCR | Submitting driver, Owner, Admin, Fleet Manager, Financial Analyst |
| Maintenance started or completed | Owner, Admin, Fleet Manager |

The app shows foreground notifications, opens an inbox when a notification is
tapped, maintains an unread badge, refreshes on pull, and unregisters the token
before logout. Payloads contain only routing IDs and screen names.

## One-time Firebase setup

1. Create a Firebase project and add Android app
   `in.transitops.transi_ops_app` and iOS app
   `in.transitops.transiOpsApp`.
2. In Firebase Cloud Messaging, upload the Apple APNs authentication key for
   the iOS app. The Apple bundle must also have Push Notifications and
   Background Modes enabled in its provisioning profile.
3. In Firebase project settings, create a server service account key. Base64
   encode the complete JSON without line breaks:

   ```bash
   base64 < firebase-service-account.json | tr -d '\n'
   ```

4. Set the backend value in `backend/.env` and restart the API:

   ```dotenv
   FIREBASE_SERVICE_ACCOUNT_JSON_BASE64=<base64-value>
   ```

5. Apply the production database migration:

   ```bash
   cd /path/to/FleetPilot/backend
   npx prisma migrate deploy
   ```

## Android build

Copy the public Firebase values from each registered app's Firebase settings.
These values identify the Firebase app and are safe to compile into the client;
the service-account JSON is server-only.

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://YOUR-NGROK-DOMAIN.ngrok-free.dev/api \
  --dart-define=FIREBASE_API_KEY=YOUR_FIREBASE_WEB_API_KEY \
  --dart-define=FIREBASE_PROJECT_ID=YOUR_FIREBASE_PROJECT_ID \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=YOUR_SENDER_ID \
  --dart-define=FIREBASE_ANDROID_APP_ID=YOUR_ANDROID_APP_ID
```

## iOS build

```bash
flutter build ipa --release \
  --dart-define=API_BASE_URL=https://YOUR_API_DOMAIN/api \
  --dart-define=FIREBASE_API_KEY=YOUR_FIREBASE_WEB_API_KEY \
  --dart-define=FIREBASE_PROJECT_ID=YOUR_FIREBASE_PROJECT_ID \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=YOUR_SENDER_ID \
  --dart-define=FIREBASE_IOS_APP_ID=YOUR_IOS_APP_ID \
  --dart-define=FIREBASE_IOS_BUNDLE_ID=in.transitops.transiOpsApp
```

Without these client defines, the app remains fully usable but intentionally
keeps push registration disabled. Existing in-app notifications still work.
