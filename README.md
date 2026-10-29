# PlainTees – Firebase-Based E-Commerce Clothing App with Xendit Payment Integration

PlainTees is a Flutter e-commerce application for selling plain T-shirts. Customers can
browse the catalog, choose a size, build a cart, check out, and pay through Xendit. Orders
are stored in Cloud Firestore, and payment status is confirmed by a Supabase Edge Function
and a Xendit webhook.

Shoppers sign in with an email and password. That account owns their orders, so the same
order history and the same live payment status appear on the website (Chrome/Windows) and
in the Android APK.

The project deliberately stays on the **Firebase Spark (free) plan**: payments are relayed
through Supabase Edge Functions, so no Firebase Functions, Secret Manager, or Blaze upgrade
is required.

---

## 1. Project Overview

PlainTees is a mobile storefront built with Flutter and backed by Firebase. The catalog is
read from the Firestore `products` collection (with a bundled fallback for offline use), the
cart is held in memory, and checkout writes an order document to Firestore before opening a
Xendit payment page in the browser.

Orders are owned by a Firebase Auth account (`user_id`), so Order History is a Firestore
query scoped to that account rather than a device-local list.

Because the Xendit secret key can never ship inside a mobile app, a small Supabase Edge
Function acts as the payment relay. It talks to Xendit, writes the payment link back to
Firestore, and later confirms the payment. The Flutter app only ever sees the payment link
and the order's status.

---

## 2. Features

| Feature | Description |
|---|---|
| Product catalog | Read from the Firestore `products` collection (10 plain T-shirts) with a bundled offline fallback |
| Product details | Full-size product view with price, description, and the sizes from `available_sizes` |
| Size selection | S, M, L, XL selector on the details screen |
| Shopping cart | Add, adjust quantity, remove items, and see the running total |
| Account | Email + password sign-in; one account works on the website and the app |
| Checkout | Validates the cart, creates the order, and starts payment |
| Synced order history | `orders` queried by `user_id`, so Chrome and Android show the same orders |
| Order information | Each order stores the item name, size, quantity, unit price, subtotal, image path, and total |
| Firestore order storage | Orders are written to the `orders` collection with a `pending` status |
| Xendit payment | A Xendit payment session/invoice is created per order and opened in the browser |
| Payment verification | `verify-xendit-payment` asks Xendit for the session status and updates Firestore |
| Xendit webhook | `xendit-webhook` receives Xendit callbacks and updates Firestore server-side |
| Payment-return deep link | `plaintees://payment-return` brings the customer back into the app |
| Payment status screen | Shows paid / pending / failed, with auto-retry and a "Check Again" button |
| Android APK | Release APK builds successfully and is ready to install |

Notes on scope:

- The cart is in-memory and resets when the app process is killed. The last order reference
  is persisted (via `shared_preferences`) so the customer can return to it.
- Browsing and the cart stay anonymous. Signing in is required only to place an order and
  to view Order History, because that is what links an order to the account that owns it.
- The order history list is mirrored into `shared_preferences` so it still opens offline;
  Firestore remains the source of truth on every refresh.

---

## 3. Technology Stack

| Layer | Technology |
|---|---|
| App | Flutter, Dart |
| Order database | Firebase Cloud Firestore |
| Accounts | Firebase Authentication (email + password) |
| Return page hosting | Firebase Hosting |
| Payment relay | Supabase Edge Functions (Deno / TypeScript) |
| Payment gateway | Xendit |
| Deep links | `app_links` |
| Opening the payment page | `url_launcher` |
| HTTP calls to the relay | `http` |
| Remembering the last order | `shared_preferences` |
| Firebase bootstrap | `firebase_core`, `cloud_firestore`, `firebase_auth` |

Firebase project: `plaintees-e-commerce` · Hosting: `https://plaintees-e-commerce.web.app`
Android package: `com.example.plain_tees`

---

## 4. Payment Architecture

```
Flutter app
  │  1. create pending order
  ▼
Cloud Firestore  ── orders/{orderId}  (payment_status: pending)
  │  2. POST /create-xendit-payment  { order_id, amount, items }
  ▼
Supabase Edge Function: create-xendit-payment
  │  3. create Xendit session (uses XENDIT_SECRET_KEY from Supabase secrets)
  ▼
Xendit  ── payment session / invoice
  │  4. customer pays in the browser
  ├──────────────► 5a. Xendit webhook  →  xendit-webhook
  └──────────────► 5b. app polls      →  verify-xendit-payment
                          │
                          ▼
                 Firestore payment_status updated (paid / failed / awaiting_payment)
                          │
 6. app reads the order   ▼
Flutter app  ──►  Payment success / pending / failed screen
```

