#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f ".apple-jwt.env" ]]; then
  echo "Missing .apple-jwt.env in repo root."
  echo "Create it first (see .apple-jwt.env template)."
  exit 1
fi

source .apple-jwt.env

: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
: "${APPLE_KEY_ID:?APPLE_KEY_ID is required}"
: "${APPLE_CLIENT_ID:?APPLE_CLIENT_ID is required}"
: "${APPLE_P8_PATH:?APPLE_P8_PATH is required}"

if [[ ! -f "${APPLE_P8_PATH}" ]]; then
  echo "Private key not found at APPLE_P8_PATH=${APPLE_P8_PATH}"
  exit 1
fi

python3 - <<'PY'
import os
import time
import sys

try:
    import jwt
except ImportError:
    print("Missing dependency: pyjwt")
    print("Install with: python -m pip install pyjwt cryptography")
    sys.exit(1)

with open(os.environ["APPLE_P8_PATH"], "r", encoding="utf-8") as f:
    private_key = f.read()

now = int(time.time())
exp = now + 60 * 60 * 24 * 180  # Apple max: 180 days

token = jwt.encode(
    {
        "iss": os.environ["APPLE_TEAM_ID"],
        "iat": now,
        "exp": exp,
        "aud": "https://appleid.apple.com",
        "sub": os.environ["APPLE_CLIENT_ID"],
    },
    private_key,
    algorithm="ES256",
    headers={"kid": os.environ["APPLE_KEY_ID"]},
)

print(token)
PY
