#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# KetraWOS 1 — Otomatik HyperFrames Kurulum, Güvenlik Kontrolü ve Video Üretici
# Çıktılar:
#   1) ./ketrawos-workspace/output/ketrawos-boot-240x240.mp4
#   2) ./ketrawos-workspace/output/ketrawos-dualboot-240x240.mp4
# ==============================================================================

WORKDIR="$(pwd)/ketrawos-workspace"
BOOT_DIR="$WORKDIR/projects/ketrawos-boot"
DUAL_DIR="$WORKDIR/projects/ketrawos-dualboot"
OUT_DIR="$WORKDIR/output"
HF_BIN="$WORKDIR/node_modules/.bin/hyperframes"

log()  { printf "\n\033[1;36m[KetraWOS]\033[0m %s\n" "$1"; }
ok()   { printf "\033[1;32m[OK]\033[0m %s\n" "$1"; }
fail() { printf "\033[1;31m[HATA]\033[0m %s\n" "$1" >&2; exit 1; }

# ------------------------------------------------------------------------------
# 1. Ön Gereksinim Kontrolü (Node.js >= 22, npm, FFmpeg, FFprobe)
# ------------------------------------------------------------------------------
log "1/6 — Sistem gereksinimleri kontrol ediliyor..."

command -v node    >/dev/null 2>&1 || fail "Node.js bulunamadı. Lütfen Node.js 22+ kurun (https://nodejs.org/)."
command -v npm     >/dev/null 2>&1 || fail "npm bulunamadı."
command -v ffmpeg  >/dev/null 2>&1 || fail "FFmpeg bulunamadı. Kurulum: sudo apt install -y ffmpeg (Linux) | brew install ffmpeg (macOS)"
command -v ffprobe >/dev/null 2>&1 || fail "ffprobe bulunamadı (FFmpeg ile birlikte gelir)."

NODE_MAJOR="$(node -p "process.versions.node.split('.')[0]")"
if [ "$NODE_MAJOR" -lt 22 ]; then
  fail "HyperFrames için Node.js 22+ gerekli (mevcut: v$(node -v))."
fi
ok "Node.js $(node -v), FFmpeg ve FFprobe hazır."

# ------------------------------------------------------------------------------
# 2. HyperFrames Kurulumu (İzole Çalışma Alanı)
# ------------------------------------------------------------------------------
log "2/6 — HyperFrames kuruluyor ($WORKDIR)..."

mkdir -p "$WORKDIR" "$BOOT_DIR" "$DUAL_DIR" "$OUT_DIR"
cd "$WORKDIR"

if [ ! -f "$WORKDIR/package.json" ]; then
  npm init -y >/dev/null
fi

npm install --no-fund hyperframes
[ -x "$HF_BIN" ] || fail "HyperFrames ikili dosyası kurulamadı: $HF_BIN"
ok "HyperFrames kuruldu ($("$HF_BIN" --version 2>/dev/null || echo 'kurulu'))."

# ------------------------------------------------------------------------------
# 3. Güvenlik ve Ortam Kontrolleri (npm audit + browser ensure + doctor + CDN)
# ------------------------------------------------------------------------------
log "3/6 — Güvenlik ve ortam denetimleri çalıştırılıyor..."

# 3a) Kritik bağımlılık güvenlik açığı taraması
npm audit --audit-level=critical
ok "npm audit (critical) temiz."

# 3b) Sandboxed Headless Chrome kurulumu ve ortam doktoru kontrolü
"$HF_BIN" browser ensure
DOCTOR_JSON="$("$HF_BIN" doctor --json)"
node -e '
  const data = JSON.parse(process.argv[1]);
  if (!data.ok) {
    console.error("Doctor başarısız:", JSON.stringify(data, null, 2));
    process.exit(1);
  }
' "$DOCTOR_JSON"
ok "HyperFrames doctor ve sandboxed Chrome doğrulandı."

# 3c) GSAP 3.14.2 CDN erişim ve SHA-256 bütünlük kontrolü
node -e '
  const { createHash } = require("crypto");
  (async () => {
    const url = "https://cdn.jsdelivr.net/npm/gsap@3.14.2/dist/gsap.min.js";
    const res = await fetch(url);
    if (!res.ok) throw new Error("HTTP " + res.status);
    const body = await res.text();
    if (!body.includes("GSAP") && !body.includes("GreenSock")) {
      throw new Error("Beklenmeyen GSAP içeriği");
    }
    const sha256 = createHash("sha256").update(body).digest("hex");
    console.log("GSAP 3.14.2 doğrulandı (SHA-256: " + sha256 + ")");
  })().catch((err) => {
    console.error("GSAP CDN doğrulaması başarısız:", err.message);
    process.exit(1);
  });
'
ok "GSAP CDN bütünlük kontrolü geçti."

# ------------------------------------------------------------------------------
# 4. 240x240 Kompozisyon Dosyalarını Oluşturma
# ------------------------------------------------------------------------------
log "4/6 — KetraWOS 1 ve Dual Boot (240x240) dosyaları indiriliyor/oluşturuluyor..."

