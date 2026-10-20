#!/usr/bin/env python3
"""
Push PocketAlpaca's settings into the iOS SIMULATOR app without typing them.

Everything is kept in your Mac's login Keychain and handed to the simulator
app in one go, so a wiped simulator or a reinstalled app is one command away
from being signed in again.

    # one-time: store the Signals endpoint URL and key (key is prompted, hidden)
    python3 Scripts/simulator_provision.py store-signals --url 'https://script.google.com/macros/s/…/exec'

    # one-time per environment: store an Alpaca token (alpaca_oauth_once.py does this for you)
    python3 Scripts/simulator_provision.py store-token --env live

    # whenever the simulator needs it: hand everything to the app
    python3 Scripts/simulator_provision.py apply --env live

    # see what is stored (lengths only)
    python3 Scripts/simulator_provision.py show

How it reaches the app: the script writes one short-lived, owner-only JSON
file into the app's group container inside the simulator, brings the app to
the front (starting it if needed), and waits for the app's receipt. The app
reads the file, stores the values in its Keychain, deletes the file, and
writes the receipt. Nothing goes through environment variables or command
lines, so nothing shows up in `ps`. Simulator builds only; the code that reads
the file does not exist in a device build.
"""
import argparse
import getpass
import json
import os
import secrets
import shutil
import subprocess
import sys
import time

BUNDLE_ID = "com.natedenys.PocketAlpaca"
APP_GROUP = "group.com.natedenys.PocketAlpaca"
DROP_FILE = "pa_provision.json"
RECEIPT_FILE = "pa_provision_receipt.json"
SVC_SIGNALS = "PocketAlpaca-Signals"      # accounts: url, key
SVC_TOKENS = "PocketAlpaca-Tokens"        # accounts: paper, live
RECEIPT_WAIT_SECONDS = 12


def simctl():
    """`xcrun simctl` when available, else the Xcode.app path."""
    if shutil.which("xcrun"):
        return ["xcrun", "simctl"]
    fixed = "/Applications/Xcode.app/Contents/Developer/usr/bin/simctl"
    if os.path.exists(fixed):
        return [fixed]
    sys.exit("simctl not found. Is Xcode installed?")


def run(cmd, **kw):
    kw.setdefault("capture_output", True)
    kw.setdefault("text", True)
    kw.setdefault("timeout", 60)
    try:
        return subprocess.run(cmd, **kw)
    except subprocess.TimeoutExpired:
        sys.exit(f"Timed out running: {' '.join(cmd[:3])} … (is the simulator service responding?)")


# ---------------------------------------------------------------- keychain

def kc_get(service, account):
    r = run(["security", "find-generic-password", "-s", service, "-a", account, "-w"], timeout=30)
    return r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else None


def kc_set(service, account, value):
    # The value is handed to `security` on its stdin in interactive mode, as
    # hex, so it never appears in a command line or in `ps`.
    cmd = f"add-generic-password -U -s {service} -a {account} -X {value.encode().hex()}\n"
    r = run(["security", "-i"], input=cmd, timeout=30)
    if r.returncode != 0 or "error" in (r.stderr or "").lower():
        sys.exit(f"Keychain write failed for {service}/{account}: {(r.stderr or r.stdout).strip()}")


def describe(v):
    return f"{len(v)} characters" if v else "none"


# ---------------------------------------------------------------- commands

def cmd_store_signals(args):
    url = (args.url or input("Signals endpoint URL (…/exec): ")).strip()
    if not url.startswith("https://script.google.com/"):
        sys.exit("That does not look like an Apps Script web app URL (expected https://script.google.com/macros/s/…/exec).")
    key = getpass.getpass("Signals API key (paste, hidden): ").strip()
    if not key:
        sys.exit("No key entered; nothing stored.")
    kc_set(SVC_SIGNALS, "url", url)
    kc_set(SVC_SIGNALS, "key", key)
    print(f"Stored the signals URL and key ({len(key)} characters) in the login Keychain as '{SVC_SIGNALS}'.")


def cmd_store_token(args):
    tok = getpass.getpass(f"Alpaca {args.env} OAuth token (paste, hidden): ").strip()
    if not tok:
        sys.exit("No token entered; nothing stored.")
    kc_set(SVC_TOKENS, args.env, tok)
    print(f"Stored the {args.env} token ({len(tok)} characters) in the login Keychain as '{SVC_TOKENS}'.")


def cmd_show(args):
    print(f"Signals URL : {kc_get(SVC_SIGNALS, 'url') or 'none'}")
    print(f"Signals key : {describe(kc_get(SVC_SIGNALS, 'key'))}")
    print(f"Paper token : {describe(kc_get(SVC_TOKENS, 'paper'))}")
    print(f"Live token  : {describe(kc_get(SVC_TOKENS, 'live'))}")


def booted_devices():
    r = run(simctl() + ["list", "devices", "booted", "-j"])
    if r.returncode != 0:
        sys.exit(f"simctl could not list devices: {r.stderr.strip()}")
    out = []
    for _runtime, devs in json.loads(r.stdout).get("devices", {}).items():
        for d in devs:
            if d.get("state") == "Booted":
                out.append((d["udid"], d["name"]))
    return out