Step by step:

1. Checkout writes an order to Firestore with `payment_status: "pending"`.
2. The app calls `create-xendit-payment` on Supabase with the order ID, amount, and items.
3. The function creates a Xendit payment session and returns a payment URL.
4. The app opens that URL in the browser and the customer pays.
5. Xendit notifies the backend through the webhook, and the status screen can also call
   `verify-xendit-payment` as a fallback.
6. Firestore is updated with the new status, and the app reads it back and shows the result.

### What is *not* used

- **No Firebase Functions.** The payment backend is Supabase Edge Functions.
- **No Firebase Secret Manager.** Secrets live in Supabase project secrets.
- **No Blaze plan.** The project stays on Firebase Spark. Firestore, Hosting, and rules
  deployment all fit within the free tier.
- **No Xendit secret inside the app.** The Flutter app only holds the Supabase URL and the
  publishable Supabase anon key. `XENDIT_SECRET_KEY`, `XENDIT_WEBHOOK_TOKEN`, and the
  Firebase service account used for server-side updates exist only as Supabase secrets.

### Endpoints

Base URL: `https://<supabase-project-ref>.supabase.co/functions/v1/`

| Function | Purpose | Caller |
|---|---|---|
| `create-xendit-payment` | Creates the Xendit session and stores the payment link | Flutter app |
| `verify-xendit-payment` | Reads the session from Xendit and syncs Firestore | Flutter app |
| `xendit-webhook` | Receives Xendit callbacks and syncs Firestore | Xendit |

### Firestore order fields

| Field | Written by | Meaning |
|---|---|---|
| `user_id` | App | Firebase Auth uid of the shopper who owns the order |
| `items` | App | Array of item snapshots (name, size, quantity, price, subtotal, image path) |
| `total` | App | Order total |
| `payment_method` | App | `Xendit` |
| `payment_status` | App → server | `pending` → `awaiting_payment` → `paid` / `failed` / `cancelled` |
| `order_status` | App → server | Fulfilment status (`pending` until paid) |
| `status` | App → server | Uppercase mirror of the order status |
| `created_at`, `updated_at` | App → server | Server timestamps |
| `payment_link_url` | Server | Xendit checkout URL |
| `xendit_session_id` | Server | Xendit payment session ID |
| `xendit_reference_id` | Server | Reference sent to Xendit (`plaintees-<orderId>`) |
| `paid_at` | Server | Set when payment completes |

Status mapping applied by the server: Xendit `COMPLETED` → `paid`, `EXPIRED` → `failed`,
`CANCELED` → `cancelled`, `ACTIVE` → `awaiting_payment`.

---

## 5. Deep Link Flow

When the payment session is created, Xendit is told to return the customer to:

```
https://plaintees-e-commerce.web.app/payment-return.html?order_id=<orderId>
```

That page (served by Firebase Hosting) reads `order_id` from the query string and forwards
the customer into the app:

```
plaintees://payment-return?order_id=<orderId>
```

The Android manifest registers that scheme, so `app_links` delivers it to `main.dart`. The
app then opens the payment status screen for that order.

Fallbacks, in order:

1. `order_id` from the deep link.
2. `session_id` scanned from the return query string.
3. The last saved order ID and session ID in `shared_preferences`.

Because the last order is persisted, a customer who closes the app and reopens it can still
reach the same payment status screen.

---

## 6. Firestore Security

Rules live in `firestore.rules` and are scoped to `orders/{orderId}` and `products/{productId}`.

| Rule | Behaviour |
|---|---|
| Create | Signed-in shoppers only; `user_id` must equal `request.auth.uid`, and the order must be a valid `pending` order with exactly the expected fields |
| Field whitelist | Only `user_id`, `items`, `total`, `payment_method`, `payment_status`, `order_status`, `status`, `customer_name`, `phone`, `address`, `city`, `postal_code`, `order_notes`, `created_at`, `updated_at` are accepted |
| Server timestamps | `created_at` and `updated_at` must equal `request.time` |
| Create as paid | Blocked — a client cannot create an order that already claims `payment_status: "paid"` |
| Create for someone else | Blocked — `user_id` must match the caller's uid |
| Read (get) | An individual order can be read by its document ID (needed by the status screen and payment deep link) |
| List | Only the signed-in owner, and only with `where('user_id', '==', uid)`. Unfiltered queries and other uids are denied |
| Update | Blocked for clients — payment status is only changed by the server |
| Delete | Blocked for clients |
| Products | Public read-only: anyone can read the catalog, no client can write it |
| Everything else | Closed by a catch-all `allow read, write: if false` |

