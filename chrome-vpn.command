#!/usr/bin/env bash
# VPN Chrome launcher.
#   - Starts wireproxy (userspace WireGuard -> local SOCKS5) if it isn't running.
#   - Launches a DEDICATED Google Chrome profile whose traffic goes through the
#     VPN, with a banner so it's obviously distinct from normal Chrome.
#   - Your normal Chrome (the standard app icon) is untouched and stays direct.
#
# Run it from a terminal to watch progress, or launch via "VPN Chrome.app"
# (then progress goes to ~/Library/Logs/VPN Chrome.log and errors pop an alert).
#
# port_open()/tunnel_in_use() are intentional boolean predicates; suppressing
# `set -e` inside their `if`/`&&`/`!` conditions (SC2310) is desired.
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
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
WP_CONF="${DIR}/wireproxy.conf"
WP_LOG="${TMPDIR:-/tmp}/wireproxy-chrome.log"
LAUNCH_LOG="${HOME}/Library/Logs/VPN Chrome.log"
STARTUP_TIMEOUT=10                       # seconds to wait for the SOCKS5 port
# --------------------------------------------------------------------------

# Launched without a terminal (the .app): keep a log so failures are diagnosable.
if [[ ! -t 1 ]]; then
  mkdir -p "$(dirname "${LAUNCH_LOG}")"
  exec >>"${LAUNCH_LOG}" 2>&1
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  echo "=== ${ts} launch ==="
fi

die() {
  echo "ERROR: $1" >&2
  if [[ -t 0 ]]; then
    read -r -p "Press Return to close..." _
  else
    # No terminal: surface the error as a native alert instead of vanishing.
    osascript -e 'on run argv' \
              -e 'display alert "VPN Chrome" message (item 1 of argv)' \
              -e 'end run' "$1" >/dev/null 2>&1 || true
  fi
  exit 1
}

command -v wireproxy >/dev/null 2>&1 ||
  die "wireproxy not found on PATH. Install it (see README.md, step 1) — it is not a Homebrew package."
[[ -x "${CHROME}" ]] ||
  die "Google Chrome not found at: ${CHROME}"
[[ -f "${WP_CONF}" ]] ||
  die "wireproxy config not found at: ${WP_CONF}. Copy wireproxy.conf.example to wireproxy.conf and fill in your keys."

port_open() { nc -z -w 1 "${PROXY_HOST}" "${PROXY_PORT}" >/dev/null 2>&1; }

# Any client (e.g. another user's VPN Chrome) still connected to the proxy?
# netstat sees all users' sockets; plain grep (not -q) keeps pipefail happy.
tunnel_in_use() {
  netstat -an -p tcp 2>/dev/null | grep "\.${PROXY_PORT} .*ESTABLISHED" >/dev/null
}

WP_PID=""
STARTED_WP=0
if port_open; then
  echo "wireproxy already running on ${PROXY_HOST}:${PROXY_PORT}."
else
  # Fail fast on a bad config instead of a vague startup timeout.
  if ! wireproxy -n -c "${WP_CONF}" >"${WP_LOG}" 2>&1; then
    cat "${WP_LOG}" >&2 || true
    die "wireproxy config test failed — fix wireproxy.conf (details in ${WP_LOG})."
  fi

  echo "Starting WireGuard tunnel (wireproxy)..."
  wireproxy -c "${WP_CONF}" >"${WP_LOG}" 2>&1 &
  WP_PID=$!
  STARTED_WP=1

  # Wait for the SOCKS5 port, polling every 0.2s.
  for ((i = 0; i < STARTUP_TIMEOUT * 5; i++)); do
    port_open && break
    if ! kill -0 "${WP_PID}" 2>/dev/null; then
      cat "${WP_LOG}" >&2 || true
      die "wireproxy exited early (details in ${WP_LOG})."
    fi
    sleep 0.2
  done

  if ! port_open; then
    cat "${WP_LOG}" >&2 || true
    kill "${WP_PID}" 2>/dev/null || true
    die "Timed out waiting for SOCKS5 on ${PROXY_HOST}:${PROXY_PORT} (details in ${WP_LOG})."
  fi
  echo "Tunnel up."
fi

# If we started wireproxy, tear it down when this VPN Chrome quits — unless
# someone else is still using it.
cleanup() {
  if [[ "${STARTED_WP}" = 1 ]] && [[ -n "${WP_PID}" ]]; then
    if tunnel_in_use; then
      echo "Other clients still use the tunnel; leaving wireproxy running."
      return 0
    fi
    kill "${WP_PID}" 2>/dev/null || true
    echo "Stopped wireproxy."
  fi
}
trap cleanup EXIT

# NOTE: Chrome 137+ removed the --load-extension flag, so the banner /
# WebRTC-block extension is loaded once into this dedicated profile via
# chrome://extensions -> Developer mode -> "Load unpacked" (see README.md).
# It then persists across launches because the profile is fixed below.
#
# --host-resolver-rules makes every hostname UNRESOLVABLE locally (except the
# proxy itself), so DNS can only happen remotely through the SOCKS5 tunnel.
# If the tunnel is down, Chrome errors rather than falling back to direct.
echo "Launching VPN Chrome..."
"${CHROME}" \
  --user-data-dir="${PROFILE}" \
  --proxy-server="socks5://${PROXY_HOST}:${PROXY_PORT}" \
  --host-resolver-rules="MAP * ~NOTFOUND , EXCLUDE ${PROXY_HOST}" \
  --no-first-run \
  --no-default-browser-check \
  "$@"
