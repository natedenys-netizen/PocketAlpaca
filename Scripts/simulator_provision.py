#!/usr/bin/env python3
"""
Push PocketAlpaca's settings into the iOS SIMULATOR app without typing them.

Everything is kept in your Mac's login Keychain and sent to the running
simulator app in one go, so a wiped simulator or a reinstalled app is one
command away from being signed in again.

    # one-time: store the Signals endpoint URL and key (key is prompted, hidden)
    python3 Scripts/simulator_provision.py store-signals --url 'https://script.google.com/macros/s/…/exec'

    # one-time per environment: store an Alpaca token (or let alpaca_oauth_once.py store it for you)
    python3 Scripts/simulator_provision.py store-token --env live

    # every time the simulator needs it: push everything into the app
    python3 Scripts/simulator_provision.py apply --env live

    # see what is stored (values masked)
    python3 Scripts/simulator_provision.py show

How it reaches the app: the script terminates and relaunches the app in the
booted simulator with an environment variable (SIMCTL_CHILD_PA_PROVISION),
which the app reads once at startup — simulator builds only; the code does not
exist in a device build. Nothing is written to disk outside the Keychain.
"""
import argparse
import base64
import getpass
import json
import os
import subprocess
import sys

BUNDLE_ID = "com.natedenys.PocketAlpaca"
SIMCTL = "/Applications/Xcode.app/Contents/Developer/usr/bin/simctl"
SVC_SIGNALS = "PocketAlpaca-Signals"      # accounts: url, key
SVC_TOKENS = "PocketAlpaca-Tokens"        # accounts: paper, live


# ---------------------------------------------------------------- keychain

def kc_get(service, account):
    r = subprocess.run(["security", "find-generic-password", "-s", service, "-a", account, "-w"],
                       capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else None


def kc_set(service, account, value):
    # NOTE: the value travels in this command's argv, which is visible in `ps`
    # on this Mac for the few milliseconds the command runs. Acceptable on a
    # personal machine; the alternative (security's own interactive prompt)
    # makes you paste every secret twice.
    r = subprocess.run(["security", "add-generic-password", "-U", "-s", service, "-a", account, "-w", value],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"Keychain write failed for {service}/{account}: {r.stderr.strip()}")


def masked(v):
    if not v:
        return "none"
    return f"{v[:4]}…{v[-4:]} ({len(v)} chars)" if len(v) > 12 else "set"


# ---------------------------------------------------------------- commands

def cmd_store_signals(args):
    url = args.url or input("Signals endpoint URL (…/exec): ").strip()
    if not url.startswith("https://script.google.com/"):
        sys.exit("That does not look like an Apps Script web app URL (expected https://script.google.com/macros/s/…/exec).")
    key = getpass.getpass("Signals API key (paste, hidden): ").strip()
    if not key:
        sys.exit("No key entered; nothing stored.")
    kc_set(SVC_SIGNALS, "url", url)
    kc_set(SVC_SIGNALS, "key", key)
    print(f"Stored signals URL and key ({len(key)} characters) in the login Keychain as '{SVC_SIGNALS}'.")


def cmd_store_token(args):
    tok = getpass.getpass(f"Alpaca {args.env} OAuth token (paste, hidden): ").strip()
    if not tok:
        sys.exit("No token entered; nothing stored.")
    kc_set(SVC_TOKENS, args.env, tok)
    print(f"Stored the {args.env} token ({len(tok)} characters) in the login Keychain as '{SVC_TOKENS}'.")


def cmd_show(args):
    print(f"Signals URL : {kc_get(SVC_SIGNALS, 'url') or 'none'}")
    print(f"Signals key : {masked(kc_get(SVC_SIGNALS, 'key'))}")
    print(f"Paper token : {masked(kc_get(SVC_TOKENS, 'paper'))}")
    print(f"Live token  : {masked(kc_get(SVC_TOKENS, 'live'))}")


def booted_devices():
    r = subprocess.run([SIMCTL, "list", "devices", "booted", "-j"], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"simctl could not list devices: {r.stderr.strip()}")
    out = []
    for runtime, devs in json.loads(r.stdout).get("devices", {}).items():
        for d in devs:
            if d.get("state") == "Booted":
                out.append((d["udid"], d["name"]))
    return out


def cmd_apply(args):
    payload = {}
    for env in ("paper", "live"):
        tok = kc_get(SVC_TOKENS, env)
        if tok:
            payload[f"{env}Token"] = tok
    if args.env:
        payload["environment"] = args.env
    url, key = kc_get(SVC_SIGNALS, "url"), kc_get(SVC_SIGNALS, "key")
    if url:
        payload["signalsURL"] = url
    if key:
        payload["signalsKey"] = key
    if not payload:
        sys.exit("Nothing stored yet. Run 'store-signals' and/or 'store-token' first, or alpaca_oauth_once.py.")

    devices = booted_devices()
    if args.device:
        target = args.device
    elif len(devices) == 1:
        target = devices[0][0]
    elif not devices:
        sys.exit("No simulator is booted. Press ⌘R in Xcode (or open Simulator) first.")
    else:
        names = ", ".join(f"{n} ({u[:8]}…)" for u, n in devices)
        sys.exit(f"More than one simulator is booted ({names}). Pass --device <udid>.")

    blob = base64.b64encode(json.dumps(payload).encode()).decode()
    subprocess.run([SIMCTL, "terminate", target, BUNDLE_ID], capture_output=True, text=True)  # ok if not running
    env = dict(os.environ, SIMCTL_CHILD_PA_PROVISION=blob)
    r = subprocess.run([SIMCTL, "launch", target, BUNDLE_ID], capture_output=True, text=True, env=env)
    if r.returncode != 0:
        sys.exit(f"Launch failed: {r.stderr.strip() or r.stdout.strip()}\n"
                 f"Is PocketAlpaca installed on this simulator? Press ⌘R in Xcode once, then run apply again.")
    sent = sorted(k for k in payload if k != "environment")
    print(f"Launched PocketAlpaca on {target[:8]}… and handed it: {', '.join(sent)}"
          + (f" (environment set to {args.env})" if args.env else "") + ".")
    print("The app shows the result in Settings. If Xcode was debugging the app, it reports it as finished; that is expected.")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("store-signals", help="store the Signals endpoint URL and key (key prompted, hidden)")
    s.add_argument("--url", help="the deployment's …/exec URL")
    s.set_defaults(fn=cmd_store_signals)
    t = sub.add_parser("store-token", help="store an Alpaca OAuth token (prompted, hidden)")
    t.add_argument("--env", choices=["paper", "live"], required=True)
    t.set_defaults(fn=cmd_store_token)
    a = sub.add_parser("apply", help="relaunch the simulator app with everything stored")
    a.add_argument("--env", choices=["paper", "live"], help="also switch the app to this environment")
    a.add_argument("--device", help="simulator UDID when more than one is booted")
    a.set_defaults(fn=cmd_apply)
    sh = sub.add_parser("show", help="list what is stored (masked)")
    sh.set_defaults(fn=cmd_show)
    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
