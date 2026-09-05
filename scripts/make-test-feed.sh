#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
#
# make-test-feed.sh — regenerate the signed test feed fixture.
#
# The Ed25519 PRIVATE key is written to keys/, which is gitignored and must
# never be committed. Only the feed and the PUBLIC key are repository content.
#
# This fixture exists so the test suite has a realistic signed feed. It is not
# a threat feed: every domain is under a documentation-reserved name from
# RFC 2606 and resolves to nothing.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

KEY_DIR="keys"
KEY="$KEY_DIR/feed-signing.ed25519.key"
KEY_ID="scamwall-test-key-1"
OUT="testdata/feed.json"
PUB_OUT="testdata/feed_trust_key.pub"

mkdir -p "$KEY_DIR" testdata

if [ ! -f "$KEY" ]; then
  echo "generating a new signing key at $KEY (gitignored)"
  openssl genpkey -algorithm ed25519 -out "$KEY"
  chmod 0600 "$KEY"
fi

# Raw 32-byte public key = last 32 bytes of the DER SubjectPublicKeyInfo.
PUB_B64="$(openssl pkey -in "$KEY" -pubout -outform DER \
  | tail -c 32 | base64 -w0)"

PAYLOAD_FILE="$(mktemp)"
SIG_FILE="$(mktemp)"
trap 'rm -f "$PAYLOAD_FILE" "$SIG_FILE"' EXIT

# The payload is emitted as one compact line so that the bytes signed here are
# unambiguously the bytes embedded below. The signature covers exactly this
# byte sequence; ScamWall verifies against the raw payload as it appears on
# disk rather than against a re-serialisation.
printf '%s' '{"manifest_version":"1.0","feed_id":"scamwall-test-feed","issued_at":"2026-09-01T00:00:00Z","expires_at":"2035-01-01T00:00:00Z","records":[{"domain":"secure-verify-login.example.com","action":"block","confidence":"high","category":"phishing"},{"domain":"account-update-required.example.net","action":"block","confidence":"high","category":"phishing"},{"domain":"Prize-Claim.EXAMPLE.ORG","action":"block","confidence":"high","category":"advance-fee-fraud"},{"domain":"münchen-sparkasse.example.net","action":"block","confidence":"high","category":"phishing"},{"domain":"refund-portal.example.com.","action":"block","confidence":"high","category":"refund-scam"},{"domain":"maybe-suspicious.example.net","action":"block","confidence":"medium","category":"unverified"},{"domain":"known-good.example.org","action":"allow","confidence":"high","category":"allowlist"},{"domain":"expired-campaign.example.com","action":"block","confidence":"high","category":"phishing","expires_at":"2026-01-01T00:00:00Z"}]}' > "$PAYLOAD_FILE"

openssl pkeyutl -sign -inkey "$KEY" -rawin -in "$PAYLOAD_FILE" -out "$SIG_FILE"
SIG_B64="$(base64 -w0 < "$SIG_FILE")"

{
  printf '{\n'
  printf '  "schema_version": 1,\n'
  printf '  "signature": {\n'
  printf '    "algorithm": "ed25519",\n'
  printf '    "key_id": "%s",\n' "$KEY_ID"
  printf '    "value": "%s"\n' "$SIG_B64"
  printf '  },\n'
  printf '  "payload": '
  cat "$PAYLOAD_FILE"
  printf '\n}\n'
} > "$OUT"

printf '%s\n' "$PUB_B64" > "$PUB_OUT"

echo "wrote $OUT"
echo "wrote $PUB_OUT"
echo
echo "trust key id:     $KEY_ID"
echo "trust public key: $PUB_B64"