def pick_device(wanted):
    devices = booted_devices()
    if not devices:
        sys.exit("No simulator is booted. Press ⌘R in Xcode (or open Simulator) first.")
    if wanted:
        for udid, name in devices:
            if udid.lower().startswith(wanted.lower()) or name.lower() == wanted.lower():
                return udid, name
        sys.exit(f"No booted simulator matches '{wanted}'. Booted: " + ", ".join(n for _u, n in devices))
    if len(devices) == 1:
        return devices[0]
    names = ", ".join(f"'{n}'" for _u, n in devices)
    sys.exit(f"More than one simulator is booted ({names}). Pass --device with one of those names.")


def group_container(udid):
    r = run(simctl() + ["get_app_container", udid, BUNDLE_ID, "groups"])
    if r.returncode != 0:
        sys.exit("PocketAlpaca is not installed on this simulator (or has no app group yet). "
                 "Press ⌘R in Xcode once, then run apply again.")
    for line in r.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) == 2 and parts[0].strip() == APP_GROUP:
            return parts[1].strip()
    sys.exit(f"The installed app has no '{APP_GROUP}' container. Press ⌘R in Xcode to install the current build, then retry.")


def cmd_apply(args):
    payload = {"nonce": secrets.token_hex(8)}
    if args.env:
        tok = kc_get(SVC_TOKENS, args.env)
        if not tok:
            sys.exit(f"No {args.env} token is stored. Run alpaca_oauth_once.py --env {args.env} (or store-token) first.")
        payload[f"{args.env}Token"] = tok
        payload["environment"] = args.env
    else:
        for env in ("paper", "live"):
            tok = kc_get(SVC_TOKENS, env)
            if tok:
                payload[f"{env}Token"] = tok
    url, key = kc_get(SVC_SIGNALS, "url"), kc_get(SVC_SIGNALS, "key")
    if url and key:
        payload["signalsURL"], payload["signalsKey"] = url, key
    elif url or key:
        print("Note: only one of the signals URL/key is stored, so neither is sent. Run store-signals to fix.")
    if len(payload) == 1:
        sys.exit("Nothing stored yet. Run store-signals and/or alpaca_oauth_once.py first.")

    udid, name = pick_device(args.device)
    container = group_container(udid)
    drop = os.path.join(container, DROP_FILE)
    receipt = os.path.join(container, RECEIPT_FILE)
    try:
        os.remove(receipt)
    except FileNotFoundError:
        pass

    fd = os.open(drop, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(payload, f)

    r = run(simctl() + ["launch", udid, BUNDLE_ID])
    if r.returncode != 0:
        try:
            os.remove(drop)
        except FileNotFoundError:
            pass
        sys.exit(f"Could not bring the app to the front: {(r.stderr or r.stdout).strip()}")

    sent = sorted(k for k in payload if k not in ("nonce", "environment"))
    print(f"Handed {', '.join(sent)}" + (f" (environment → {args.env})" if args.env else "") + f" to PocketAlpaca on {name}. Waiting for the app…")
    deadline = time.time() + RECEIPT_WAIT_SECONDS
    while time.time() < deadline:
        if os.path.exists(receipt):
            try:
                with open(receipt) as f:
                    rc = json.load(f)
            except (OSError, ValueError):
                time.sleep(0.3)
                continue
            if rc.get("nonce") == payload["nonce"]:
                applied = rc.get("applied") or []
                print("App confirmed: " + (", ".join(applied) if applied else "nothing applied") + ".")
                if rc.get("error"):
                    print("App reported: " + rc["error"])
                    sys.exit(1)
                return
        time.sleep(0.3)

    try:
        os.remove(drop)
        removed = True
    except FileNotFoundError:
        removed = False
    sys.exit("The app did not acknowledge within %d s. %s\nPress ⌘R in Xcode once so the current build (with provisioning support) is installed and running, then run apply again."
             % (RECEIPT_WAIT_SECONDS, "The drop file was removed." if removed else "The drop file was consumed but no receipt appeared."))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("store-signals", help="store the Signals endpoint URL and key (key prompted, hidden)")
    s.add_argument("--url", help="the deployment's …/exec URL")
    s.set_defaults(fn=cmd_store_signals)
    t = sub.add_parser("store-token", help="store an Alpaca OAuth token (prompted, hidden)")
    t.add_argument("--env", choices=["paper", "live"], required=True)
    t.set_defaults(fn=cmd_store_token)
    a = sub.add_parser("apply", help="hand everything stored to the running simulator app")
    a.add_argument("--env", choices=["paper", "live"], help="send only this environment's token and switch the app to it")
    a.add_argument("--device", help="simulator name or UDID prefix when more than one is booted")
    a.set_defaults(fn=cmd_apply)
    sh = sub.add_parser("show", help="list what is stored (lengths only)")
    sh.set_defaults(fn=cmd_show)
    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
