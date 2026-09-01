# Live Location Privacy and Release Checklist

## Data flow

- A linked, verified Driver explicitly starts sharing for one assigned `DISPATCHED` or `IN_PROGRESS` trip.
- The phone captures GPS observations; the backend derives organization, driver, vehicle, assignment eligibility, and canonical trip status from the Bearer token and database.
- Each observation receives one UUID, is encrypted in a SQLCipher queue before upload, and is retried with the same UUID.
- Uploads use `POST /api/driver/me/trips/:tripId/locations` in oldest-first batches of at most 50. Only acknowledged IDs are deleted.
- JWTs and the SQLCipher key use Android Keystore/iOS Keychain through `flutter_secure_storage`. JWTs are never stored in SharedPreferences.
- SharedPreferences stores only the active trip resume marker and consent version. Resume always revalidates the server assignment.
- Coordinates, tokens, contacts, and request bodies are not written to application logs. Diagnostics exposed to the UI contain only queue counts, permission state, timestamps, accuracy, and HTTP-class actions.
- Terminal server reconciliation stops GPS and clears that trip's queued points. Signing out or losing connectivity stops/preserves data according to the server contract.

## Release checklist

- Verify Android 13, 14, and 15 foreground location service notification, locked-screen capture, permission revocation, Doze, process recreation, and network switching.
- Verify iOS current and previous major versions for When In Use/Always settings, blue background indicator, locked-screen behavior, process termination limitations, and permission revocation.
- Run a physical-device assigned trip for at least 30 minutes and confirm first-point `IN_PROGRESS`, web freshness, stable retry IDs, battery use, and terminal stop.
- Confirm production uses an HTTPS `API_BASE_URL` build define and no development hostname or TLS pin is embedded.
- Confirm App Store/Play disclosures explain active-trip-only collection, dispatch/safety/ETA purpose, encrypted offline storage, and server retention policy.
- Confirm Android notification tap returns to TransitOps and OEM battery guidance is factual rather than claiming optimization bypass.
- Confirm horizontally scaled backend deployments replace process-local SSE fan-out with a shared pub/sub layer; REST/database correctness remains independent.

## Platform limitations

Android foreground services and iOS background location are subject to OS/OEM scheduling and user settings. The UI reports `LIVE` only after server acknowledgement and never promises exact 10-second delivery while the OS suspends or restricts the application.
