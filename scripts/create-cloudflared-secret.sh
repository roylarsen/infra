#!/usr/bin/env bash
# Usage: create-cloudflared-secret.sh <file-containing-tunnel-token>
# Writes a SOPS-encrypted Secret for the cloudflared tunnel token (never prints it).
set -euo pipefail
cd "$(dirname "$0")/.."
out=flux/clusters/k3s/cloudflared/tunnel-token.sops.yaml
input="${1:?token file required}"
umask 077
tmp=$(mktemp flux/clusters/k3s/cloudflared/.tunnel-token.XXXXXX.sops.yaml)
trap 'rm -f "$tmp"' EXIT
token=$(tr -d ' \r\n' < "$input")
test -n "$token"
printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: cloudflared-tunnel\n  namespace: cloudflared\nstringData:\n  token: %s\n' "$token" > "$tmp"
unset token
sops --encrypt --in-place "$tmp"
install -m 600 "$tmp" "$out"
echo "wrote $out"
