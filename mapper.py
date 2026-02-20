#!/usr/bin/env python3
"""MapReduce-style mapper for log lines.

Supports:
  - JSON lines (from log_generator.py): extracts "action" key
  - Pipe-separated: timestamp | level | user_id | action | message | response_time | IP
Emits tab-separated: action\t1
Malformed lines are skipped; errors reported to stderr.
"""
import json
import sys

# Action is the 4th field (0-based index 3) for pipe format
ACTION_INDEX = 3


def parse_line(line):
    """
    Parse a single log line. Returns action or None if malformed.
    Tries JSON first (log_generator.py output), then pipe-separated format.
    """
    line = line.rstrip("\r\n")
    if not line:
        return None
    # Try JSON (from log_generator.py)
    try:
        obj = json.loads(line)
        if isinstance(obj, dict):
            action = obj.get("action")
            if action:
                return str(action).strip()
    except (json.JSONDecodeError, TypeError):
        pass
    # Fallback: pipe-separated
    parts = [p.strip() for p in line.split("|")]
    if len(parts) <= ACTION_INDEX:
        return None
    action = parts[ACTION_INDEX].strip()
    return action if action else None


def main():
    for line in sys.stdin:
        try:
            action = parse_line(line)
            if action is None:
                print("mapper: skip malformed line", line[:80], file=sys.stderr)
                continue
            print(action, "1", sep="\t")
        except Exception as e:
            print("mapper error: {}".format(e), file=sys.stderr)
            continue


if __name__ == "__main__":
    main()