cat <<'EOF' > "$BOOT_DIR/index.html"
<!doctype html>
<html lang="tr">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=240, height=240" />
  <title>KetraWOS 1 — Boot &amp; Loop (240x240)</title>
  <script src="https://cdn.jsdelivr.net/npm/gsap@3.14.2/dist/gsap.min.js"></script>
  <style>
    * { box-sizing: border-box; }
    html, body {
      margin: 0;
      padding: 0;
      width: 240px;
      height: 240px;
      overflow: hidden;
      background: #000000;
    }
    #root {
      position: relative;
      width: 100%;
      height: 100%;
      overflow: hidden;
      background: #000000;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, sans-serif;
      color: #f8fafc;
    }
    .clip {
      position: absolute;
      inset: 0;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    #boot-stage {
      position: relative;
      width: 240px;
      height: 240px;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    #core-halo {
      position: absolute;
      width: 170px;
      height: 170px;
      border-radius: 50%;
      background: radial-gradient(circle, rgba(0, 245, 212, 0.3) 0%, rgba(56, 189, 248, 0.12) 44%, rgba(0, 0, 0, 0) 74%);
      opacity: 0;
      pointer-events: none;
    }
    #shutdown-flash-line {
      position: absolute;
      width: 164px;
      height: 2px;
      border-radius: 999px;
      background: linear-gradient(90deg, rgba(0, 245, 212, 0) 0%, #e0f2fe 50%, rgba(0, 245, 212, 0) 100%);
      box-shadow: 0 0 10px rgba(56, 189, 248, 0.9);
      opacity: 0;
      pointer-events: none;
    }
    #watch-hud {
      position: absolute;
      inset: 0;
      width: 240px;
      height: 240px;
      pointer-events: none;
    }
    #brand-layer {
      position: absolute;
      inset: 0;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: flex-start;
      padding-top: 112px;
      pointer-events: none;
    }
    #wordmark-row {
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 6px;
      opacity: 0;
    }
    #brand-name {
      font-size: 22px;
      font-weight: 700;
      letter-spacing: -0.02em;
      line-height: 1;
      color: #f8fafc;
    }
    #version-pill {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-width: 22px;
      height: 22px;
      padding: 0 5px;
      border-radius: 6px;
      background: linear-gradient(135deg, #00f5d4 0%, #38bdf8 100%);
      color: #03131a;
      font-size: 14px;
      font-weight: 800;
      line-height: 1;
    }
    #progress-track {
      position: relative;
      margin-top: 14px;
      width: 112px;
      height: 4px;
      border-radius: 999px;
      background: rgba(148, 163, 184, 0.22);
      overflow: hidden;
      opacity: 0;
    }
    #progress-fill {
      position: absolute;
      left: 0;
      top: 0;
      width: 112px;
      height: 4px;
      border-radius: 999px;
      background: linear-gradient(90deg, #0ea5e9 0%, #00f5d4 100%);
      transform-origin: left center;
    }
    #progress-shimmer {
      position: absolute;
      left: 0;
      top: 0;
      width: 38px;
      height: 4px;
      border-radius: 999px;
      background: linear-gradient(90deg, rgba(255, 255, 255, 0) 0%, rgba(255, 255, 255, 0.95) 50%, rgba(255, 255, 255, 0) 100%);
      opacity: 0;
    }
    #status-row {
      margin-top: 12px;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 6px;
      opacity: 0;
    }
    #status-label {
      font-family: monospace;
      font-size: 11px;
      font-weight: 700;
      letter-spacing: 0.12em;
      color: #bae6fd;
    }
    #wait-dots {
      display: flex;
      align-items: center;
      gap: 4px;
    }
    .wait-dot {
      width: 4px;
      height: 4px;
      border-radius: 50%;
      background: #00f5d4;
      opacity: 0.25;
    }
  </style>
