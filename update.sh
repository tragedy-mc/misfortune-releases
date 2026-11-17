#!/usr/bin/env bash
# Pin sources.json to a published release: ./update.sh [vX.Y.Z]
# With no argument, uses the latest release of this repo.
# Prefers each platform's installer (.deb/.dmg) and falls back to the plain
# .tar.gz for releases that predate the installers.
set -euo pipefail

repo="tragedy-mc/misfortune-releases"
cd "$(dirname "$0")"

api() {
  curl -fsSL ${GH_TOKEN:+-H "Authorization: Bearer $GH_TOKEN"} "https://api.github.com/repos/$repo/$1"
}

tag="${1:-$(api releases/latest | jq -r .tag_name)}"
version="${tag#v}"
assets=$(api "releases/tags/v$version" | jq -r '.assets[].name')

json=$(jq -n --arg v "$version" '{version: $v, platforms: {}}')
for entry in x86_64-linux:linux-x64:deb aarch64-linux:linux-arm64:deb aarch64-darwin:macos-arm64:dmg; do
  IFS=: read -r system name ext <<<"$entry"
  asset="misfortune-$name.$ext"
  grep -qxF "$asset" <<<"$assets" || asset="misfortune-$name.tar.gz"
  grep -qxF "$asset" <<<"$assets" || { echo "v$version has no $asset" >&2; exit 1; }
  url="https://github.com/$repo/releases/download/v$version/$asset"
  hash=$(nix store prefetch-file --json "$url" | jq -r .hash)
  json=$(jq --arg s "$system" --arg a "$asset" --arg h "$hash" \
    '.platforms[$s] = {asset: $a, hash: $h}' <<<"$json")
done

jq . <<<"$json" >sources.json
echo "Pinned sources.json to v$version"
