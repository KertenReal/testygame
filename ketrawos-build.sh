#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# KetraWOS 1 — Kristal <-> Saat Dönüşüm Videosu (10s Loop, 240x240)
# ==============================================================================

WORKDIR="$(pwd)/ketrawos-workspace"
MORPH_DIR="$WORKDIR/projects/ketrawos-logo-morph"
FONT_DIR="$MORPH_DIR/assets/fonts"
OUT_DIR="$WORKDIR/output"
HF_BIN="$WORKDIR/node_modules/.bin/hyperframes"

log()  { printf "\n\033[1;36m[KetraWOS]\033[0m %s\n" "$1"; }
ok()   { printf "\033[1;32m[OK]\033[0m %s\n" "$1"; }
fail() { printf "\033[1;31m[HATA]\033[0m %s\n" "$1" >&2; exit 1; }

# 1. Ön Gereksinim Kontrolü
log "1/6 — Sistem gereksinimleri kontrol ediliyor..."
command -v node    >/dev/null 2>&1 || fail "Node.js bulunamadı (22+ gerekli)."
command -v npm     >/dev/null 2>&1 || fail "npm bulunamadı."
command -v ffmpeg  >/dev/null 2>&1 || fail "FFmpeg bulunamadı."
command -v ffprobe >/dev/null 2>&1 || fail "ffprobe bulunamadı."

NODE_MAJOR="$(node -p "process.versions.node.split('.')[0]")"
if [ "$NODE_MAJOR" -lt 22 ]; then
  fail "Node.js 22+ gerekli (mevcut: v$(node -v))."
fi
ok "Node.js $(node -v), FFmpeg ve FFprobe hazır."

# 2. HyperFrames Kurulumu
log "2/6 — HyperFrames kuruluyor ($WORKDIR)..."
mkdir -p "$WORKDIR" "$MORPH_DIR" "$FONT_DIR" "$OUT_DIR"
cd "$WORKDIR"

if [ ! -f "$WORKDIR/package.json" ]; then
  npm init -y >/dev/null
fi

npm install --no-fund hyperframes
[ -x "$HF_BIN" ] || fail "HyperFrames kurulamadı: $HF_BIN"
ok "HyperFrames kuruldu."

# 3. Güvenlik, Ortam ve Lexend Font Doğrulaması
log "3/6 — Güvenlik, ortam ve Lexend font doğrulaması yapılıyor..."
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
  for (const req of ["ffmpeg", "ffprobe", "chrome"]) {
    const found = checks.find((c) => String(c.name || "").toLowerCase().includes(req));
    if (!found || !found.ok) {
      console.error("Gerekli bileşen hazır değil:", req, found || "bulunamadı");
      process.exit(1);
    }
  }
' "$DOCTOR_JSON"
ok "FFmpeg, FFprobe ve sandboxed Chrome doğrulandı."

node -e '
  const fs = require("fs");
  const path = require("path");
  const { createHash } = require("crypto");
  const fontOut = process.argv[1];

  (async () => {
    const gsapUrl = "https://cdn.jsdelivr.net/npm/gsap@3.14.2/dist/gsap.min.js";
    const gRes = await fetch(gsapUrl);
    if (!gRes.ok) throw new Error("GSAP HTTP " + gRes.status);
    const gBody = await gRes.text();
    if (!gBody.includes("GSAP") && !gBody.includes("GreenSock")) {
      throw new Error("Beklenmeyen GSAP içeriği");
    }
    console.log("GSAP SHA-256: " + createHash("sha256").update(gBody).digest("hex"));

    const cssUrl = "https://fonts.googleapis.com/css2?family=Lexend:wght@700&display=swap";
    const cRes = await fetch(cssUrl, {
      headers: {
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
      }
    });
    if (!cRes.ok) throw new Error("Lexend CSS HTTP " + cRes.status);
    const cssText = await cRes.text();
    const matches = [...cssText.matchAll(/url\((https:\/\/fonts\.gstatic\.com\/[^)]+\.woff2)\)/g)];
    if (!matches.length) throw new Error("Lexend woff2 adresi bulunamadı");
    const fontUrl = matches[matches.length - 1][1];

    const fRes = await fetch(fontUrl);
    if (!fRes.ok) throw new Error("Lexend WOFF2 HTTP " + fRes.status);
    const buf = Buffer.from(await fRes.arrayBuffer());
    if (buf.subarray(0, 4).toString("ascii") !== "wOF2") {
      throw new Error("Geçersiz WOFF2 font başlığı");
    }
    fs.mkdirSync(path.dirname(fontOut), { recursive: true });
    fs.writeFileSync(fontOut, buf);
    console.log("Lexend 700 woff2 doğrulandı (" + buf.length + " bayt).");
  })().catch((err) => {
    console.error("Varlık doğrulama hatası:", err.message);
    process.exit(1);
  });