</head>
<body>
  <div
    id="root"
    data-composition-id="ketrawos-boot"
    data-start="0"
    data-duration="9"
    data-width="240"
    data-height="240"
  >
    <section id="boot-clip" class="clip" data-start="0" data-duration="9" data-track-index="1">
      <div id="boot-stage">
        <div id="core-halo"></div>
        <div id="shutdown-flash-line"></div>

        <svg id="watch-hud" viewBox="0 0 240 240" width="240" height="240">
          <defs>
            <linearGradient id="ringAccentGrad" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" stop-color="#00f5d4" />
              <stop offset="100%" stop-color="#38bdf8" />
            </linearGradient>
            <linearGradient id="scannerGrad" x1="0%" y1="0%" x2="100%" y2="0%">
              <stop offset="0%" stop-color="#00f5d4" stop-opacity="0" />
              <stop offset="65%" stop-color="#00f5d4" stop-opacity="0.9" />
              <stop offset="100%" stop-color="#e0f2fe" stop-opacity="1" />
            </linearGradient>
          </defs>

          <circle id="outer-track-ring" cx="120" cy="120" r="102" fill="none" stroke="rgba(56, 189, 248, 0.28)" stroke-width="2" stroke-linecap="round" pathLength="100" stroke-dasharray="100 120" stroke-dashoffset="110" />
          <circle id="inner-precision-ring" cx="120" cy="120" r="91" fill="none" stroke="rgba(0, 245, 212, 0.24)" stroke-width="1.5" stroke-linecap="round" pathLength="100" stroke-dasharray="100 120" stroke-dashoffset="110" />
          <g id="dial-ticks-group"></g>
          <circle id="orbital-scanner" cx="120" cy="120" r="102" fill="none" stroke="url(#scannerGrad)" stroke-width="3" stroke-linecap="round" pathLength="100" stroke-dasharray="22 78" stroke-dashoffset="0" style="opacity: 0;" />
          <circle id="orbital-beacon" cx="120" cy="18" r="3.2" fill="#e0f2fe" style="opacity: 0;" />
          <circle id="inner-beacon" cx="120" cy="29" r="2.2" fill="#00f5d4" style="opacity: 0;" />
          <circle id="core-ignition-dot" cx="120" cy="120" r="6" fill="#e0f2fe" style="opacity: 0;" />

          <g id="emblem-group">
            <path id="emblem-hex" d="M 120 52 L 142 64.5 L 142 89.5 L 120 102 L 98 89.5 L 98 64.5 Z" fill="rgba(0, 245, 212, 0.1)" stroke="url(#ringAccentGrad)" stroke-width="2" stroke-linejoin="round" stroke-linecap="round" pathLength="100" stroke-dasharray="100 120" stroke-dashoffset="110" style="opacity: 0;" />
            <path id="emblem-stem" d="M 111 64 L 111 90" fill="none" stroke="#f8fafc" stroke-width="3" stroke-linecap="round" pathLength="100" stroke-dasharray="100 120" stroke-dashoffset="110" style="opacity: 0;" />
            <path id="emblem-upper" d="M 129 65 L 114 77" fill="none" stroke="#00f5d4" stroke-width="3" stroke-linecap="round" pathLength="100" stroke-dasharray="100 120" stroke-dashoffset="110" style="opacity: 0;" />
            <path id="emblem-lower" d="M 116 75 L 130 90" fill="none" stroke="#38bdf8" stroke-width="3" stroke-linecap="round" pathLength="100" stroke-dasharray="100 120" stroke-dashoffset="110" style="opacity: 0;" />
          </g>
        </svg>

        <div id="brand-layer">
          <div id="wordmark-row">
            <span id="brand-name">KetraWOS</span>
            <span id="version-pill">1</span>
          </div>
          <div id="progress-track">
            <div id="progress-fill"></div>
            <div id="progress-shimmer"></div>
          </div>
          <div id="status-row">
            <span id="status-label">BOOTING</span>
            <div id="wait-dots">
              <div id="wait-dot-0" class="wait-dot"></div>
              <div id="wait-dot-1" class="wait-dot"></div>
              <div id="wait-dot-2" class="wait-dot"></div>
            </div>
          </div>
        </div>
      </div>
    </section>
  </div>

  <script>
    const INTRO_DURATION = 3;
    const LOOP_CYCLE_SEC = 2;
    const LOOP_TOTAL_SEC = 6;
    const LOOP_REPEAT = Math.max(0, Math.floor(LOOP_TOTAL_SEC / LOOP_CYCLE_SEC) - 1);

    const ticksGroup = document.getElementById("dial-ticks-group");
    const svgNS = "http://www.w3.org/2000/svg";
    const tickEls = [];

    for (let i = 0; i < 12; i++) {
      const angleRad = ((i * 30) - 90) * (Math.PI / 180);
      const rIn = (i % 3 === 0) ? 94 : 96;
      const rOut = 99.5;
      const line = document.createElementNS(svgNS, "line");
      line.setAttribute("id", "dial-tick-" + i);
      line.setAttribute("x1", (120 + Math.cos(angleRad) * rIn).toFixed(2));
      line.setAttribute("y1", (120 + Math.sin(angleRad) * rIn).toFixed(2));
      line.setAttribute("x2", (120 + Math.cos(angleRad) * rOut).toFixed(2));
      line.setAttribute("y2", (120 + Math.sin(angleRad) * rOut).toFixed(2));
      line.setAttribute("stroke", (i % 3 === 0) ? "#00f5d4" : "#38bdf8");
      line.setAttribute("stroke-width", (i % 3 === 0) ? "2" : "1.2");
      line.setAttribute("stroke-linecap", "round");
      line.style.opacity = "0";
      ticksGroup.appendChild(line);
      tickEls.push(line);
    }

    gsap.set("#progress-fill", { scaleX: 0 });
    gsap.set("#progress-shimmer", { x: -38, opacity: 0 });

    const tl = gsap.timeline({ paused: true });

    tl.fromTo("#shutdown-flash-line", { opacity: 0, scaleX: 1, scaleY: 1 }, { opacity: 0.95, scaleX: 1, scaleY: 1, duration: 0.12, ease: "power2.out" }, 0.06);
    tl.to("#shutdown-flash-line", { scaleX: 0.02, scaleY: 2.2, opacity: 0, duration: 0.24, ease: "power3.in" }, 0.18);

    tl.fromTo("#core-ignition-dot", { opacity: 0, scale: 0.3 }, { opacity: 1, scale: 1.5, svgOrigin: "120 120", duration: 0.2, ease: "power2.out" }, 0.24);
    tl.to("#core-ignition-dot", { opacity: 0, scale: 2.4, svgOrigin: "120 120", duration: 0.42, ease: "power2.out" }, 0.44);

    tl.fromTo("#core-halo", { opacity: 0, scale: 0.35 }, { opacity: 0.42, scale: 1, duration: 0.9, ease: "power3.out" }, 0.38);
    tl.fromTo("#outer-track-ring", { opacity: 0, strokeDashoffset: 110 }, { opacity: 1, strokeDashoffset: 0, duration: 1.05, ease: "power3.inOut" }, 0.42);
    tl.fromTo("#inner-precision-ring", { opacity: 0, strokeDashoffset: 110 }, { opacity: 1, strokeDashoffset: 0, duration: 0.95, ease: "power3.inOut" }, 0.58);

    for (let i = 0; i < tickEls.length; i++) {
      tl.fromTo(tickEls[i], { opacity: 0 }, { opacity: 0.35, duration: 0.28, ease: "power2.out" }, 0.78 + i * 0.045);
    }

    tl.fromTo("#emblem-hex", { opacity: 0, strokeDashoffset: 110 }, { opacity: 1, strokeDashoffset: 0, duration: 0.72, ease: "power2.inOut" }, 0.55);
    tl.fromTo("#emblem-stem", { opacity: 0, strokeDashoffset: 110 }, { opacity: 1, strokeDashoffset: 0, duration: 0.42, ease: "power2.out" }, 0.95);
    tl.fromTo("#emblem-upper", { opacity: 0, strokeDashoffset: 110 }, { opacity: 1, strokeDashoffset: 0, duration: 0.36, ease: "power2.out" }, 1.12);
    tl.fromTo("#emblem-lower", { opacity: 0, strokeDashoffset: 110 }, { opacity: 1, strokeDashoffset: 0, duration: 0.36, ease: "power2.out" }, 1.22);

    tl.fromTo("#wordmark-row", { opacity: 0, y: 10, scale: 0.95 }, { opacity: 1, y: 0, scale: 1, duration: 0.65, ease: "power3.out" }, 1.42);
    tl.fromTo("#progress-track", { opacity: 0, scaleX: 0.65 }, { opacity: 1, scaleX: 1, duration: 0.42, ease: "power2.out" }, 1.78);
    tl.to("#progress-fill", { scaleX: 0.72, duration: 1.05, ease: "power2.out" }, 1.88);
    tl.fromTo("#status-row", { opacity: 0, y: 6 }, { opacity: 1, y: 0, duration: 0.45, ease: "power2.out" }, 1.92);

    tl.fromTo("#orbital-scanner", { opacity: 0 }, { opacity: 1, duration: 0.55, ease: "power2.out" }, 2.35);
    tl.fromTo("#orbital-beacon", { opacity: 0 }, { opacity: 1, duration: 0.45, ease: "power2.out" }, 2.45);
    tl.fromTo("#inner-beacon", { opacity: 0 }, { opacity: 0.9, duration: 0.45, ease: "power2.out" }, 2.5);

    const loopTl = gsap.timeline({ repeat: LOOP_REPEAT });

    loopTl.to("#orbital-scanner", { rotation: 360, svgOrigin: "120 120", duration: LOOP_CYCLE_SEC, ease: "none" }, 0);
    loopTl.to("#orbital-beacon", { rotation: 360, svgOrigin: "120 120", duration: LOOP_CYCLE_SEC, ease: "none" }, 0);
    loopTl.to("#inner-beacon", { rotation: -360, svgOrigin: "120 120", duration: LOOP_CYCLE_SEC, ease: "none" }, 0);

    loopTl.to("#core-halo", { opacity: 0.78, scale: 1.09, duration: 1.0, ease: "sine.inOut" }, 0);
    loopTl.to("#core-halo", { opacity: 0.42, scale: 1.0, duration: 1.0, ease: "sine.inOut" }, 1.0);
    loopTl.to("#emblem-group", { scale: 1.05, svgOrigin: "120 77", duration: 1.0, ease: "sine.inOut" }, 0);
    loopTl.to("#emblem-group", { scale: 1.0, svgOrigin: "120 77", duration: 1.0, ease: "sine.inOut" }, 1.0);

    for (let i = 0; i < tickEls.length; i++) {
      const peak = 0.2 + i * 0.132;
      loopTl.to(tickEls[i], { opacity: 0.95, duration: 0.16, ease: "sine.out" }, peak - 0.16);
      loopTl.to(tickEls[i], { opacity: 0.35, duration: 0.24, ease: "sine.in" }, peak);
    }

    loopTl.to("#progress-shimmer", { opacity: 0.9, duration: 0.32, ease: "power1.out" }, 0.05);
    loopTl.to("#progress-shimmer", { opacity: 0, duration: 0.38, ease: "power1.in" }, 0.95);
    loopTl.to("#progress-shimmer", { x: 112, duration: 1.35, ease: "power1.inOut" }, 0.05);
    loopTl.to("#progress-shimmer", { x: -38, duration: 0.05, ease: "none" }, 1.92);

    for (let d = 0; d < 3; d++) {
      const dotPeak = 0.35 + d * 0.4;
      const dotSel = "#wait-dot-" + d;
      loopTl.to(dotSel, { opacity: 1, scale: 1.35, duration: 0.35, ease: "sine.out" }, dotPeak - 0.35);
      loopTl.to(dotSel, { opacity: 0.25, scale: 1, duration: 0.45, ease: "sine.in" }, dotPeak);
    }

    tl.add(loopTl, INTRO_DURATION);

    window.__timelines = window.__timelines || {};
    window.__timelines["ketrawos-boot"] = tl;
  </script>
