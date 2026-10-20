# PocketAlpaca

A private, read-only iPhone view of one Alpaca account. Built on the
[Alpaca Connect](https://app.alpaca.markets/connect) program (OAuth) so it
runs outside the Google Apps Script quota and never touches the trading
engines. It cannot place, change, or cancel an order: every request is a GET.

Four tabs plus a home-screen widget:

| Tab | Shows | Alpaca endpoint |
|---|---|---|
| Overview | equity, today's change, portfolio chart (1D / 1M / 1Y / All), buying power, cash | `GET /v2/account`, `GET /v2/account/portfolio/history` |
| Positions | each position with signed qty, avg entry, current price, unrealized $ and % | `GET /v2/positions` |
| Orders | open orders with distance to stop, then recent closed orders | `GET /v2/orders?status=open`, `?status=closed` |
| Fills | recent executions grouped by day | `GET /v2/account/activities/FILL` |
| Widget | equity, day change, long/short, market open/closed | `GET /v2/account`, `GET /v2/clock` |

Percent P/L comes straight from Alpaca's `unrealized_plpc`. It is never
recomputed from quantity, which is how the retired Alpaca app showed NaN%.

## Layout

```
Shared/                      compiled into BOTH the app and the widget
  AlpacaModels.swift         Codable types (Account, Position, Order, Fill, PortfolioHistory, MarketClock)
  AlpacaAPI.swift            read-only HTTP client + a mock client for previews
  TokenStore.swift           Keychain storage for the OAuth tokens (one per environment)
  Formatting.swift           money / percent / colour helpers
PocketAlpaca/                the app
  PocketAlpacaApp.swift      entry point; creates the AppModel
  AppModel.swift             one observable store: client, data, refresh, errors
  Views/                     RootTabView, Overview, Positions (+ detail sheet), Orders, Fills, Settings
  PocketAlpaca.entitlements  App Group shared with the widget
PocketAlpacaWidget/          home-screen widget (small + medium): equity, day change, long/short, market status
Scripts/alpaca_oauth_once.py one-time sign-in on the Mac; prints the token once
Scripts/make_logo.swift      renders the logo / app icon
```

New `.swift` files dropped under `PocketAlpaca/`, `PocketAlpacaWidget/`, or
`Shared/` join the right target automatically (Xcode 16 synchronized folders).

The app and the widget share one App Group, `group.com.natedenys.PocketAlpaca`.
It doubles as the Keychain access group, so the widget can read the token and
refresh on its own (every 20 minutes while the market is open, hourly otherwise).

## Build from the terminal

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project PocketAlpaca.xcodeproj -scheme PocketAlpaca \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  build CODE_SIGNING_ALLOWED=NO -derivedDataPath DerivedData
```

## Run in the simulator

Open `PocketAlpaca.xcodeproj` in Xcode, pick an iPhone simulator in the
toolbar, press Run (⌘R). With no token saved the app shows sample data and
a banner saying so.

## Sign in (one time, on the Mac)

1. Register the app at https://app.alpaca.markets/connect with redirect URI
   exactly `http://localhost:8765/callback`. Put the Client ID and Client
   Secret in your password manager. Never commit them.
2. Run `python3 Scripts/alpaca_oauth_once.py --env paper` (later `--env live`).
   It opens Alpaca's consent page, catches the redirect, exchanges the code
   for a read-only token, and prints the token once.
3. In the app: Settings → set Paper/Live to match → paste the token → Save.
   The token lives in the phone's Keychain only.
4. Revoke any time at app.alpaca.markets → Connected Apps.

## Running on the real iPhone

The phone is on iOS 26 and this Mac tops out at Xcode 16.4, so a direct
cable install is not possible. The path is Xcode Cloud → TestFlight, which
needs the paid Apple Developer Program.
