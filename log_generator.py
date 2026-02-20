#!/usr/bin/env python3
"""
log_generator.py — Generate realistic application logs to stdout.

Fields: timestamp, level (INFO 80% / WARNING 15% / ERROR 5%), user_id, action,
        message, response_time (ms), IP. Uses Faker for realistic data.
Continuous stream at --rate logs/second for --duration seconds (0 = forever).
"""

import argparse
import json
import random
import signal
import sys
import time
from datetime import datetime, timezone

from faker import Faker

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
LEVELS = ("INFO", "WARNING", "ERROR")
LEVEL_WEIGHTS = (80, 15, 5)  # INFO 80%, WARNING 15%, ERROR 5%

ACTIONS = (
    "LOGIN",
    "LOGOUT",
    "PURCHASE",
    "VIEW",
    "SEARCH",
    "CLICK",
    "ERROR",
)

# Action-specific message templates (optional placeholders for faker/sentence)
MESSAGE_TEMPLATES = {
    "LOGIN": (
        "User authenticated successfully",
        "Session started",
        "Login attempt from device",
    ),
    "LOGOUT": (
        "User signed out",
        "Session terminated",
        "Logout requested",
    ),
    "PURCHASE": (
        "Order completed",
        "Payment processed",
        "Checkout successful",
    ),
    "VIEW": (
        "Product page viewed",
        "Page load completed",
        "Content displayed",
    ),
    "SEARCH": (
        "Search query executed",
        "Results returned",
        "Search performed",
    ),
    "CLICK": (
        "Button clicked",
        "Link followed",
        "Element interaction",
    ),
    "ERROR": (
        "Operation failed",
        "Request timeout",
        "Unexpected error",
    ),
}

DEFAULT_RATE = 5.0  # logs per second
DEFAULT_DURATION = 0  # 0 = run until interrupted
USER_POOL_SIZE = 50  # reuse these user_ids for realistic repetition


def parse_args():
    parser = argparse.ArgumentParser(
        description="Generate realistic application logs to stdout (JSON lines)."
    )
    parser.add_argument(
        "--rate",
        type=float,
        default=DEFAULT_RATE,
        metavar="N",
        help=f"Logs per second (default: {DEFAULT_RATE})",
    )
    parser.add_argument(
        "--duration",
        type=float,
        default=DEFAULT_DURATION,
        metavar="SECONDS",
        help="Run for SECONDS; 0 = run until Ctrl+C (default: 0)",
    )
    return parser.parse_args()


def _make_user_pool(faker: Faker, size: int) -> list:
    """Stable pool of user_ids (mix of names and UUIDs) for realistic repetition."""
    pool = [faker.user_name() for _ in range(size // 2)]
    pool += [str(faker.uuid4()) for _ in range(size - len(pool))]
    return pool


def generate_log_line(faker: Faker, user_pool: list) -> dict:
    level = random.choices(LEVELS, weights=LEVEL_WEIGHTS)[0]
    action = random.choice(ACTIONS)

    # Slight bias: ERROR level often pairs with ERROR action
    if level == "ERROR" and random.random() < 0.6:
        action = "ERROR"

    templates = MESSAGE_TEMPLATES[action]
    message = random.choice(templates)
    if random.random() < 0.4:
        message = faker.sentence(nb_words=4, variable_nb_words=True).rstrip(".")

    # response_time in ms: ERROR often slower; cap at 30s
    if level == "ERROR":
        response_time_ms = random.randint(2000, 30000)
    elif level == "WARNING":
        response_time_ms = random.randint(500, 5000)
    else:
        response_time_ms = random.randint(10, 2000)

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "level": level,
        "user_id": random.choice(user_pool),
        "action": action,
        "message": message,
        "response_time": response_time_ms,
        "ip": faker.ipv4_public(),
    }


def main():
    args = parse_args()
    if args.rate <= 0:
        print("error: --rate must be positive", file=sys.stderr)
        sys.exit(1)
    if args.duration < 0:
        print("error: --duration must be non-negative", file=sys.stderr)
        sys.exit(1)

    faker = Faker()
    user_pool = _make_user_pool(faker, USER_POOL_SIZE)
    interval = 1.0 / args.rate
    deadline = time.monotonic() + args.duration if args.duration > 0 else None

    def stop(signum, frame):
        sys.exit(0)

    signal.signal(signal.SIGINT, stop)
    if hasattr(signal, "SIGTERM"):
        signal.signal(signal.SIGTERM, stop)

    try:
        while True:
            log_entry = generate_log_line(faker, user_pool)
            print(json.dumps(log_entry), flush=True)
            if deadline is not None and time.monotonic() >= deadline:
                break
            time.sleep(interval)
    except (KeyboardInterrupt, SystemExit):
        pass


if __name__ == "__main__":
    main()
