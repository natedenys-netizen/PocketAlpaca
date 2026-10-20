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


def kill_stale_instances():
    """An earlier run of this script left waiting for the browser holds the port. End it."""
    r = subprocess.run(["lsof", "-ti", f"tcp:{PORT}", "-sTCP:LISTEN"], capture_output=True, text=True)
    for pid in r.stdout.split():
        if pid == str(os.getpid()):
            continue
        cmd = subprocess.run(["ps", "-o", "command=", "-p", pid], capture_output=True, text=True).stdout
        if "alpaca_oauth_once" in cmd:
            print(f"Ending an earlier run of this script (pid {pid}) that was still waiting for the browser.")
            subprocess.run(["kill", pid])
    time.sleep(1)


def show_client_id():
    """Print the stored Client ID (it is not a secret; it travels in the browser URL)
    and the exact authorize URL, so it can be compared with the Connect dashboard."""
    cid = os.environ.get("ALPACA_CLIENT_ID") or keychain_get("client_id")
    sec = os.environ.get("ALPACA_CLIENT_SECRET") or keychain_get("client_secret")
    if not cid:
        sys.exit("No Client ID stored. Run --store first.")
    print(f"Stored Client ID ({len(cid)} characters):\n\n  {cid}\n")
    print(f"Stored Client Secret: {'present, ' + str(len(sec)) + ' characters' if sec else 'MISSING'} (not shown)")
    q = urllib.parse.urlencode({"response_type": "code", "client_id": cid, "redirect_uri": REDIRECT_URI,
                                "state": "example", "env": "paper"})
    print("\nAuthorize URL the browser will open for --env paper:\n\n  " + AUTHORIZE_URL + "?" + q + "\n")
    print("Compare the Client ID above with the one on your app's page at app.alpaca.markets/connect.")


def keychain_set_token(env, token):
    """Keep the token in the login Keychain so simulator_provision.py can hand it to the simulator."""
    r = subprocess.run(["security", "add-generic-password", "-U", "-s", "PocketAlpaca-Tokens", "-a", env, "-w", token],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print(f"  (could not save the token to the Keychain: {r.stderr.strip()})")


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
    ap.add_argument("--no-save-token", action="store_true", help="do not keep the resulting token in the macOS Keychain for simulator_provision.py")
    ap.add_argument("--show", action="store_true", help="print the stored Client ID and the authorize URL (never the secret), then exit")
    args = ap.parse_args()

    if args.store:
        store_credentials()
        return
    if args.show:
        show_client_id()
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
    except OSError:
        kill_stale_instances()
        try:
            server = http.server.HTTPServer(("127.0.0.1", PORT), Handler)
        except OSError as e:
            sys.exit(f"Port {PORT} is still busy ({e.strerror}). Something other than this script is using it: "
                     f"run  lsof -i tcp:{PORT}  to see what.")
    t = threading.Thread(target=server.serve_forever, daemon=True)
    t.start()

    print(f"\nOpening your browser to authorize the {args.env.upper()} account.")
    print("If it does not open, paste this URL into Safari:\n\n  " + auth_url + "\n")
    webbrowser.open(auth_url)

    print("Waiting for Alpaca to redirect back to localhost:8765 (up to 5 minutes; Ctrl-C to abort) ...")
    deadline = time.time() + 300
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
    if not args.no_save_token:
        keychain_set_token(args.env, access)
        print(f"  Saved to this Mac's Keychain ('PocketAlpaca-Tokens' / {args.env}). To hand it to the simulator app:")
        print(f"    python3 Scripts/simulator_provision.py apply --env {args.env}")
        print("  On a real phone, paste it into PocketAlpaca → Settings → Sign in instead.")
    else:
        print("  Paste it into PocketAlpaca → Settings → Sign in, with the")
        print(f"  Environment switch set to {args.env.capitalize()}. Then clear this terminal.")
    print("  Revoke it any time at app.alpaca.markets → Connected Apps.\n")


if __name__ == "__main__":
    main()
