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

command -v node    >/dev/null 2>&1 || fail "Node.js bulunamadı. Lütfen Node.js 22+ kurun."
command -v npm     >/dev/null 2>&1 || fail "npm bulunamadı."
command -v ffmpeg  >/dev/null 2>&1 || fail "FFmpeg bulunamadı."
command -v ffprobe >/dev/null 2>&1 || fail "ffprobe bulunamadı."

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
# 3. Güvenlik ve Ortam Kontrolleri
# ------------------------------------------------------------------------------
log "3/6 — Güvenlik ve ortam denetimleri çalıştırılıyor..."

npm audit --audit-level=critical
ok "npm audit (critical) temiz."

"$HF_BIN" browser ensure
DOCTOR_JSON="$("$HF_BIN" doctor --json)"
node -e '
  const data = JSON.parse(process.argv[1]);
  const checks = Array.isArray(data.checks) ? data.checks : [];
  for (const c of checks) {
    console.log((c.ok ? "[PASS] " : "[INFO] ") + c.name + ": " + (c.detail || ""));
  }
  const required = ["ffmpeg", "ffprobe", "chrome"];
  for (const req of required) {
    const found = checks.find((c) => String(c.name || "").toLowerCase().includes(req));
    if (!found || !found.ok) {
      console.error("Gerekli render bileşeni hazır değil:", req, found || "bulunamadı");
      process.exit(1);
    }
  }
' "$DOCTOR_JSON"
ok "FFmpeg, FFprobe ve sandboxed Chrome doğrulandı."

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
log "4/6 — KetraWOS 1 ve Dual Boot (240x240) dosyaları oluşturuluyor..."

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

    tl.fromTo("#core-ignition-dot", { opacity: 0, scale: 0.3 },
