#!/usr/bin/env bash
# Pin sources.json to a published release: ./update.sh [vX.Y.Z]
# With no argument, uses the latest release of this repo.
set -euo pipefail

repo="tragedy-mc/misfortune-releases"
cd "$(dirname "$0")"

tag="${1:-$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" | jq -r .tag_name)}"
version="${tag#v}"

json=$(jq -n --arg v "$version" '{version: $v, platforms: {}}')
for pair in x86_64-linux:linux-x64 aarch64-linux:linux-arm64 aarch64-darwin:macos-arm64; do
  system="${pair%%:*}"
  asset="misfortune-${pair#*:}.tar.gz"
  url="https://github.com/$repo/releases/download/v$version/$asset"
  hash=$(nix store prefetch-file --json "$url" | jq -r .hash)
  json=$(jq --arg s "$system" --arg a "$asset" --arg h "$hash" \
    '.platforms[$s] = {asset: $a, hash: $h}' <<<"$json")
done

jq . <<<"$json" >sources.json
echo "Pinned sources.json to v$version"
