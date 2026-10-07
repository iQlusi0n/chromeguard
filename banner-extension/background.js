// Block WebRTC IP leaks for this (VPN) Chrome profile only.
//
// The VPN here is an app-level SOCKS5 proxy, which carries TCP only. WebRTC
// otherwise reaches the network over UDP and by enumerating local interfaces,
// both of which bypass the proxy and expose your real IP. Constraining
// WebRTC's IP-handling policy stops that.
//
//   "disable_non_proxied_udp"  RECOMMENDED. Leak-proof: WebRTC may only use
//                              UDP that goes through the proxy. Peer-to-peer
//                              calls fall back to TURN-over-TCP, or don't
//                              connect — but your real IP never leaks.
//   "default_public_interface_only"  Softer: hides local/LAN IPs but still
//                              exposes the public IP via STUN. Not leak-proof.
//   "default"                  Chrome's normal behavior (leaks). Effectively off.
const WEBRTC_POLICY = "disable_non_proxied_udp";

function applyPolicy() {
  chrome.privacy.network.webRTCIPHandlingPolicy.set({ value: WEBRTC_POLICY }, () => {
    if (chrome.runtime.lastError) {
      console.error("VPN Chrome: failed to set WebRTC policy:", chrome.runtime.lastError.message);
    }
  });
}

chrome.runtime.onInstalled.addListener(applyPolicy);
chrome.runtime.onStartup.addListener(applyPolicy);
