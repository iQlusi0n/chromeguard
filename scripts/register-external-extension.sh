#!/usr/bin/env bash
# Register the VPN Chrome extension as a macOS "external extension" so Chrome
# installs it automatically for ALL users on this Mac (no per-user Load unpacked).
#
# Chrome on macOS only allows this for extensions hosted on the Chrome Web Store
# — a local .crx is NOT permitted — so first publish banner-extension/ to the
# Web Store (an "Unlisted" listing is fine; nobody can find it) and pass its
# 32-character ID here. Each user approves the extension once when prompted.
#
# Usage:   sudo scripts/register-external-extension.sh <extension-id>
# Remove:  sudo rm "/Library/Application Support/Google/Chrome/External Extensions/<id>.json"
set -euo pipefail

EXT_DIR="${EXT_DIR:-/Library/Application Support/Google/Chrome/External Extensions}"
UPDATE_URL="https://clients2.google.com/service/update2/crx"

id="${1:-}"
if [[ ! "${id}" =~ ^[a-p]{32}$ ]]; then
  echo "usage: $0 <chrome-web-store-extension-id>   (32 lowercase letters a-p)" >&2
  exit 2
fi

mkdir -p "${EXT_DIR}"
printf '{\n  "external_update_url": "%s"\n}\n' "${UPDATE_URL}" >"${EXT_DIR}/${id}.json"

# Chrome ignores the all-users folder unless unprivileged users cannot modify
# it and the Chrome directory is group-owned by admin.
if [[ "${EXT_DIR}" == /Library/* ]]; then
  chown root:admin "/Library/Application Support/Google" \
                   "/Library/Application Support/Google/Chrome" \
                   "${EXT_DIR}" "${EXT_DIR}/${id}.json"
  chmod 755 "/Library/Application Support/Google" \
            "/Library/Application Support/Google/Chrome" "${EXT_DIR}"
  chmod 644 "${EXT_DIR}/${id}.json"
fi

echo "Registered ${id} for all users -> ${EXT_DIR}/${id}.json"
echo "Relaunch Chrome; each user approves the extension once when prompted."
