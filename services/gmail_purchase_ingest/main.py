#!/usr/bin/env python3
"""Gmail → DharmaCore purchase draft ingest service."""

from __future__ import annotations

import argparse
import logging
import os
import sys

from dotenv import load_dotenv

from gmail_client import GmailClient
from pb_client import PocketBaseClient
from poller import run_loop, run_once


def main(argv: list[str] | None = None) -> int:
    load_dotenv()
    parser = argparse.ArgumentParser(description="DharmaCore Gmail purchase ingest")
    parser.add_argument(
        "--once",
        action="store_true",
        help="Run a single poll cycle and exit",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Run even if email_ingest_enabled is false",
    )
    parser.add_argument(
        "--oauth",
        action="store_true",
        help="Run Gmail OAuth flow and save token, then exit",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
    )
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    if args.oauth:
        gmail = GmailClient()
        gmail.connect()
        print(f"Gmail token saved to {gmail.token_path}")
        return 0

    pb = PocketBaseClient()
    try:
        pb.ensure_auth()
    except Exception as e:
        logging.error("PocketBase auth failed: %s", e)
        return 1

    gmail = GmailClient()
    try:
        gmail.connect()
    except Exception as e:
        logging.error("Gmail connect failed: %s", e)
        return 1

    if args.once:
        result = run_once(pb, gmail, force=args.force)
        print(result)
        return 0 if result.get("ok") or result.get("skipped") else 1

    run_loop(pb, gmail)
    return 0


if __name__ == "__main__":
    sys.exit(main())
