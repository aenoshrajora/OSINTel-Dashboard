#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
------------------------------------------------------------------------------
    CTFR - Updated for OSINTel Dashboard integration
    Original by Sheila A. Berta (UnaPibaGeek)
------------------------------------------------------------------------------
"""

import re
import sys
import json
import argparse
import requests

## # CONTEXT VARIABLES # ##
version = 1.3


## # MAIN FUNCTIONS # ##

def parse_args():
    parser = argparse.ArgumentParser(
        description="Query crt.sh certificate transparency logs for subdomains."
    )
    parser.add_argument(
        "-d", "--domain",
        type=str,
        required=True,
        help="Target domain (e.g. example.com)."
    )
    parser.add_argument(
        "-o", "--output",
        type=str,
        default=None,
        help="Output file path to save results."
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output results as JSON."
    )
    parser.add_argument(
        "--no-banner",
        action="store_true",
        help="Suppress banner (useful when called from dashboard)."
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=15,
        help="HTTP request timeout in seconds (default: 15)."
    )
    return parser.parse_args()


def banner():
    b = """
          ____ _____ _____ ____  
         / ___|_   _|  ___|  _ \\ 
        | |     | | | |_  | |_) |
        | |___  | | |  _| |  _ < 
         \\____| |_| |_|   |_| \\_\\

     Version {v} - Hey don't miss AXFR!
    Made by Sheila A. Berta (UnaPibaGeek)
    """.format(v=version)
    print(b)


def clear_url(target):
    """Strip protocol, www prefix, and path — return bare domain."""
    target = target.strip().lower()
    # Remove protocol if present
    target = re.sub(r'^https?://', '', target)
    # Remove www. prefix
    target = re.sub(r'^www\.', '', target)
    # Remove path/query/fragment
    return target.split('/')[0].split('?')[0].split('#')[0].strip()


def fetch_subdomains(domain, timeout=15):
    """
    Query crt.sh for certificate transparency records.
    Returns a sorted, deduplicated list of subdomains on success,
    or raises an exception on failure.
    """
    url = "https://crt.sh/?q=%.{d}&output=json".format(d=domain)
    headers = {"User-Agent": "ctfr/1.3 (subdomain-enum)"}

    try:
        resp = requests.get(url, headers=headers, timeout=timeout)
    except requests.exceptions.Timeout:
        raise RuntimeError(
            "Request timed out after {}s. crt.sh may be slow — try again.".format(timeout)
        )
    except requests.exceptions.ConnectionError as exc:
        raise RuntimeError("Connection error: {}".format(exc))

    if resp.status_code != 200:
        raise RuntimeError(
            "crt.sh returned HTTP {} — information not available.".format(resp.status_code)
        )

    try:
        data = resp.json()
    except json.JSONDecodeError:
        raise RuntimeError("crt.sh returned non-JSON response. Service may be degraded.")

    if not data:
        return []

    subdomains = set()
    for entry in data:
        name = entry.get("name_value", "")
        # name_value can contain newline-separated multiple names
        for sub in name.splitlines():
            sub = sub.strip().lower()
            # Filter out wildcard entries and empty strings
            if sub and not sub.startswith("*"):
                subdomains.add(sub)

    return sorted(subdomains)


def save_subdomains(subdomains, output_file):
    """Write subdomains to output_file, one per line."""
    try:
        with open(output_file, "w", encoding="utf-8") as f:
            f.write("\n".join(subdomains) + "\n")
        print("\n[+] Results saved to: {}".format(output_file))
    except IOError as exc:
        print("[X] Could not write output file: {}".format(exc), file=sys.stderr)


def main():
    args = parse_args()

    if not args.no_banner:
        banner()

    domain = clear_url(args.domain)

    if not domain:
        print("[X] Invalid domain provided.", file=sys.stderr)
        sys.exit(1)

    print("\n[!] ---- TARGET: {} ---- [!]\n".format(domain))
    print("[*] Querying crt.sh certificate transparency logs...")

    try:
        subdomains = fetch_subdomains(domain, timeout=args.timeout)
    except RuntimeError as exc:
        print("[X] {}".format(exc), file=sys.stderr)
        sys.exit(1)

    if not subdomains:
        print("[!] No subdomains found for: {}".format(domain))
        sys.exit(0)

    print("[+] Found {} unique subdomain(s):\n".format(len(subdomains)))

    if args.json:
        output_data = {"domain": domain, "subdomains": subdomains, "count": len(subdomains)}
        print(json.dumps(output_data, indent=2))
    else:
        for sub in subdomains:
            print("[-]  {}".format(sub))

    if args.output:
        save_subdomains(subdomains, args.output)

    print("\n\n[!] Done. Have a nice day! ;).")


if __name__ == "__main__":
    main()