' "$FONT_DIR/lexend.woff2"
ok "GSAP ve Lexend fontu güvenle doğrulandı."

# 4. Logo Dönüşüm Kompozisyonunu Oluşturma (10 sn)
log "4/6 — KetraWOS Logo Dönüşüm projesi (10s) oluşturuluyor..."

cat <<'EOF' > "$MORPH_DIR/index.html"
<!doctype html>
<html lang="tr">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=240, height=240" />
  <title>KetraWOS 1 — Logo Morph Loop 10s (240x240)</title>
  <script src="https://cdn.jsdelivr.net/npm/gsap@3.14.2/dist/gsap.min.js"></script>
  <style>
    @font-face {
      font-family: "Lexend";
      src: url("assets/fonts/lexend.woff2") format("woff2");
      font-weight: 700;
      font-style: normal;
    }
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
      font-family: "Lexend", sans-serif;
    }
    .clip {
      position: absolute;
      inset: 0;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    #morph-stage {
      position: relative;
      width: 240px;
      height: 240px;
    }
    #logo-svg {
      position: absolute;
      inset: 0;
      width: 240px;
      height: 240px;
      pointer-events: none;
    }
    #brand-row {
      position: absolute;
      top: 201px;
      left: 0;
      width: 240px;
      height: 20px;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 5px;
      pointer-events: none;
    }
    #ketra-word {
      display: inline-block;
      font-family: "Lexend", sans-serif;
      font-weight: 700;
      font-size: 13px;
      line-height: 1;
      letter-spacing: -0.01em;
      color: #ffffff;
      opacity: 0;
    }
    #ver-badge {
      display: inline-block;
      width: 10px;
      font-family: "Lexend", sans-serif;
      font-weight: 700;
      font-size: 13px;
      line-height: 1;
      text-align: center;
      color: #ffffff;
      opacity: 0;
    }
  </style>
