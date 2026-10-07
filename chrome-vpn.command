#!/usr/bin/env bash
# VPN Chrome launcher.
#   - Starts wireproxy (userspace WireGuard -> local SOCKS5) if it isn't running.
#   - Launches a DEDICATED Google Chrome profile whose traffic goes through the
#     VPN, with a banner so it's obviously distinct from normal Chrome.
#   - Your normal Chrome (the standard app icon) is untouched and stays direct.
#
# Double-click this file in Finder to launch, or run it from a terminal.
#
# port_open() is an intentional boolean predicate; suppressing `set -e` inside
# its `if`/`&&`/`!` conditions (SC2310) is the desired behavior here.
# shellcheck disable=SC2310
set -euo pipefail

# GUI launches (Finder / the .app) get a minimal PATH that omits Homebrew and
# /usr/local/bin, so tools like wireproxy wouldn't be found. Add them back.
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"

# --- config ---------------------------------------------------------------
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROXY_HOST="127.0.0.1"
PROXY_PORT="25344"                       # must match BindAddress in wireproxy.conf
PROFILE="${HOME}/Library/Application Support/ChromeVPN"   # dedicated, separate profile
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
WP_CONF="${DIR}/wireproxy.conf"
WP_LOG="${TMPDIR:-/tmp}/wireproxy-chrome.log"
STARTUP_TIMEOUT=10                       # seconds to wait for the SOCKS5 port
# --------------------------------------------------------------------------

die() {
  echo "$1" >&2
  read -r -p "Press Return to close..." _
  exit 1
}

command -v wireproxy >/dev/null 2>&1 ||
  die "wireproxy not found on PATH. Install it (see README.md, step 1) — it is not a Homebrew package."
[[ -x "${CHROME}" ]] ||
  die "Google Chrome not found at: ${CHROME}"
[[ -f "${WP_CONF}" ]] ||
  die "wireproxy config not found at: ${WP_CONF}. Copy wireproxy.conf.example to wireproxy.conf and fill in your keys."

port_open() { nc -z -w 1 "${PROXY_HOST}" "${PROXY_PORT}" >/dev/null 2>&1; }

WP_PID=""
STARTED_WP=0
if port_open; then
  echo "wireproxy already running on ${PROXY_HOST}:${PROXY_PORT}."
else
  echo "Starting WireGuard tunnel (wireproxy)..."
  wireproxy -c "${WP_CONF}" >"${WP_LOG}" 2>&1 &
  WP_PID=$!
  STARTED_WP=1

  # Wait for the SOCKS5 port, polling every 0.2s.
  for ((i = 0; i < STARTUP_TIMEOUT * 5; i++)); do
    port_open && break
    if ! kill -0 "${WP_PID}" 2>/dev/null; then
      cat "${WP_LOG}" >&2 || true
      die "wireproxy exited early (see log above)."
    fi
    sleep 0.2
  done

  if ! port_open; then
    cat "${WP_LOG}" >&2 || true
    kill "${WP_PID}" 2>/dev/null || true
    die "Timed out waiting for SOCKS5 on ${PROXY_HOST}:${PROXY_PORT} (see log above)."
  fi
  echo "Tunnel up."
fi

# If we started wireproxy, tear it down when this VPN Chrome instance quits.
cleanup() {
  if [[ "${STARTED_WP}" = 1 ]] && [[ -n "${WP_PID}" ]]; then
    kill "${WP_PID}" 2>/dev/null || true
    echo "Stopped wireproxy."
  fi
}
trap cleanup EXIT

# NOTE: Chrome 137+ removed the --load-extension flag, so the banner /
# WebRTC-block extension is loaded once into this dedicated profile via
# chrome://extensions -> Developer mode -> "Load unpacked" (see README.md).
# It then persists across launches because the profile is fixed below.
echo "Launching VPN Chrome..."
"${CHROME}" \
  --user-data-dir="${PROFILE}" \
  --proxy-server="socks5://${PROXY_HOST}:${PROXY_PORT}" \
  --no-first-run \
  --no-default-browser-check \
  "$@"
