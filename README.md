# VPN Chrome

A dedicated Google Chrome instance whose traffic is routed through a WireGuard
VPN, marked with a banner and protected against WebRTC IP leaks. Your normal
Chrome and every other app stay on the direct connection.

How it works: [wireproxy](https://github.com/whyvl/wireproxy) runs WireGuard in
userspace and exposes it as a local SOCKS5 proxy. A launcher starts that proxy
and opens Chrome with a separate profile pointed at it. Nothing touches macOS
system routing, so only this Chrome goes through the VPN. The setup is
**fail-closed**: the proxy is mandatory and every hostname is made unresolvable
locally (`--host-resolver-rules`), so if the tunnel is down Chrome errors rather
than leaking to the direct connection, and DNS can only happen remotely through
the tunnel.

```
VPN Chrome.app/          double-click to launch (no Terminal window)
chrome-vpn.command       the workflow the app runs (start tunnel -> launch Chrome)
wireproxy.conf.example   WireGuard/proxy config template -> copy to wireproxy.conf
banner-extension/        on-page VPN banner + WebRTC leak protection
assets/appicon.svg       icon source
```

The folder must stay **together**: the app runs its sibling
`chrome-vpn.command`, which reads the sibling `wireproxy.conf` and
`banner-extension/`.

> **Secrets:** `wireproxy.conf` holds your WireGuard private key and is
> git-ignored. Never commit it; start from `wireproxy.conf.example`.

## Prerequisites

- A Mac (Apple Silicon or Intel — everything here is universal).
- **Google Chrome** installed at `/Applications/Google Chrome.app`.
- An admin account (`sudo`) for the `/Applications` install.
- A WireGuard peer for this machine on your server: your private key, your
  tunnel IP, the server's public key, and its endpoint (`host:port`).

## 1. Install the wireproxy binary

wireproxy is **not** on Homebrew. Install the universal macOS binary:

```bash
cd /tmp
curl -fsSL -o wireproxy.tar.gz \
  https://github.com/whyvl/wireproxy/releases/download/v1.1.3/wireproxy_darwin_all.tar.gz
tar -xzf wireproxy.tar.gz
sudo mkdir -p /usr/local/bin
sudo mv wireproxy /usr/local/bin/
sudo chmod +x /usr/local/bin/wireproxy
sudo xattr -dr com.apple.quarantine /usr/local/bin/wireproxy 2>/dev/null || true
wireproxy --version
```

The launcher adds `/usr/local/bin` and `/opt/homebrew/bin` to its PATH, so the
binary is found whether you launch from Terminal or the app.

## 2. Install the app folder (all users)

```bash
sudo mv ~/Downloads/vpn-chrome /Applications/VPN-Chrome   # adjust the source path
cd /Applications/VPN-Chrome

sudo chown -R root:wheel /Applications/VPN-Chrome
sudo chmod -R a+rX /Applications/VPN-Chrome
sudo chmod +x chrome-vpn.command "VPN Chrome.app/Contents/MacOS/VPN Chrome"
sudo xattr -dr com.apple.quarantine /Applications/VPN-Chrome
```

Each user gets their **own** VPN Chrome profile
(`~/Library/Application Support/ChromeVPN`), so nothing mixes between accounts.

## 3. Configure the VPN

```bash
sudo cp wireproxy.conf.example wireproxy.conf
sudo nano wireproxy.conf          # fill in the REPLACE_WITH_... values
wireproxy -n -c wireproxy.conf    # config test, no connection
```

Field notes:

- `Endpoint` — the server's public `host:port`. If this Mac is on the **same
  LAN** as the server, its public address may not loop back (no NAT
  hairpinning); use the server's LAN IP instead, or enable hairpin NAT.
- `DNS` — the resolver used **inside** the tunnel. `1.1.1.1` works out of the
  box. A router LAN IP only works if the router answers DNS on its WireGuard
  interface.
- `MTU` — measure, don't guess (see Troubleshooting). `1340` suits a 1400-byte
  path and is safe everywhere.

**Private key permissions.** `a+rX` above makes `wireproxy.conf` readable by
every local user. If you want to restrict it:

```bash
sudo dseditgroup -o create vpnusers
sudo dseditgroup -o edit -a <username> -t user vpnusers   # repeat per user
sudo chgrp vpnusers wireproxy.conf && sudo chmod 640 wireproxy.conf
```

**Server side:** after adding this peer to the server's `wg0.conf`, apply it —
WireGuard does not hot-reload:

```bash
sudo wg syncconf wg0 <(wg-quick strip wg0)   # peers only, no downtime
# or: sudo wg-quick down wg0 && sudo wg-quick up wg0   # also re-runs PostUp/NAT
sudo wg show wg0                              # peer listed? handshake later?
```

## 4. Launch

Double-click **`VPN Chrome.app`**.

- First launch per user: if macOS says "unidentified developer",
  **right-click → Open → Open** (once per account).
- **Load the extension once** (Chrome 137+ removed the `--load-extension` flag,
  so it is loaded into the profile instead): open `chrome://extensions`, turn on
  **Developer mode**, click **Load unpacked**, select
  `/Applications/VPN-Chrome/banner-extension`. This enables **both** the banner
  and the WebRTC leak block, and persists across relaunches.
- No Rosetta prompt: the bundle sets `LSRequiresNativeExecution`.

Quit the VPN Chrome window (⌘Q) to stop; if the app started the tunnel it
shuts `wireproxy` down on quit (unless another user is still connected).

When launched via the app there is no terminal, so progress is written to
`~/Library/Logs/VPN Chrome.log` and any startup error is shown as a native
alert. Running `chrome-vpn.command` in Terminal prints the same output live.

## 5. Verify

In VPN Chrome:

1. **Banner** — the red ribbon shows on real sites (not on `chrome://` pages).
2. **VPN IP** — <https://ifconfig.me> shows the server's IP.
3. **No leak elsewhere** — normal Chrome on the same site shows your real IP.
4. **WebRTC** — <https://browserleaks.com/webrtc> reveals no real/local IP. To
   confirm the policy directly: `chrome://extensions` → the extension's
   **service worker** → Console:
   `chrome.privacy.network.webRTCIPHandlingPolicy.get({}, console.log)` should
   print `disable_non_proxied_udp` / `controlled_by_this_extension`.

From Terminal, the same path as Chrome:

```bash
curl -sS --socks5-hostname 127.0.0.1:25344 https://api.ipify.org; echo
```

## Customizing

- **Banner** — `banner-extension/content.js`, the `CONFIG` block: `text`,
  `color`, `opacity`, `position` (`frame`, `ribbon-top-right`,
  `ribbon-top-left`, `ribbon-bottom-right`, `ribbon-bottom-left`, `bar-top`).
- **WebRTC strictness** — `banner-extension/background.js`, `WEBRTC_POLICY`:
  `disable_non_proxied_udp` (default, leak-proof, may break P2P calls),
  `default_public_interface_only` (softer), `default` (off).
- **Icon** — source in `assets/appicon.svg`. Render to PNG at 16–1024, place in
  an `.iconset`, run `iconutil -c icns`, and replace
  `VPN Chrome.app/Contents/Resources/appIcon.icns`. Then `touch` the app and
  `killall Dock Finder`.

## Troubleshooting

- **App won't start / error alert** — read `~/Library/Logs/VPN Chrome.log`
  (per user) and the proxy log it points to. A bad config is caught up front by
  `wireproxy -n` before anything starts.
- **Nothing loads / `ERR_SOCKS_CONNECTION_FAILED`** — Chrome reached the proxy
  but the tunnel isn't passing traffic. Run the proxy in the foreground to see
  why: `wireproxy -c /Applications/VPN-Chrome/wireproxy.conf`.
  - No `Received handshake response` → the server isn't reachable or doesn't
    know this peer (check `sudo wg show wg0`, the `Endpoint`, UDP port
    forwarding, hairpin NAT, CGNAT).
  - Handshake OK but hangs on `Resolving address` → DNS inside the tunnel;
    try `DNS = 1.1.1.1`.
  - Handshake OK, `curl` returns empty, `wg show` has far more *sent* than
    *received* → **MTU**. Measure the path MTU from this Mac:

    ```bash
    for s in 1472 1452 1432 1412 1392 1372 1352 1332 1300 1272; do
      ping -c1 -W1000 -D -s "$s" 8.8.8.8 >/dev/null 2>&1 && echo "OK $s -> path MTU $((s+28))"
    done
    ```

    Set `MTU = <largest path MTU> - 60` in `wireproxy.conf`.
- **"wireproxy not found"** — `which wireproxy` should print
  `/usr/local/bin/wireproxy`; redo step 1.
- **"You need to install Rosetta"** — already mitigated in `Info.plist`. If it
  still prompts, reboot, or right-click the app → Get Info → uncheck "Open
  using Rosetta".
- **No banner / WebRTC not blocked** — the extension isn't loaded; redo the
  Load-unpacked step. Both features live in that one extension.
- **Video calls won't connect** — expected with `disable_non_proxied_udp`; see
  Customizing.
- **Icon doesn't update** — `touch "/Applications/VPN-Chrome/VPN Chrome.app"`,
  `killall Dock Finder`, or log out/in.
- **Several users at once** — one shared tunnel on `127.0.0.1:25344`. The
  launcher leaves it running on quit while other clients are still connected,
  so one user quitting won't cut another off; the process may then linger until
  that first user logs out. For an always-on shared tunnel, run wireproxy as a
  LaunchDaemon instead.

## Development

`biome.json` configures lint/format for the extension (`biome check .`). Shell
scripts pass `shellcheck -o all`.
