# PocketAlpaca Privacy Policy

Last updated: October 14, 2026

PocketAlpaca is a personal, read-only iPhone app that shows the owner's own
Alpaca brokerage account: equity, portfolio history, open positions, and
orders. It is built on the Alpaca Connect (OAuth) program.

## What the app collects

Nothing. PocketAlpaca has no server, no analytics, no crash reporting, no
advertising, and no third-party SDKs. The app does not collect, store,
or transmit personal information to the developer or to anyone else.

## What the app stores on the device

- The Alpaca OAuth access token you authorize, stored in the iOS Keychain
  on your phone only.
- Your choice of paper or live environment.

Both are removed when you tap Sign out in Settings or delete the app.

## Where your data goes

The app talks only to Alpaca's own API servers (`api.alpaca.markets` and
`paper-api.alpaca.markets`) over HTTPS, using the token you authorized.
Account data is displayed on screen and is not retained beyond the app's
in-memory cache for the current session.

## Permissions

The OAuth token is requested with read-only scope. The app cannot place,
modify, or cancel orders, move money, or change account settings.

## Revoking access

You can revoke the app's access at any time at
https://app.alpaca.markets under Connected Apps. Revocation takes effect
on the next request.

## Changes and contact

This policy may be updated when the app changes. Questions: open an issue
on the project repository or contact the developer, Nathanael Denys, at
natedenys@gmail.com.