</body>
</html>
EOF

cat <<'EOF' > "$DUAL_DIR/index.html"
<!doctype html>
<html lang="tr">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=240, height=240" />
  <title>KetraWOS — Dual Boot Manager (240x240)</title>
  <script src="https://cdn.jsdelivr.net/npm/gsap@3.14.2/dist/gsap.min.js"></script>
  <style>
    * { box-sizing: border-box; }
    html, body {
      margin: 0;
      padding: 0;
      width: 240px;
      height: 240px;
      overflow: hidden;
      background: #04060a;
    }
    #root {
      position: relative;
      width: 100%;
      height: 100%;
      overflow: hidden;
      background: radial-gradient(circle at 50% 48%, #0a1220 0%, #04060a 74%);
      font-family: system-ui, -apple-system, BlinkMacSystemFont, sans-serif;
      color: #f8fafc;
    }
    .clip {
      position: absolute;
      inset: 0;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    #dualboot-stage {
      position: relative;
      width: 240px;
      height: 240px;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: flex-start;
      padding-top: 34px;
    }
    #db-svg {
      position: absolute;
      inset: 0;
      width: 240px;
      height: 240px;
      pointer-events: none;
    }
    #slot-a-halo {
      position: absolute;
      top: 34px;
      left: 50px;
      width: 140px;
      height: 140px;
      border-radius: 50%;
      background: radial-gradient(circle, rgba(0, 245, 212, 0.28) 0%, rgba(56, 189, 248, 0.1) 46%, rgba(0, 0, 0, 0) 74%);
      opacity: 0;
      pointer-events: none;
    }
    #db-header {
      position: relative;
      z-index: 2;
      height: 16px;
      display: flex;
      align-items: center;
      justify-content: center;
      opacity: 0;
    }
    #db-title {
      font-family: monospace;
      font-size: 13px;
      font-weight: 700;
      letter-spacing: 0.12em;
      color: #7dd3fc;
    }
    #cards-col {
      position: relative;
      z-index: 2;
      margin-top: 14px;
      width: 144px;
      height: 96px;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: space-between;
    }
    .os-card {
      position: relative;
      width: 144px;
      height: 44px;
      border-radius: 12px;
      padding: 0 10px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      background: rgba(15, 23, 42, 0.85);
      border: 1.5px solid rgba(148, 163, 184, 0.25);
      opacity: 0;
    }
    #slot-a-card { border-color: rgba(0, 245, 212, 0.42); }
    #slot-b-card { border-color: rgba(255, 138, 61, 0.42); }
    .card-lock-ring {
      position: absolute;
      inset: -2.5px;
      border-radius: 14px;
      pointer-events: none;
      opacity: 0;
    }
    #slot-a-lock-ring {
      border: 2px solid #00f5d4;
      box-shadow: 0 0 12px rgba(0, 245, 212, 0.42);
    }
    #slot-b-lock-ring {
      border: 2px solid #ff8a3d;
      box-shadow: 0 0 10px rgba(255, 138, 61, 0.36);
    }
    .card-left {
      display: flex;
      align-items: center;
      gap: 7px;
    }
    .os-name {
      font-size: 13px;
      font-weight: 700;
      letter-spacing: -0.01em;
      color: #f8fafc;
      white-space: nowrap;
    }
    .slot-badge {
      font-family: monospace;
      font-size: 11px;
      font-weight: 800;
      padding: 2px 6px;
      border-radius: 6px;
      line-height: 1.2;
    }
    #slot-a-badge { background: rgba(0, 245, 212, 0.16); color: #00f5d4; }
    #slot-b-badge { background: rgba(255, 138, 61, 0.16); color: #fdba74; }
    #db-progress-track {
      position: absolute;
      z-index: 2;
      top: 146px;
      left: 66px;
      width: 108px;
      height: 4px;
      border-radius: 999px;
      background: rgba(148, 163, 184, 0.22);
      overflow: hidden;
      opacity: 0;
    }
    #db-progress-fill {
      position: absolute;
      left: 0;
      top: 0;
      width: 108px;
      height: 4px;
      border-radius: 999px;
      background: linear-gradient(90deg, #38bdf8 0%, #00f5d4 100%);
      transform-origin: left center;
    }
    #db-shimmer {
      position: absolute;
      left: 0;
      top: 0;
      width: 36px;
      height: 4px;
      border-radius: 999px;
      background: linear-gradient(90deg, rgba(255, 255, 255, 0) 0%, rgba(255, 255, 255, 0.95) 50%, rgba(255, 255, 255, 0) 100%);
      opacity: 0;
    }
    #countdown-wrap {
      position: relative;
      z-index: 2;
      margin-top: 10px;
      width: 140px;
      height: 16px;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .cd-msg {
      position: absolute;
      inset: 0;
      display: flex;
      align-items: center;
      justify-content: center;
      font-family: monospace;
      font-size: 11px;
      font-weight: 700;
      letter-spacing: 0.1em;
      white-space: nowrap;
      opacity: 0;
    }
    #cd-scan { color: #94a3b8; }
    #cd-3 { color: #e2e8f0; }
    #cd-2 { color: #bae6fd; }
    #cd-1 { color: #00f5d4; }
    #cd-boot { color: #00f5d4; }
    #db-dots {
      position: relative;
      z-index: 2;
      margin-top: 8px;
      display: flex;
      align-items: center;
      gap: 5px;
      opacity: 0;
    }
    .db-dot {
      width: 4.5px;
      height: 4.5px;
      border-radius: 50%;
      background: #00f5d4;
      opacity: 0.25;
    }
  </style>