Server-side updates are performed by the Edge Functions using a Firebase service account,
which bypasses security rules. That is why the client never needs update permission.

Trade-off to be aware of: an individual order is still readable by anyone who knows its
document ID, because the payment status screen must work before the auth session is
restored. Order IDs are random Firestore IDs, listing is restricted to the owner's own
documents, and order IDs are never shown publicly. No credentials, keys, or tokens are
stored in this repository.

---

## 7. Project Structure

```
plain_tees/
├── lib/
│   ├── main.dart                     # App entry, theme, deep-link handling, home screen
│   ├── firebase_options.dart         # Generated Firebase configuration
│   ├── config/
│   │   └── payment_config.dart       # Supabase URL + publishable anon key
│   ├── models/
│   │   ├── cart_item.dart            # Cart item model
│   │   ├── order_summary.dart        # Order summary used by the history list
│   │   └── product.dart              # Firestore product model
│   ├── data/
│   │   ├── cart_data.dart            # In-memory cart list
│   │   └── product_data.dart         # Offline fallback catalog
│   ├── screens/
│   │   ├── auth_screen.dart          # Email + password sign-in / sign-up
│   │   ├── product_details_screen.dart
│   │   ├── cart_screen.dart
│   │   ├── checkout_screen.dart      # Order creation + payment launch
│   │   ├── order_history_screen.dart # Synced history (Firestore by user_id)
│   │   ├── order_details_screen.dart
│   │   └── payment_success_screen.dart
│   └── services/
│       ├── auth_service.dart         # Firebase Auth wrapper
│       ├── order_service.dart        # Firestore create/read + owner query
│       ├── order_history_store.dart  # Offline mirror of the synced list
│       ├── product_service.dart      # Reads the products collection
│       ├── payment_service.dart      # Calls the Supabase functions
│       └── last_order_store.dart     # Remembers the last order across restarts
├── supabase/
│   ├── config.toml                   # Function entries (verify_jwt = false)
│   └── functions/
│       ├── create-xendit-payment/index.ts
│       ├── verify-xendit-payment/index.ts
│       ├── xendit-webhook/index.ts
│       └── _shared/
│           ├── cors.ts
│           └── firestore.ts          # Service-account JWT + Firestore REST updates
├── web/
│   └── payment-return.html           # Hosting page that forwards to the deep link
├── firestore.rules                   # Security rules
├── firebase.json                     # Hosting + Firestore rules configuration
├── android/                          # Android manifest, deep link, signing config
└── build/app/outputs/flutter-apk/app-release.apk
```

`functions/` contains the default Firebase CLI scaffold. It is **not** used for payments —
the payment backend is entirely in `supabase/functions/`.

---

## 8. Setup

Requirements: Flutter SDK, an Android device or emulator, and (for deployment) the Firebase
CLI and Supabase CLI.

```powershell
flutter pub get
flutter analyze
flutter test
```

`flutter pub get` installs dependencies such as `firebase_core`, `cloud_firestore`,
`firebase_auth`, `app_links`, `url_launcher`, `http`, and `shared_preferences`.

### Firebase Authentication

Email/password sign-in is configured in `firebase.json` and deployed with the CLI:

```powershell
firebase deploy --only auth --project plaintees-e-commerce
```

That command enables the Email/Password provider. Authorized web domains are
`plaintees-e-commerce.web.app`, `plaintees-e-commerce.firebaseapp.com`, `localhost`, and
`127.0.0.1`. Browsing and the cart work without signing in; placing an order and viewing
Order History require an account.

To sync across devices, create the account once (in the app: person icon → create account)
and sign in with the same email and password on the other platform.

---

## 9. Run the App

```powershell
flutter devices
flutter run
```

To target one device explicitly:

```powershell
flutter run -d <device-id>
```

Runtime notes:

