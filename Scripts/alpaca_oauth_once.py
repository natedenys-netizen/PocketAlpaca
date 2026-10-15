#!/usr/bin/env python3
"""
One-time Alpaca Connect sign-in for PocketAlpaca. Run this ON THE MAC.

It opens the Alpaca authorization page in your browser, receives the
authorization code on http://localhost:8765/callback, exchanges it for a
read-only access token using your Connect app's client secret, and prints
the token ONCE so you can paste it into PocketAlpaca → Settings on the phone.

The Client ID and Client Secret come from, in order: the environment
(ALPACA_CLIENT_ID / ALPACA_CLIENT_SECRET), the macOS login Keychain, or a
prompt. Store them in the Keychain ONCE with --store so you never type them
again:

    python3 Scripts/alpaca_oauth_once.py --store          # paste ID, paste Secret
    python3 Scripts/alpaca_oauth_once.py --env paper      # first, for development
    python3 Scripts/alpaca_oauth_once.py --env live       # later, for the real account

The token itself is never written anywhere; it is printed once.

Register the app first at https://app.alpaca.markets/connect with redirect
URI exactly:  http://localhost:8765/callback
"""
import argparse
import getpass
import http.server
import json
import os
import secrets
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
import webbrowser

AUTHORIZE_URL = "https://app.alpaca.markets/oauth/authorize"
TOKEN_URL = "https://api.alpaca.markets/oauth/token"
REDIRECT_URI = "http://localhost:8765/callback"
PORT = 8765

received = {}

KEYCHAIN_SERVICE = "PocketAlpaca-Connect"


def keychain_get(account):
    """Read one value from the macOS login Keychain, or None if absent."""
    r = subprocess.run(["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", account, "-w"],
                       capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else None


def keychain_set(account, value):
    """Create or replace one value in the macOS login Keychain."""
    r = subprocess.run(["security", "add-generic-password", "-U", "-s", KEYCHAIN_SERVICE, "-a", account, "-w", value],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"Keychain write failed for {account}: {r.stderr.strip()}")


def store_credentials():
    print("Paste each value from your password manager and press Enter. Nothing is echoed.")
    cid = getpass.getpass("Connect app Client ID: ").strip()
    sec = getpass.getpass("Connect app Client Secret: ").strip()
    if not cid or not sec:
        sys.exit("Both values are required; nothing stored.")
    keychain_set("client_id", cid)
    keychain_set("client_secret", sec)
    print(f"Stored in the login Keychain as service '{KEYCHAIN_SERVICE}' (Client ID is {len(cid)} characters, Secret {len(sec)}).")
    print("You can see or delete them in Keychain Access by searching PocketAlpaca.")


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        if url.path != "/callback":
            self.send_response(404); self.end_headers(); return
        q = urllib.parse.parse_qs(url.query)
        received["code"] = q.get("code", [None])[0]
        received["state"] = q.get("state", [None])[0]
        received["error"] = q.get("error", [None])[0]
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        msg = "Signed in. You can close this tab and return to the terminal." if received["code"] else f"Authorization failed: {received['error']}"
        self.wfile.write(f"<html><body style='font-family:-apple-system;padding:2em'><h2>PocketAlpaca</h2><p>{msg}</p></body></html>".encode())

    def log_message(self, *args):  # quiet
        pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--env", choices=["paper", "live"], help="which account to authorize")
    ap.add_argument("--scope", default="", help="OAuth scopes; empty = read-only (default). 'data' adds Market Data API.")
    ap.add_argument("--store", action="store_true", help="save the Client ID and Secret in the macOS Keychain, then exit")
    args = ap.parse_args()

    if args.store:
        store_credentials()
        return
    if not args.env:
        ap.error("--env paper|live is required (or use --store first)")

    client_id = os.environ.get("ALPACA_CLIENT_ID") or keychain_get("client_id")
    client_secret = os.environ.get("ALPACA_CLIENT_SECRET") or keychain_get("client_secret")
    src = "environment" if os.environ.get("ALPACA_CLIENT_ID") else ("Keychain" if client_id else "prompt")
    if not client_id:
        client_id = input("Connect app Client ID: ").strip()
    if not client_secret:
        client_secret = getpass.getpass("Connect app Client Secret (hidden): ").strip()
    if not client_id or not client_secret:
        sys.exit("Client ID and Client Secret are required. Run with --store to save them once.")
    print(f"Using Client ID from {src}: {client_id[:4]}…{client_id[-4:]} ({len(client_id)} characters)")

    state = secrets.token_urlsafe(24)
    params = {
        "response_type": "code",
        "client_id": client_id,
        "redirect_uri": REDIRECT_URI,
        "state": state,
        "env": args.env,
    }
    if args.scope:
        params["scope"] = args.scope
    auth_url = AUTHORIZE_URL + "?" + urllib.parse.urlencode(params)

    http.server.HTTPServer.allow_reuse_address = True
    try:
        server = http.server.HTTPServer(("127.0.0.1", PORT), Handler)
    except OSError as e:
        sys.exit(f"Port {PORT} is busy ({e.strerror}). An earlier run of this script is probably still waiting "
                 f"in another Terminal tab: press Ctrl-C there, or run  lsof -ti tcp:{PORT} | xargs kill  and try again.")
    t = threading.Thread(target=server.serve_forever, daemon=True)
    t.start()

    print(f"\nOpening your browser to authorize the {args.env.upper()} account.")
    print("If it does not open, paste this URL into Safari:\n\n  " + auth_url + "\n")
    webbrowser.open(auth_url)

    print("Waiting for Alpaca to redirect back to localhost:8765 (up to 10 minutes; Ctrl-C to abort) ...")
    deadline = time.time() + 600
    try:
        while "code" not in received:
            if time.time() > deadline:
                server.shutdown()
                sys.exit("Timed out waiting for the browser. Run the script again.")
            time.sleep(0.2)
    except KeyboardInterrupt:
        server.shutdown()
        sys.exit("\nAborted.")
    server.shutdown()

    if received.get("error") or not received.get("code"):
        sys.exit(f"Authorization failed: {received.get('error')}")
    if received.get("state") != state:
        sys.exit("State mismatch — possible request forgery. Run again.")

    body = urllib.parse.urlencode({
        "grant_type": "authorization_code",
        "code": received["code"],
        "client_id": client_id,
        "client_secret": client_secret,
        "redirect_uri": REDIRECT_URI,
    }).encode()
    req = urllib.request.Request(TOKEN_URL, data=body, method="POST",
                                 headers={"Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            tok = json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        sys.exit(f"Token exchange failed: HTTP {e.code} {e.read().decode()[:300]}")

    access = tok.get("access_token")
    if not access:
        sys.exit(f"No access_token in response: {tok}")

    print("\n" + "=" * 64)
    print(f"  {args.env.upper()} account token (scope: '{tok.get('scope', '') or 'read-only'}')")
    print("=" * 64)
    print("\n  " + access + "\n")
    print("  Paste it into PocketAlpaca → Settings → Sign in, with the")
    print(f"  Environment switch set to {args.env.capitalize()}. Then clear this terminal.")
    print("  Revoke it any time at app.alpaca.markets → Connected Apps.\n")


if __name__ == "__main__":
    main()
