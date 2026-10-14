#!/usr/bin/env python3
"""
One-time Alpaca Connect sign-in for PocketAlpaca. Run this ON THE MAC.

It opens the Alpaca authorization page in your browser, receives the
authorization code on http://localhost:8765/callback, exchanges it for a
read-only access token using your Connect app's client secret, and prints
the token ONCE so you can paste it into PocketAlpaca → Settings on the phone.

Nothing is written to disk. The client secret is read from the environment
or typed at a hidden prompt; it never leaves this machine.

    python3 Scripts/alpaca_oauth_once.py --env paper      # first, for development
    python3 Scripts/alpaca_oauth_once.py --env live       # later, for the real account

Register the app first at https://app.alpaca.markets/connect with redirect
URI exactly:  http://localhost:8765/callback
"""
import argparse
import getpass
import http.server
import json
import os
import secrets
import sys
import threading
import urllib.parse
import urllib.request
import webbrowser

AUTHORIZE_URL = "https://app.alpaca.markets/oauth/authorize"
TOKEN_URL = "https://api.alpaca.markets/oauth/token"
REDIRECT_URI = "http://localhost:8765/callback"
PORT = 8765

received = {}


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
    ap.add_argument("--env", choices=["paper", "live"], required=True, help="which account to authorize")
    ap.add_argument("--scope", default="", help="OAuth scopes; empty = read-only (default). 'data' adds Market Data API.")
    args = ap.parse_args()

    client_id = os.environ.get("ALPACA_CLIENT_ID") or input("Connect app Client ID: ").strip()
    client_secret = os.environ.get("ALPACA_CLIENT_SECRET") or getpass.getpass("Connect app Client Secret (hidden): ").strip()
    if not client_id or not client_secret:
        sys.exit("Client ID and Client Secret are required.")

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

    server = http.server.HTTPServer(("127.0.0.1", PORT), Handler)
    t = threading.Thread(target=server.serve_forever, daemon=True)
    t.start()

    print(f"\nOpening your browser to authorize the {args.env.upper()} account.")
    print("If it does not open, paste this URL into Safari:\n\n  " + auth_url + "\n")
    webbrowser.open(auth_url)

    print("Waiting for Alpaca to redirect back to localhost:8765 ...")
    while "code" not in received:
        threading.Event().wait(0.2)
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