</head>
<body>
  <!-- Uzun bekleme loopu için SPIN_LOOPS değerini artırıp data-duration = 7 + SPIN_LOOPS * 1.5 yapabilirsin -->
  <div
    id="root"
    data-composition-id="ketrawos-logo-morph"
    data-start="0"
    data-duration="10"
    data-width="240"
    data-height="240"
  >
    <section id="morph-clip" class="clip" data-start="0" data-duration="10" data-track-index="1">
      <div id="morph-stage">
        <svg id="logo-svg" viewBox="0 0 240 240" width="240" height="240">
          <!-- Üst Kristal -> Saniye Dikdörtgeni (12 yönü) -->
          <g id="hand-top-group">
            <path id="top-dark" d="M 98.0,100.0 L 98.0,60.0 L 120.0,38.0 L 142.0,60.0 L 142.0,100.0 Z" fill="#8C0020" />
            <path id="top-light" d="M 104.0,94.0 L 104.0,63.0 L 120.0,44.0 L 136.0,63.0 L 136.0,94.0 Z" fill="#FF0055" />
          </g>

          <!-- Sol Alt Kristal -> Akrep Dikdörtgeni (8 yönü) -->
          <g id="hand-lb-group">
            <path id="lb-dark" d="M 125.8,136.1 L 75.5,165.1 L 45.5,157.0 L 53.5,127.0 L 103.8,98.0 Z" fill="#8A5A00" />
            <path id="lb-light" d="M 117.6,133.8 L 75.2,158.3 L 50.7,154.0 L 59.1,130.7 L 101.6,106.2 Z" fill="#DD9500" />
          </g>

          <!-- Sağ Alt Kristal -> Yelkovan Dikdörtgeni (4 yönü) -->
          <g id="hand-rb-group">
            <path id="rb-dark" d="M 136.2,98.0 L 186.4,127.0 L 194.5,157.0 L 164.4,165.1 L 114.2,136.1 Z" fill="#008CAA" />
            <path id="rb-light" d="M 138.4,106.2 L 180.8,130.7 L 189.3,154.0 L 164.8,158.3 L 122.4,133.8 Z" fill="#82E9FF" />
          </g>

          <!-- Merkezi Kırmızı Daire (Küçülür: 34.6/28.4 -> 21.5/17.5) -->
          <circle id="center-dot-outer" cx="120.0" cy="114.0" r="34.6" fill="#950000" />
          <circle id="center-dot-inner" cx="120.0" cy="114.0" r="28.4" fill="#E00000" />
        </svg>

        <div id="brand-row">
          <span id="ketra-word">KetraWOS</span>
          <span id="ver-badge">1</span>
        </div>
      </div>
    </section>
  </div>

  <script>
    const SPIN_LOOPS = 2; // 2 tur x 1.5s = 3.0s tam hızlı akış -> toplam 10.0s

    const SHAPES = {
      topDarkOrig:  "M 98.0,100.0 L 98.0,60.0 L 120.0,38.0 L 142.0,60.0 L 142.0,100.0 Z",
      topDarkHand:  "M 117.0,104.0 L 117.0,32.0 L 120.0,32.0 L 123.0,32.0 L 123.0,104.0 Z",
      topLightOrig: "M 104.0,94.0 L 104.0,63.0 L 120.0,44.0 L 136.0,63.0 L 136.0,94.0 Z",
      topLightHand: "M 118.3,104.0 L 118.3,34.2 L 120.0,34.2 L 121.7,34.2 L 121.7,104.0 Z",

      lbDarkOrig:   "M 125.8,136.1 L 75.5,165.1 L 45.5,157.0 L 53.5,127.0 L 103.8,98.0 Z",
      lbDarkHand:   "M 112.8,121.6 L 73.0,144.6 L 71.5,142.0 L 70.0,139.4 L 109.8,116.4 Z",
      lbLightOrig:  "M 117.6,133.8 L 75.2,158.3 L 50.7,154.0 L 59.1,130.7 L 101.6,106.2 Z",
      lbLightHand:  "M 112.2,120.5 L 74.3,142.4 L 73.4,140.9 L 72.6,139.4 L 110.5,117.5 Z",

      rbDarkOrig:   "M 136.2,98.0 L 186.4,127.0 L 194.5,157.0 L 164.4,165.1 L 114.2,136.1 Z",
      rbDarkHand:   "M 130.2,116.4 L 183.9,147.4 L 182.4,150.0 L 180.9,152.6 L 127.2,121.6 Z",
      rbLightOrig:  "M 138.4,106.2 L 180.8,130.7 L 189.3,154.0 L 164.8,158.3 L 122.4,133.8 Z",
      rbLightHand:  "M 129.5,117.5 L 181.3,147.4 L 180.4,148.9 L 179.6,150.4 L 127.8,120.5 Z"
    };

    gsap.set("#ketra-word", { x: 7.5, y: -97, scale: 0.5 });
    gsap.set("#ver-badge", { scale: 0.6 });

    const tl = gsap.timeline({ paused: true });

    // 1) 0.00s -> 1.35s: Kristaller eşit kalınlıkta dikdörtgene dönüşür & daire küçülür
    tl.fromTo("#top-dark",  { attr: { d: SHAPES.topDarkOrig } },  { attr: { d: SHAPES.topDarkHand },  duration: 1.35, ease: "power2.inOut" }, 0);
    tl.fromTo("#top-light", { attr: { d: SHAPES.topLightOrig } }, { attr: { d: SHAPES.topLightHand }, duration: 1.35, ease: "power2.inOut" }, 0);
    tl.fromTo("#lb-dark",   { attr: { d: SHAPES.lbDarkOrig } },   { attr: { d: SHAPES.lbDarkHand },   duration: 1.35, ease: "power2.inOut" }, 0);
    tl.fromTo("#lb-light",  { attr: { d: SHAPES.lbLightOrig } },  { attr: { d: SHAPES.lbLightHand },  duration: 1.35, ease: "power2.inOut" }, 0);
    tl.fromTo("#rb-dark",   { attr: { d: SHAPES.rbDarkOrig } },   { attr: { d: SHAPES.rbDarkHand },   duration: 1.35, ease: "power2.inOut" }, 0);
    tl.fromTo("#rb-light",  { attr: { d: SHAPES.rbLightOrig } },  { attr: { d: SHAPES.rbLightHand },  duration: 1.35, ease: "power2.inOut" }, 0);

    tl.fromTo("#center-dot-outer", { attr: { r: 34.6 } }, { attr: { r: 21.5 }, duration: 1.35, ease: "power2.inOut" }, 0);
    tl.fromTo("#center-dot-inner", { attr: { r: 28.4 } }, { attr: { r: 17.5 }, duration: 1.35, ease: "power2.inOut" }, 0);

    // 1b) Dairede %75 görünür olduktan sonra saatin aşağısına 2x büyüyerek iner, sonra yanında 1 belirir
    tl.to("#ketra-word", { opacity: 0.75, duration: 0.75, ease: "power2.out" }, 0.1);
    tl.to("#ketra-word", { opacity: 1, x: 0, y: 0, scale: 1, duration: 0.6, ease: "power3.inOut" }, 0.88);
    tl.fromTo("#ver-badge", { opacity: 0, scale: 0.6 }, { opacity: 1, scale: 1, duration: 0.3, ease: "back.out(1.6)" }, 1.45);

    // 2) 1.80s -> 3.30s: Yüksek hızlı saat akışı hızlanması (tepe hız: 1920°/s = 5.33 tur/sn)
    tl.to("#hand-top-group", { rotation: 1440, svgOrigin: "120 114", duration: 1.5, ease: "power1.in" }, 1.8);
    tl.to("#hand-rb-group",  { rotation: 720,  svgOrigin: "120 114", duration: 1.5, ease: "power1.in" }, 1.8);
    tl.to("#hand-lb-group",  { rotation: 180,  svgOrigin: "120 114", duration: 1.5, ease: "power1.in" }, 1.8);

    // 3) Tam hızda kesintisiz akış (SPIN_LOOPS x 1.50s)
    let tCursor = 3.3;
    let aTop = 1440;
    let aRb  = 720;
    let aLb  = 180;

    for (let k = 0; k < SPIN_LOOPS; k++) {
      aTop += 2880;
      aRb  += 1440;
      aLb  += 360;
      tl.to("#hand-top-group", { rotation: aTop, svgOrigin: "120 114", duration: 1.5, ease: "none" }, tCursor);
      tl.to("#hand-rb-group",  { rotation: aRb,  svgOrigin: "120 114", duration: 1.5, ease: "none" }, tCursor);
      tl.to("#hand-lb-group",  { rotation: aLb,  svgOrigin: "120 114", duration: 1.5, ease: "none" }, tCursor);
      tCursor += 1.5;
    }

    // 4) 2.25s boyunca gitgide yavaşlama ve tam kristal yerlerine oturma (360° tam katı)
    aTop += 1440;
    aRb  += 720;
    aLb  += 180;
    tl.to("#hand-top-group", { rotation: aTop, svgOrigin: "120 114", duration: 2.25, ease: "power2.out" }, tCursor);
    tl.to("#hand-rb-group",  { rotation: aRb,  svgOrigin: "120 114", duration: 2.25, ease: "power2.out" }, tCursor);
    tl.to("#hand-lb-group",  { rotation: aLb,  svgOrigin: "120 114", duration: 2.25, ease: "power2.out" }, tCursor);
    tCursor += 2.25;

    // 5) 8.60s -> 9.95s: Tam tersi — 1 kaybolur -> KetraWOS küçülüp daireye döner -> kristaller ve daire eski haline büyür
    const revTextStart = tCursor + 0.05;
    tl.to("#ver-badge", { opacity: 0, scale: 0.6, duration: 0.25, ease: "power2.in" }, revTextStart);
    tl.to("#ketra-word", { opacity: 0.75, x: 7.5, y: -97, scale: 0.5, duration: 0.55, ease: "power3.inOut" }, revTextStart + 0.2);
    tl.to("#ketra-word", { opacity: 0, duration: 0.54, ease: "power2.in" }, revTextStart + 0.78);

    const revShapeStart = revTextStart + 0.3;
    tl.to("#top-dark",  { attr: { d: SHAPES.topDarkOrig },  duration: 1.05, ease: "power2.inOut" }, revShapeStart);
    tl.to("#top-light", { attr: { d: SHAPES.topLightOrig }, duration: 1.05, ease: "power2.inOut" }, revShapeStart);
    tl.to("#lb-dark",   { attr: { d: SHAPES.lbDarkOrig },   duration: 1.05, ease: "power2.inOut" }, revShapeStart);
    tl.to("#lb-light",  { attr: { d: SHAPES.lbLightOrig },  duration: 1.05, ease: "power2.inOut" }, revShapeStart);
    tl.to("#rb-dark",   { attr: { d: SHAPES.rbDarkOrig },   duration: 1.05, ease: "power2.inOut" }, revShapeStart);
    tl.to("#rb-light",  { attr: { d: SHAPES.rbLightOrig },  duration: 1.05, ease: "power2.inOut" }, revShapeStart);

    tl.to("#center-dot-outer", { attr: { r: 34.6 }, duration: 1.05, ease: "power2.inOut" }, revShapeStart);
    tl.to("#center-dot-inner", { attr: { r: 28.4 }, duration: 1.05, ease: "power2.inOut" }, revShapeStart);

    window.__timelines = window.__timelines || {};
    window.__timelines["ketrawos-logo-morph"] = tl;
  </script>