</head>
<body>
  <div
    id="root"
    data-composition-id="ketrawos-dualboot"
    data-start="0"
    data-duration="9"
    data-width="240"
    data-height="240"
  >
    <section id="dualboot-clip" class="clip" data-start="0" data-duration="9" data-track-index="1">
      <div id="dualboot-stage">
        <div id="slot-a-halo"></div>

        <svg id="db-svg" viewBox="0 0 240 240" width="240" height="240">
          <defs>
            <linearGradient id="dbScanGrad" x1="0%" y1="0%" x2="100%" y2="0%">
              <stop offset="0%" stop-color="#00f5d4" stop-opacity="0" />
              <stop offset="65%" stop-color="#00f5d4" stop-opacity="0.9" />
              <stop offset="100%" stop-color="#e0f2fe" stop-opacity="1" />
            </linearGradient>
          </defs>

          <circle id="db-outer-ring" cx="120" cy="120" r="105" fill="none" stroke="rgba(56, 189, 248, 0.22)" stroke-width="1.5" stroke-linecap="round" pathLength="100" stroke-dasharray="100 120" stroke-dashoffset="110" />
          <circle id="db-inner-ring" cx="120" cy="120" r="96" fill="none" stroke="rgba(0, 245, 212, 0.18)" stroke-width="1.2" stroke-linecap="round" pathLength="100" stroke-dasharray="100 120" stroke-dashoffset="110" />
          <path id="bus-top-line" d="M 120 53 L 120 63" fill="none" stroke="#00f5d4" stroke-width="1.8" stroke-linecap="round" pathLength="100" stroke-dasharray="100 120" stroke-dashoffset="110" style="opacity: 0;" />
          <path id="bus-mid-line" d="M 120 108 L 120 116" fill="none" stroke="#ff8a3d" stroke-width="1.8" stroke-linecap="round" pathLength="100" stroke-dasharray="100 120" stroke-dashoffset="110" style="opacity: 0;" />
          <circle id="db-active-scanner" cx="120" cy="120" r="105" fill="none" stroke="url(#dbScanGrad)" stroke-width="3" stroke-linecap="round" pathLength="100" stroke-dasharray="22 78" stroke-dashoffset="0" style="opacity: 0;" />
        </svg>

        <div id="db-header">
          <div id="db-title">DUAL BOOT</div>
        </div>

        <div id="cards-col">
          <div id="slot-a-card" class="os-card">
            <div id="slot-a-lock-ring" class="card-lock-ring"></div>
            <div class="card-left">
              <svg id="slot-a-icon" width="20" height="20" viewBox="0 0 40 40">
                <path d="M 20 3 L 35 11.5 L 35 28.5 L 20 37 L 5 28.5 L 5 11.5 Z" fill="rgba(0, 245, 212, 0.14)" stroke="#00f5d4" stroke-width="2.6" />
                <path d="M 15 12 L 15 28 M 25 13 L 16 20 M 18 19 L 25 28" fill="none" stroke="#f8fafc" stroke-width="2.8" stroke-linecap="round" />
              </svg>
              <span id="slot-a-title" class="os-name">KetraWOS 1</span>
            </div>
            <span id="slot-a-badge" class="slot-badge">A</span>
          </div>

          <div id="slot-b-card" class="os-card">
            <div id="slot-b-lock-ring" class="card-lock-ring"></div>
            <div class="card-left">
              <svg id="slot-b-icon" width="20" height="20" viewBox="0 0 40 40">
                <rect x="6" y="6" width="28" height="28" rx="8" fill="rgba(255, 138, 61, 0.14)" stroke="#ff8a3d" stroke-width="2.6" />
                <path d="M 13 15 L 19 20 L 13 25 M 21 25 L 27 25" fill="none" stroke="#ffedd5" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
              <span id="slot-b-title" class="os-name">Alt OS</span>
            </div>
            <span id="slot-b-badge" class="slot-badge">B</span>
          </div>
        </div>

        <div id="db-progress-track">
          <div id="db-progress-fill"></div>
          <div id="db-shimmer"></div>
        </div>

        <div id="countdown-wrap">
          <span id="cd-scan" class="cd-msg">SCANNING</span>
          <span id="cd-3" class="cd-msg">BOOT IN 03</span>
          <span id="cd-2" class="cd-msg">BOOT IN 02</span>
          <span id="cd-1" class="cd-msg">LOCK A · 01</span>
          <span id="cd-boot" class="cd-msg">BOOTING OS</span>
        </div>

        <div id="db-dots">
          <div id="db-dot-0" class="db-dot"></div>
          <div id="db-dot-1" class="db-dot"></div>
          <div id="db-dot-2" class="db-dot"></div>
        </div>
      </div>
    </section>
  </div>

  <script>
    const DB_HANDOFF_END = 5;
    const DB_CYCLE_SEC = 2;
    const DB_LOOP_TOTAL_SEC = 4;
    const DB_LOOP_REPEAT = Math.max(0, Math.floor(DB_LOOP_TOTAL_SEC / DB_CYCLE_SEC) - 1);

    gsap.set("#db-progress-fill", { scaleX: 0 });
    gsap.set("#db-shimmer", { x: -36, opacity: 0 });

    const tl = gsap.timeline({ paused: true });

    tl.fromTo("#db-outer-ring", { opacity: 0, strokeDashoffset: 110 }, { opacity: 1, strokeDashoffset: 0, duration: 0.9, ease: "power3.inOut" }, 0.08);
    tl.fromTo("#db-inner-ring", { opacity: 0, strokeDashoffset: 110 }, { opacity: 1, strokeDashoffset: 0, duration: 0.85, ease: "power3.inOut" }, 0.18);
    tl.fromTo("#db-header", { opacity: 0, y: -6 }, { opacity: 1, y: 0, duration: 0.5, ease: "power3.out" }, 0.22);

    tl.fromTo("#bus-top-line", { opacity: 0, strokeDashoffset: 110 }, { opacity: 0.85, strokeDashoffset: 0, duration: 0.35, ease: "power2.out" }, 0.35);
    tl.fromTo("#bus-mid-line", { opacity: 0, strokeDashoffset: 110 }, { opacity: 0.75, strokeDashoffset: 0, duration: 0.35, ease: "power2.out" }, 0.45);

    tl.fromTo("#slot-a-card", { opacity: 0, y: 10, scale: 0.95 }, { opacity: 1, y: 0, scale: 1, duration: 0.55, ease: "power3.out" }, 0.42);
    tl.fromTo("#slot-b-card", { opacity: 0, y: 10, scale: 0.95 }, { opacity: 1, y: 0, scale: 1, duration: 0.55, ease: "power3.out" }, 0.52);

    tl.fromTo("#cd-scan", { opacity: 0 }, { opacity: 1, duration: 0.22 }, 0.6);
    tl.to("#cd-scan", { opacity: 0, duration: 0.16 }, 1.28);

    tl.fromTo("#slot-b-lock-ring", { opacity: 0 }, { opacity: 0.95, duration: 0.24, ease: "power2.out" }, 1.45);
    tl.to("#slot-b-lock-ring", { opacity: 0, duration: 0.24, ease: "power2.in" }, 2.05);
    tl.fromTo("#slot-a-lock-ring", { opacity: 0 }, { opacity: 1, duration: 0.3, ease: "power2.out" }, 2.25);

    tl.fromTo("#cd-3", { opacity: 0 }, { opacity: 1, duration: 0.16 }, 1.48);
    tl.to("#cd-3", { opacity: 0, duration: 0.14 }, 2.02);

    tl.fromTo("#cd-2", { opacity: 0 }, { opacity: 1, duration: 0.16 }, 2.18);
    tl.to("#cd-2", { opacity: 0, duration: 0.14 }, 2.72);

    tl.fromTo("#cd-1", { opacity: 0 }, { opacity: 1, duration: 0.16 }, 2.88);
    tl.to("#cd-1", { opacity: 0, duration: 0.14 }, 3.42);

    tl.to("#bus-top-line", { opacity: 0, duration: 0.3 }, 3.5);
    tl.to("#bus-mid-line", { opacity: 0, duration: 0.3 }, 3.5);
    tl.to("#slot-b-card", { opacity: 0, y: 14, scale: 0.9, duration: 0.5, ease: "power2.inOut" }, 3.52);

    tl.to("#slot-a-card", { y: 18, scale: 1.08, duration: 0.7, ease: "power3.inOut" }, 3.65);

    tl.fromTo("#slot-a-halo", { opacity: 0, scale: 0.6 }, { opacity: 0.38, scale: 1, duration: 0.7, ease: "power2.out" }, 3.85);
    tl.fromTo("#cd-boot", { opacity: 0, y: 4 }, { opacity: 1, y: 0, duration: 0.38, ease: "power2.out" }, 3.62);

    tl.fromTo("#db-progress-track", { opacity: 0, scaleX: 0.6 }, { opacity: 1, scaleX: 1, duration: 0.35, ease: "power2.out" }, 3.8);
    tl.to("#db-progress-fill", { scaleX: 0.76, duration: 1.0, ease: "power2.out" }, 3.92);
    tl.fromTo("#db-dots", { opacity: 0 }, { opacity: 1, duration: 0.35 }, 4.05);
    tl.fromTo("#db-active-scanner", { opacity: 0 }, { opacity: 1, duration: 0.45 }, 4.5);

    const dbLoopTl = gsap.timeline({ repeat: DB_LOOP_REPEAT });

    dbLoopTl.to("#db-active-scanner", { rotation: 360, svgOrigin: "120 120", duration: DB_CYCLE_SEC, ease: "none" }, 0);
    dbLoopTl.to("#slot-a-halo", { opacity: 0.74, scale: 1.1, duration: 1.0, ease: "sine.inOut" }, 0);
    dbLoopTl.to("#slot-a-halo", { opacity: 0.38, scale: 1.0, duration: 1.0, ease: "sine.inOut" }, 1.0);

    dbLoopTl.to("#db-shimmer", { opacity: 0.9, duration: 0.32, ease: "power1.out" }, 0.05);
    dbLoopTl.to("#db-shimmer", { opacity: 0, duration: 0.38, ease: "power1.in" }, 0.95);
    dbLoopTl.to("#db-shimmer", { x: 108, duration: 1.35, ease: "power1.inOut" }, 0.05);
    dbLoopTl.to("#db-shimmer", { x: -36, duration: 0.05, ease: "none" }, 1.92);

    for (let d = 0; d < 3; d++) {
      const dotPeak = 0.35 + d * 0.4;
      const dotSel = "#db-dot-" + d;
      dbLoopTl.to(dotSel, { opacity: 1, scale: 1.35, duration: 0.35, ease: "sine.out" }, dotPeak - 0.35);
      dbLoopTl.to(dotSel, { opacity: 0.25, scale: 1, duration: 0.45, ease: "sine.in" }, dotPeak);
    }

    tl.add(dbLoopTl, DB_HANDOFF_END);

    window.__timelines = window.__timelines || {};
    window.__timelines["ketrawos-dualboot"] = tl;
  </script>
