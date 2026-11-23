#!/usr/bin/env python3
"""Patch PiKVM's installed xh_hk4401 ugpio driver from 4 to 8 channels.

The BliSwitch v2 vendor guide requires three logical changes:
  1. channel validator max 3 -> 7
  2. receive regex ports 1-4 -> 1-8
  3. transmit assertion channel <= 3 -> <= 7

This script patches the installed file supplied as argv[1], creates no backup
itself (the shell installer handles backup), and refuses unexpected layouts.
"""
from pathlib import Path
import re
import sys

if len(sys.argv) != 2:
    raise SystemExit(f"usage: {sys.argv[0]} /path/to/xh_hk4401.py")

path = Path(sys.argv[1])
text = path.read_text()
original = text

# Support both modern valid_number.mk(...) and older functools.partial(...).
validator_patterns = [
    (r'(valid_number\.mk\(min=0,\s*max=)3(,\s*name="XH-HK4401 channel"\))', r'\g<1>7\g<2>'),
    (r'(functools\.partial\(valid_number,\s*min=0,\s*max=)3(,\s*name="XH-HK4401 channel"\))', r'\g<1>7\g<2>'),
]
validator_changed = 0
for pattern, replacement in validator_patterns:
    text, count = re.subn(pattern, replacement, text, count=1)
    validator_changed += count
    if count:
        break

# Replace both protocol-1 and protocol-2 ranges when present on the same line.
regex_count = text.count('[1-4]')
if regex_count:
    text = text.replace('[1-4]', '[1-8]')

text, assert_count = re.subn(r'assert 0 <= channel <= 3\b', 'assert 0 <= channel <= 7', text, count=1)

# Idempotency: if already fully patched, report success without rewriting.
already = (
    ('max=7' in text or 'max = 7' in text)
    and '[1-8]' in text
    and 'assert 0 <= channel <= 7' in text
)

if not already:
    raise SystemExit(
        "Refusing to write: driver layout did not match the expected PiKVM xh_hk4401 patterns.\n"
        f"validator changes={validator_changed}, regex replacements={regex_count}, assert changes={assert_count}"
    )

if text == original:
    print(f"Already patched: {path}")
else:
    path.write_text(text)
    print(f"Patched for 8 ports: {path}")
    print(f"Changes: validator={validator_changed}, receive-ranges={regex_count}, send-assert={assert_count}")
