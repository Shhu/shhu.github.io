#!/usr/bin/env bash
# Publishes the shu-app.com Flatpak repository (https://shu-app.com/flatpak/repo/): the bundle of
# the latest release of each app, imported into a fresh repository, signed, with its AppStream
# catalog, then handed to this site's Pages workflow as the asset of the `flatpak-repo` release.
# Each app's release script runs it once its GitHub release exists; it always takes the latest
# release of every app, so the order does not matter.
#
# Signed with the key in ~/.tauri/shu-flatpak-gpg, which never leaves this computer; its public
# half is flatpak/shu-app.gpg, written into the .flatpakref and .flatpakrepo files.
set -euo pipefail

key=AAE5190E796E12E130A6197706BEFFF96F9401CE
gpg_home="$HOME/.tauri/shu-flatpak-gpg"
site=Shhu/shhu.github.io
# Repository, bundle name in its releases.
apps=(
  "Shhu/facteur facteur.flatpak"
  "Shhu/atelier atelier.flatpak"
)

[[ -d "$gpg_home" ]] || { echo "missing signing key: $gpg_home" >&2; exit 1; }
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

ostree init --repo="$work/repo" --mode=archive-z2
for app in "${apps[@]}"; do
  read -r repo bundle <<< "$app"
  # The newest published release from the list: "latest" (gh release view) can still name the
  # previous one for a few seconds after a release is created.
  tag="$(gh api "repos/$repo/releases?per_page=10" \
    --jq '[.[] | select((.draft or .prerelease) | not)] | sort_by(.created_at) | last | .tag_name')"
  [[ -n "$tag" && "$tag" != null ]] || { echo "no release found in $repo" >&2; exit 1; }
  gh release download "$tag" --repo "$repo" --pattern "$bundle" --dir "$work"
  flatpak build-import-bundle --gpg-sign="$key" --gpg-homedir="$gpg_home" "$work/repo" "$work/$bundle" 2>&1 \
    | grep -v CRITICAL | grep -v '^$' || true
  echo "$repo $tag"
done
flatpak build-update-repo --title=shu-app.com --gpg-sign="$key" --gpg-homedir="$gpg_home" \
  --generate-static-deltas --prune "$work/repo"

tar -C "$work" -cf "$work/flatpak-repo.tar" repo
if ! gh release view flatpak-repo --repo "$site" > /dev/null 2>&1; then
  gh release create flatpak-repo --repo "$site" --title "Flatpak repository" \
    --notes "Built by flatpak/publish.sh; the Pages workflow serves it at https://shu-app.com/flatpak/repo/."
fi
gh release upload flatpak-repo "$work/flatpak-repo.tar" --repo "$site" --clobber
gh workflow run pages.yml --repo "$site"
echo "Flatpak repository published: https://shu-app.com/flatpak/ (live within a few minutes)"