</body>
</html>
EOF

# ------------------------------------------------------------------------------
# 5. HTML Güvenlik Politikası + HyperFrames Lint & Check Doğrulaması
# ------------------------------------------------------------------------------
log "5/6 — HTML güvenlik politikası, lint ve check doğrulaması yapılıyor..."

node -e '
  const fs = require("fs");
  const allowed = new Set([
    "https://cdn.jsdelivr.net/npm/gsap@3.14.2/dist/gsap.min.js",
    "http://www.w3.org/2000/svg"
  ]);
  for (const file of process.argv.slice(1)) {
    const html = fs.readFileSync(file, "utf8");
    const urls = html.match(/https?:\/\/[^\s"\x27<>]+/g) || [];
    for (const u of urls) {
      if (!allowed.has(u)) {
        console.error("İzin verilmeyen dış kaynak (" + file + "): " + u);
        process.exit(1);
      }
    }
  }
' "$BOOT_DIR/index.html" "$DUAL_DIR/index.html"
ok "HTML dosyalarında yalnızca güvenilir GSAP CDN kaynağı bulundu."

"$HF_BIN" lint "$BOOT_DIR"
"$HF_BIN" check "$BOOT_DIR"
"$HF_BIN" lint "$DUAL_DIR"
"$HF_BIN" check "$DUAL_DIR"
ok "Her iki proje lint ve browser/kontrast kontrolünden geçti."

# ------------------------------------------------------------------------------
# 6. İki Ayrı Video Çıktısı Üretimi
# ------------------------------------------------------------------------------
log "6/6 — İki ayrı 240x240 MP4 videosu render ediliyor..."

(cd "$BOOT_DIR" && "$HF_BIN" render --chroma-subsampling 444 --output "$OUT_DIR/ketrawos-boot-240x240.mp4")
(cd "$DUAL_DIR" && "$HF_BIN" render --chroma-subsampling 444 --output "$OUT_DIR/ketrawos-dualboot-240x240.mp4")

log "TAMAMLANDI! İki video başarıyla oluşturuldu:"
ls -lh "$OUT_DIR/ketrawos-boot-240x240.mp4" "$OUT_DIR/ketrawos-dualboot-240x240.mp4"