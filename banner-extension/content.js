(() => {
  "use strict";

  // ── Configuration ────────────────────────────────────────────────────────
  // Visual styling mirrors the "Environment Marker" extension exactly
  // (moldure frame + diagonal corner ribbons). URL matching is dropped since
  // this browser is always the VPN browser, so the marker is always shown.
  const CONFIG = {
    text: "VPN CHROME \u00B7 WireGuard", // label text (ribbon / bar modes)
    color: "#b71c1c", // marker color
    opacity: 1, // 0 .. 1 (Env Marker: ribbon transparency)
    // position: one of
    //   "frame"            full-page 8px border ("Moldure") — no text label
    //   "ribbon-top-right" | "ribbon-top-left"
    //   "ribbon-bottom-right" | "ribbon-bottom-left"   diagonal corner ribbon
    //   "bar-top"          extra: full-width top bar (not in Env Marker)
    position: "ribbon-top-right",
    frameThickness: 8, // px, "frame" mode (Env Marker uses 8)
    minFontSize: 15, // ribbon auto-fit bounds (Env Marker)
    maxFontSize: 45,
  };
  // ─────────────────────────────────────────────────────────────────────────

  // Top frame only; never inject into iframes.
  if (window.top !== window) return;

  const WRAP_ID = "chrome-envmarker";
  const TEXT_ID = "chrome-envmarker-text";
  const Z = 2147483647;

  // Diagonal ribbon geometry, matching Environment Marker's _addMarker.
  const RIBBON = {
    "ribbon-top-right": "right: -72px; top: 45px; transform: rotate(45deg);",
    "ribbon-top-left": "left: -72px; top: 45px; transform: rotate(-45deg);",
    "ribbon-bottom-right": "right: -72px; bottom: 45px; transform: rotate(-45deg);",
    "ribbon-bottom-left": "left: -72px; bottom: 45px; transform: rotate(45deg);",
  };

  // Dependency-free replacement for the textFit lib: shrink the font from
  // maxFontSize until the text fits the inner box (single line), floored
  // at minFontSize.
  function fitText(el, min, max) {
    let size = max;
    el.style.fontSize = `${size}px`;
    while (size > min && (el.scrollWidth > el.clientWidth || el.scrollHeight > el.clientHeight)) {
      size -= 1;
      el.style.fontSize = `${size}px`;
    }
  }

  function build() {
    const existing = document.getElementById(WRAP_ID);
    if (existing) existing.remove();

    const pos = CONFIG.position;
    const wrap = document.createElement("div");
    wrap.id = WRAP_ID;

    if (pos === "frame") {
      // Moldure — verbatim style shape from Environment Marker (no label).
      wrap.style.cssText = `
        position: fixed; top:0; left:0; right:0; bottom:0;
        border: ${CONFIG.frameThickness}px solid ${CONFIG.color};
        z-index: ${Z}; pointer-events:none; user-select:none;
        opacity:${CONFIG.opacity};`;
      document.body.appendChild(wrap);
      return;
    }

    if (pos === "bar-top") {
      // Extra convenience mode (not part of Environment Marker).
      wrap.style.cssText = `
        position: fixed; top:0; left:0; right:0; padding:6px 12px;
        background-color: ${CONFIG.color}; color:#fff; text-align:center;
        font:600 12px/1.3 -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
        letter-spacing:.3px; box-shadow:0 1px 4px rgba(0,0,0,.4);
        white-space:nowrap; overflow:hidden; text-overflow:ellipsis;
        box-sizing:border-box; z-index:${Z}; pointer-events:none;
        user-select:none; opacity:${CONFIG.opacity};`;
      wrap.textContent = CONFIG.text;
      document.body.appendChild(wrap);
      const shift = () => {
        document.body.style.setProperty("margin-top", `${wrap.offsetHeight}px`, "important");
      };
      shift();
      window.addEventListener("load", shift);
      return;
    }

    // Diagonal ribbon — verbatim style shape from Environment Marker.
    const positionStyle = RIBBON[pos] || RIBBON["ribbon-top-right"];
    const ribbonWidth = "290px";
    const ribbonHeight = "55px";

    wrap.style.cssText = `
      text-shadow: -1px -1px 0 #555, 1px -1px 0 #555, -1px 1px 0 #555, 1px 1px 0 #555;
      position: fixed; ${positionStyle}
      background-color: ${CONFIG.color};
      z-index: ${Z}; height: ${ribbonHeight}; width: ${ribbonWidth};
      overflow-x: hidden; box-shadow: 7px 0px 9px #000; color: #fff;
      pointer-events:none; user-select:none; opacity:${CONFIG.opacity};`;

    const textDiv = document.createElement("div");
    textDiv.id = TEXT_ID;
    textDiv.style.cssText = `
      margin: 0 45px; line-height: ${ribbonHeight}; height:100%;
      width: calc(100% - 90px); overflow:hidden; text-align:center;
      font-family: Arial, sans-serif;`;
    textDiv.textContent = CONFIG.text;
    wrap.appendChild(textDiv);
    document.body.appendChild(wrap);

    fitText(textDiv, CONFIG.minFontSize, CONFIG.maxFontSize);
  }

  function init() {
    if (document.body) build();
    else document.addEventListener("DOMContentLoaded", build);
  }

  init();
  window.addEventListener("hashchange", init);
})();