</body>
</html>
EOF

# 5. HTML Güvenlik Politikası + HyperFrames Lint & Check
log "5/6 — HTML güvenlik politikası, lint ve check doğrulaması yapılıyor..."
node -e '
  const fs = require("fs");
  const allowed = new Set([
    "https://cdn.jsdelivr.net/npm/gsap@3.14.2/dist/gsap.min.js",
    "http://www.w3.org/2000/svg"
  ]);
  const html = fs.readFileSync(process.argv[1], "utf8");
  const urls = html.match(/https?:\/\/[^\s"\x27<>]+/g) || [];
  for (const u of urls) {
    if (!allowed.has(u)) {
      console.error("İzin verilmeyen dış kaynak:", u);
      process.exit(1);
    }
  }
' "$MORPH_DIR/index.html"
ok "HTML dış kaynak politikası doğrulandı."

"$HF_BIN" lint "$MORPH_DIR"
"$HF_BIN" check "$MORPH_DIR"
ok "Lint ve browser/kontrast kontrolü geçti."

# 6. 240x240 MP4 Render
log "6/6 — KetraWOS Logo Dönüşüm videosu (10s) render ediliyor..."
"$HF_BIN" render "$MORPH_DIR" --fps 30 --output "$OUT_DIR/ketrawos-logo-morph-240x240.mp4"

log "TAMAMLANDI! Video başarıyla oluşturuldu:"
ls -lh "$OUT_DIR/ketrawos-logo-morph-240x240.mp4"