- The app opens on the product catalog. Tap a product, pick a size, and add it to the cart.
- Checkout requires a network connection, because it writes to Firestore and calls the
  payment relay. It also requires sign-in, so the order is linked to the account.
- Order History reads `orders where user_id == uid` and falls back to the on-device mirror
  when offline.
- The Xendit page opens in the device browser. Use Xendit **test mode** credentials while
  developing.

---

## 10. Build APK

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Output:

```
build/app/outputs/flutter-apk/app-release.apk
```

Install it on a connected device with:

```powershell
flutter install --release
```

or copy the APK to the phone and open it (allow installation from unknown sources).

---

## 11. Supabase Deployment

The functions are already deployed. To redeploy them after a code change:

```powershell
npx --yes supabase functions deploy create-xendit-payment xendit-webhook verify-xendit-payment --project-ref <PROJECT_REF> --use-api --yes
```

Required project secrets (set once in the Supabase dashboard or CLI — values are never
committed):

| Secret | Purpose |
|---|---|
| `XENDIT_SECRET_KEY` | Authenticates calls to Xendit |
| `XENDIT_WEBHOOK_TOKEN` | Verifies that webhook calls really come from Xendit |
| `FIREBASE_SERVICE_ACCOUNT_BASE64` | Lets the function update Firestore server-side |

To set a secret without printing it:

```powershell
npx --yes supabase secrets set XENDIT_SECRET_KEY --project-ref <PROJECT_REF>
```

The CLI prompts for the value.

---

## 12. Firebase Rules Deployment

```powershell
firebase deploy --only firestore:rules --project plaintees-e-commerce
```

`firebase.json` maps `firestore.rules` to the Firestore rules slot. Deploying rules is free
and does not require Blaze.

The return page is hosted separately:

```powershell
flutter build web
firebase deploy --only hosting --project plaintees-e-commerce
```

---

## 13. Testing

Verified results:

| Test | Result |
|---|---|
| `flutter analyze` | Clean, no issues |
| `flutter test` | All tests passed |
| `flutter build apk --release` | Built successfully |
| Firestore create (anonymous, valid order) | Allowed |
| Firestore single-document read | Allowed |
| Firestore collection list | Denied (403) |
| Firestore client update | Denied (403) |
| Firestore client delete | Denied (403) |
| Client-created order marked `paid` | Denied (403) |
| Xendit payment creation | Verified — session created, `firestore_updated: true` |
| Xendit payment status verification | Verified — `ACTIVE` / `awaiting_payment` synced to Firestore |

Rules were checked with unauthenticated REST calls using the same payload shape the Flutter
SDK sends, then the full chain was exercised on a throwaway order: create order → create
Xendit session → read order through the app's rules → verify status. The throwaway order was
deleted afterwards.

Manual end-to-end test on a real device:

1. Add a T-shirt to the cart and check out.
2. Pay with a Xendit test card (`4000 0000 0000 0002`, any future expiry, any CVV).
3. Confirm the app returns via the deep link and shows **Paid**.
4. Close and reopen the app — the last order is still reachable.

---

## 14. BMC Finals Requirements

| Requirement | How PlainTees satisfies it |
|---|---|
| E-commerce App | Product catalog, product details, size selection, cart, checkout, order storage, and payment in one Flutter app |
| Firebase | Cloud Firestore for orders, Firebase Hosting for the payment-return page, and deployed Firestore security rules — all on the Spark plan |
| Payment Integration | Xendit payment sessions created server-side, webhook + verification function syncing payment status back to Firestore |
| By Pair | Two-member project; work split between the Flutter app and the server-side payment relay |

| Member | Responsibility |
|---|---|
| _Member 1_ | _Flutter UI, cart, checkout, deep links, Firestore client_ |
| _Member 2_ | _Supabase payment functions, Xendit integration, Firestore rules, deployment_ |

| Requirement | Evidence |
|---|---|
| Export to APK | `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk` |
| Debugging | `flutter analyze`, widget tests, `debugPrint` traces in the checkout and deep-link flow, merged-manifest inspection, live endpoint tests, and Supabase function logs |

---

## Security Reminders

- Never commit the Xendit secret key, webhook token, or Firebase service account JSON.
- Never pass secrets to the app with `--dart-define`; anything compiled into the app is
  readable.
- Keep `.env`, `google-services.json` copies of service accounts, and exported key files out
  of version control.
