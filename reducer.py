#!/usr/bin/env python3
"""MapReduce-style reducer for action counts.

Reads tab-separated key-value pairs from stdin: action\tcount
Aggregates counts per action, outputs lines sorted by total_count descending.
Format: action\ttotal_count
"""
import sys
from collections import defaultdict


def main():
    # Aggregate counts per action (defaultdict avoids key checks)
    counts = defaultdict(int)

    for line in sys.stdin:
        line = line.rstrip("\r\n")
        if not line:
            continue
        try:
            parts = line.split("\t", 1)
            if len(parts) != 2:
                print("reducer: skip malformed line", repr(line[:80]), file=sys.stderr)
                continue
            action, value = parts[0].strip(), parts[1].strip()
            if not action:
                continue
            count = int(value)
            counts[action] += count
        except ValueError:
            print("reducer: skip non-integer count", repr(line[:80]), file=sys.stderr)
            continue
        except Exception as e:
            print("reducer error: {}".format(e), file=sys.stderr)
            continue

    # Sort by count descending, then by action ascending for stable ordering
    for action, total in sorted(counts.items(), key=lambda x: (-x[1], x[0])):
        print(action, total, sep="\t")


if __name__ == "__main__":
    main()
