#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# KetraWOS 1 — Tüm 3 Videoyu Üreten Birleşik HyperFrames Betiği (240x240, 60fps)
# Çıktılar:
#   1) ketrawos-logo-morph-240x240.mp4     (10.0s — Kristal <-> Saat Döngüsü)
#   2) ketrawos-dualboot-ketra-240x240.mp4 (11.0s — Dual Boot + Kristal -> 1. Animasyon)
#   3) ketrawos-dualboot-tcl-240x240.mp4   ( 1.7s — Dual Boot: Kısa TCL)
# ==============================================================================

WORKDIR="$(pwd)/ketrawos-workspace"
MORPH_DIR="$WORKDIR/projects/ketrawos-logo-morph"
KETRA_DIR="$WORKDIR/projects/ketrawos-dualboot-ketra"
TCL_DIR="$WORKDIR/projects/ketrawos-dualboot-tcl"
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
mkdir -p "$WORKDIR" "$MORPH_DIR/assets/fonts" "$KETRA_DIR/assets/fonts" "$TCL_DIR/assets/fonts" "$OUT_DIR"
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
  const targets = process.argv.slice(1);

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
    for (const out of targets) {
      fs.mkdirSync(path.dirname(out), { recursive: true });
      fs.writeFileSync(out, buf);
    }
    console.log("Lexend 700 woff2 doğrulandı (" + buf.length + " bayt).");
  })().catch((err) => {
    console.error("Varlık doğrulama hatası:", err.message);
    process.exit(1);
  });
' "$MORPH_DIR/assets/fonts/lexend.woff2" "$KETRA_DIR/assets/fonts/lexend.woff2" "$TCL_DIR/assets/fonts/lexend.woff2"
ok "GSAP ve Lexend fontu güvenle doğrulandı."

# 4. Tüm 3 Kompozisyon Dosyasını Oluşturma
log "4/6 — 3 video projesi oluşturuluyor..."

# --- PROJE 1: Logo Dönüşüm Döngüsü (10s) ---
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
    html, body { margin: 0; padding: 0; width: 240px; height: 240px; overflow: hidden; background: #000000; }
    #root { position: relative; width: 100%; height: 100%; overflow: hidden; background: #000000; font-family: "Lexend", sans-serif; }
    .clip { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; }
    #morph-stage { position: relative; width: 240px; height: 240px; }
    #logo-svg { position: absolute; inset: 0; width: 240px; height: 240px; pointer-events: none; }
    #brand-row { position: absolute; top: 201px; left: 0; width: 240px; height: 20px; display: flex; align-items: center; justify-content: center; gap: 5px; pointer-events: none; }
    #ketra-word { display: inline-block; font-family: "Lexend", sans-serif; font-weight: 700; font-size: 13px; line-height: 1; letter-spacing: -0.01em; color: #ffffff; opacity: 0; }
    #ver-badge { display: inline-block; width: 10px; font-family: "Lexend", sans-serif; font-weight: 700; font-size: 13px; line-height: 1; text-align: center; color: #ffffff; opacity: 0; }
  </style>
</head>
<body>
  <div id="root" data-composition-id="ketrawos-logo-morph" data-start="0" data-duration="10" data-width="240" data-height="240">
    <section id="morph-clip" class="clip" data-start="0" data-duration="10" data-track-index="1">
      <div id="morph-stage">
        <svg id="logo-svg" viewBox="0 0 240 240" width="240" height="240">
          <g id="hand-top-group">
            <path id="top-dark" d="M 98.0,100.0 L 98.0,60.0 L 120.0,38.0 L 142.0,60.0 L 142.0,100.0 Z" fill="#8C0020" />
            <path id="top-light" d="M 104.0,94.0 L 104.0,63.0 L 120.0,44.0 L 136.0,63.0 L 136.0,94.0 Z" fill="#FF0055" />
          </g>
          <g id="hand-lb-group">
            <path id="lb-dark" d="M 125.8,136.1 L 75.5,165.1 L 45.5,157.0 L 53.5,127.0 L 103.8,98.0 Z" fill="#8A5A00" />
            <path id="lb-light" d="M 117.6,133.8 L 75.2,158.3 L 50.7,154.0 L 59.1,130.7 L 101.6,106.2 Z" fill="#DD9500" />
          </g>
          <g id="hand-rb-group">
            <path id="rb-dark" d="M 136.2,98.0 L 186.4,127.0 L 194.5,157.0 L 164.4,165.1 L 114.2,136.1 Z" fill="#008CAA" />
            <path id="rb-light" d="M 138.4,106.2 L 180.8,130.7 L 189.3,154.0 L 164.8,158.3 L 122.4,133.8 Z" fill="#82E9FF" />
          </g>
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

    // 0.0s -> 1.6s: Kristal -> Saat ibreleri dönüşümü
    tl.fromTo("#top-dark",  { attr: { d: SHAPES.topDarkOrig } },  { attr: { d: SHAPES.topDarkHand },  duration: 1.6, ease: "power2.inOut" }, 0);
    tl.fromTo("#top-light", { attr: { d: SHAPES.topLightOrig } }, { attr: { d: SHAPES.topLightHand }, duration: 1.6, ease: "power2.inOut" }, 0);
    tl.fromTo("#lb-dark",   { attr: { d: SHAPES.lbDarkOrig } },   { attr: { d: SHAPES.lbDarkHand },   duration: 1.6, ease: "power2.inOut" }, 0);
    tl.fromTo("#lb-light",  { attr: { d: SHAPES.lbLightOrig } },  { attr: { d: SHAPES.lbLightHand },  duration: 1.6, ease: "power2.inOut" }, 0);
    tl.fromTo("#rb-dark",   { attr: { d: SHAPES.rbDarkOrig } },   { attr: { d: SHAPES.rbDarkHand },   duration: 1.6, ease: "power2.inOut" }, 0);
    tl.fromTo("#rb-light",  { attr: { d: SHAPES.rbLightOrig } },  { attr: { d: SHAPES.rbLightHand },  duration: 1.6, ease: "power2.inOut" }, 0);
    tl.fromTo("#center-dot-outer", { attr: { r: 34.6 } }, { attr: { r: 21.5 }, duration: 1.6, ease: "power2.inOut" }, 0);
    tl.fromTo("#center-dot-inner", { attr: { r: 28.4 } }, { attr: { r: 17.5 }, duration: 1.6, ease: "power2.inOut" }, 0);

    // 0.1s -> 1.98s: KetraWOS 1 yazısı merkezden alt kısma açılır
    tl.to("#ketra-word", { opacity: 0.75, duration: 0.9, ease: "power2.out" }, 0.1);
    tl.to("#ketra-word", { opacity: 1, x: 0, y: 0, scale: 1, duration: 0.66, ease: "power3.inOut" }, 1.02);
    tl.fromTo("#ver-badge", { opacity: 0, scale: 0.6 }, { opacity: 1, scale: 1, duration: 0.3, ease: "back.out(1.6)" }, 1.68);

    // 0.9s -> 8.4s: Tüm 3 kol toplam 2 tur (720 deg), hızlanma ve yavaşlama ağırdan ve C1-sürekli
    // Morph'un son 0.70s'inde (0.9s - 1.6s) ağır yavaştan hızlanmaya başlar (~16.3 deg @ 1.6s)
    const HANDS = ["#hand-top-group", "#hand-rb-group", "#hand-lb-group"];
    for (const h of HANDS) {
      tl.to(h, { rotation: 192, svgOrigin: "120 114", duration: 2.4, ease: "power1.in" },  0.9);
      tl.to(h, { rotation: 576, svgOrigin: "120 114", duration: 2.4, ease: "none" },       3.3);
      tl.to(h, { rotation: 720, svgOrigin: "120 114", duration: 2.7, ease: "power2.out" }, 5.7);
    }

    // 8.02s -> 10.0s: Yazı kapanır ve saat ibreleri kristale geri döner
    tl.to("#ver-badge", { opacity: 0, scale: 0.6, duration: 0.3, ease: "power2.in" }, 8.02);
    tl.to("#ketra-word", { opacity: 0.75, x: 7.5, y: -97, scale: 0.5, duration: 0.66, ease: "power3.inOut" }, 8.32);
    tl.to("#ketra-word", { opacity: 0, duration: 0.9, ease: "power2.in" }, 9.0);

    const revShapeStart = 8.4;
    tl.to("#top-dark",  { attr: { d: SHAPES.topDarkOrig },  duration: 1.6, ease: "power2.inOut" }, revShapeStart);
    tl.to("#top-light", { attr: { d: SHAPES.topLightOrig }, duration: 1.6, ease: "power2.inOut" }, revShapeStart);
    tl.to("#lb-dark",   { attr: { d: SHAPES.lbDarkOrig },   duration: 1.6, ease: "power2.inOut" }, revShapeStart);
    tl.to("#lb-light",  { attr: { d: SHAPES.lbLightOrig },  duration: 1.6, ease: "power2.inOut" }, revShapeStart);
    tl.to("#rb-dark",   { attr: { d: SHAPES.rbDarkOrig },   duration: 1.6, ease: "power2.inOut" }, revShapeStart);
    tl.to("#rb-light",  { attr: { d: SHAPES.rbLightOrig },  duration: 1.6, ease: "power2.inOut" }, revShapeStart);
    tl.to("#center-dot-outer", { attr: { r: 34.6 }, duration: 1.6, ease: "power2.inOut" }, revShapeStart);
    tl.to("#center-dot-inner", { attr: { r: 28.4 }, duration: 1.6, ease: "power2.inOut" }, revShapeStart);

    window.__timelines = window.__timelines || {};
    window.__timelines["ketrawos-logo-morph"] = tl;
  </script>
</body>
</html>
EOF

# --- PROJE 2: Dual Boot -> Kristal Logo Gelişi + 1. Animasyonun Aynısı (11.0s) ---
cat <<'EOF' > "$KETRA_DIR/index.html"
<!doctype html>
<html lang="tr">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=240, height=240" />
  <title>KetraWOS 1 — Dual Boot (240x240)</title>
  <script src="https://cdn.jsdelivr.net/npm/gsap@3.14.2/dist/gsap.min.js"></script>
  <style>
    @font-face {
      font-family: "Lexend";
      src: url("assets/fonts/lexend.woff2") format("woff2");
      font-weight: 700;
      font-style: normal;
    }
    * { box-sizing: border-box; }
    html, body { margin: 0; padding: 0; width: 240px; height: 240px; overflow: hidden; background: #000000; }
    #root { position: relative; width: 100%; height: 100%; overflow: hidden; background: #000000; font-family: "Lexend", sans-serif; }
    .clip { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; }
    #dualboot-stage { position: relative; width: 240px; height: 240px; }
    #logo-wrap { position: absolute; inset: 0; width: 240px; height: 240px; pointer-events: none; }
    #logo-svg { position: absolute; inset: 0; width: 240px; height: 240px; pointer-events: none; }
    #ketra-menu-row { position: absolute; top: 76px; left: 104px; height: 20px; display: flex; align-items: center; gap: 5px; pointer-events: none; }
    #ketra-menu-word { font-family: "Lexend", sans-serif; font-weight: 700; font-size: 12px; line-height: 1; color: #ffffff; }
    #ketra-menu-ver { font-family: "Lexend", sans-serif; font-weight: 700; font-size: 12px; line-height: 1; color: #ffffff; }
    #row-tcl { position: absolute; top: 138px; left: 0; width: 240px; height: 20px; display: flex; align-items: center; justify-content: center; gap: 8px; pointer-events: none; }
    #tcl-label { width: 82px; font-family: "Lexend", sans-serif; font-weight: 700; font-size: 12px; line-height: 1; color: #e5e7eb; white-space: nowrap; }
    #brand-row { position: absolute; top: 201px; left: 0; width: 240px; height: 20px; display: flex; align-items: center; justify-content: center; gap: 5px; pointer-events: none; }
    #ketra-word { display: inline-block; font-family: "Lexend", sans-serif; font-weight: 700; font-size: 13px; line-height: 1; letter-spacing: -0.01em; color: #ffffff; opacity: 0; }
    #ver-badge { display: inline-block; width: 10px; font-family: "Lexend", sans-serif; font-weight: 700; font-size: 13px; line-height: 1; text-align: center; color: #ffffff; opacity: 0; }
  </style>
</head>
<body>
  <div id="root" data-composition-id="ketrawos-dualboot-ketra" data-start="0" data-duration="11" data-width="240" data-height="240">
    <section id="dualboot-clip" class="clip" data-start="0" data-duration="11" data-track-index="1">
      <div id="dualboot-stage">
        <div id="logo-wrap">
          <svg id="logo-svg" viewBox="0 0 240 240" width="240" height="240">
            <g id="hand-top-group">
              <path id="top-dark" d="M 98.0,100.0 L 98.0,60.0 L 120.0,38.0 L 142.0,60.0 L 142.0,100.0 Z" fill="#8C0020" />
              <path id="top-light" d="M 104.0,94.0 L 104.0,63.0 L 120.0,44.0 L 136.0,63.0 L 136.0,94.0 Z" fill="#FF0055" />
            </g>
            <g id="hand-lb-group">
              <path id="lb-dark" d="M 125.8,136.1 L 75.5,165.1 L 45.5,157.0 L 53.5,127.0 L 103.8,98.0 Z" fill="#8A5A00" />
              <path id="lb-light" d="M 117.6,133.8 L 75.2,158.3 L 50.7,154.0 L 59.1,130.7 L 101.6,106.2 Z" fill="#DD9500" />
            </g>
            <g id="hand-rb-group">
              <path id="rb-dark" d="M 136.2,98.0 L 186.4,127.0 L 194.5,157.0 L 164.4,165.1 L 114.2,136.1 Z" fill="#008CAA" />
              <path id="rb-light" d="M 138.4,106.2 L 180.8,130.7 L 189.3,154.0 L 164.8,158.3 L 122.4,133.8 Z" fill="#82E9FF" />
            </g>
            <circle id="center-dot-outer" cx="120.0" cy="114.0" r="34.6" fill="#950000" />
            <circle id="center-dot-inner" cx="120.0" cy="114.0" r="28.4" fill="#E00000" />
          </svg>
        </div>

        <div id="ketra-menu-row">
          <span id="ketra-menu-word">KetraWOS</span>
          <span id="ketra-menu-ver">1</span>
        </div>

        <div id="row-tcl">
          <svg id="tcl-logo-svg" width="44" height="14" viewBox="0 0 235 73">
            <path id="tcl-t" fill="#FFFFFF" d="M 0.0,3.0 L 0.0,22.0 L 26.0,22.0 L 27.0,23.0 L 27.0,69.0 L 50.0,69.0 L 50.0,23.0 L 51.0,22.0 L 76.0,22.0 L 76.0,3.0 Z" />
            <path id="tcl-c" fill="#FFFFFF" d="M 97.0,6.0 L 89.0,14.0 L 89.0,15.0 L 87.0,17.0 L 87.0,18.0 L 86.0,19.0 L 86.0,21.0 L 84.0,24.0 L 84.0,27.0 L 83.0,28.0 L 83.0,44.0 L 84.0,45.0 L 84.0,48.0 L 85.0,49.0 L 85.0,51.0 L 86.0,52.0 L 87.0,55.0 L 89.0,57.0 L 89.0,58.0 L 96.0,65.0 L 99.0,66.0 L 101.0,68.0 L 103.0,68.0 L 106.0,70.0 L 109.0,70.0 L 110.0,71.0 L 114.0,71.0 L 115.0,72.0 L 131.0,72.0 L 132.0,71.0 L 136.0,71.0 L 137.0,70.0 L 140.0,70.0 L 141.0,69.0 L 142.0,69.0 L 143.0,68.0 L 144.0,68.0 L 145.0,67.0 L 148.0,66.0 L 156.0,58.0 L 156.0,57.0 L 157.0,56.0 L 157.0,55.0 L 160.0,50.0 L 160.0,45.0 L 161.0,44.0 L 140.0,44.0 L 140.0,46.0 L 139.0,47.0 L 138.0,50.0 L 134.0,54.0 L 133.0,54.0 L 132.0,55.0 L 130.0,55.0 L 129.0,56.0 L 118.0,56.0 L 117.0,55.0 L 115.0,55.0 L 114.0,54.0 L 113.0,54.0 L 107.0,48.0 L 107.0,47.0 L 104.0,42.0 L 104.0,30.0 L 105.0,29.0 L 105.0,27.0 L 106.0,26.0 L 106.0,25.0 L 110.0,20.0 L 111.0,20.0 L 114.0,17.0 L 116.0,17.0 L 117.0,16.0 L 120.0,16.0 L 121.0,15.0 L 126.0,15.0 L 127.0,16.0 L 130.0,16.0 L 131.0,17.0 L 133.0,17.0 L 138.0,22.0 L 138.0,23.0 L 140.0,26.0 L 140.0,28.0 L 161.0,28.0 L 160.0,27.0 L 160.0,22.0 L 159.0,21.0 L 159.0,19.0 L 158.0,18.0 L 157.0,15.0 L 154.0,12.0 L 154.0,11.0 L 151.0,8.0 L 150.0,8.0 L 145.0,4.0 L 144.0,4.0 L 143.0,3.0 L 141.0,3.0 L 140.0,2.0 L 138.0,2.0 L 137.0,1.0 L 134.0,1.0 L 133.0,0.0 L 113.0,0.0 L 112.0,1.0 L 109.0,1.0 L 108.0,2.0 L 105.0,2.0 L 104.0,3.0 L 103.0,3.0 L 102.0,4.0 L 101.0,4.0 L 100.0,5.0 Z" />
            <path id="tcl-l" fill="#FFFFFF" d="M 174.0,3.0 L 174.0,69.0 L 234.0,69.0 L 234.0,52.0 L 197.0,52.0 L 196.0,51.0 L 196.0,3.0 Z" />
          </svg>
          <span id="tcl-label">TCL Original</span>
        </div>

        <div id="brand-row">
          <span id="ketra-word">KetraWOS</span>
          <span id="ver-badge">1</span>
        </div>
      </div>
    </section>
  </div>
  <script>
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

    // Dual Boot menüsünde kristal logo küçültülmüş halde (75, 89) merkezli
    gsap.set("#logo-wrap",  { x: -45, y: -25, scale: 0.29, transformOrigin: "120px 114px" });
    gsap.set("#ketra-word", { x: 7.5, y: -97, scale: 0.5 });
    gsap.set("#ver-badge",  { scale: 0.6 });

    const tl = gsap.timeline({ paused: true });

    // 0.0s -> 0.95s: Dual Boot menüsü kapanır, kristal logo tam boy merkeze gelir
    tl.to("#ketra-menu-row", { opacity: 0, y: -6, duration: 0.35, ease: "power2.in" }, 0.3);
    tl.to("#row-tcl",        { opacity: 0, y: 8,  duration: 0.35, ease: "power2.in" }, 0.3);
    tl.to("#logo-wrap",      { x: 0, y: 0, scale: 1, duration: 0.6, ease: "power3.inOut" }, 0.35);

    // 1.0s'den itibaren 1. animasyon ile birebir aynı sekans
    const T = 1.0;

    tl.fromTo("#top-dark",  { attr: { d: SHAPES.topDarkOrig } },  { attr: { d: SHAPES.topDarkHand },  duration: 1.6, ease: "power2.inOut" }, T + 0);
    tl.fromTo("#top-light", { attr: { d: SHAPES.topLightOrig } }, { attr: { d: SHAPES.topLightHand }, duration: 1.6, ease: "power2.inOut" }, T + 0);
    tl.fromTo("#lb-dark",   { attr: { d: SHAPES.lbDarkOrig } },   { attr: { d: SHAPES.lbDarkHand },   duration: 1.6, ease: "power2.inOut" }, T + 0);
    tl.fromTo("#lb-light",  { attr: { d: SHAPES.lbLightOrig } },  { attr: { d: SHAPES.lbLightHand },  duration: 1.6, ease: "power2.inOut" }, T + 0);
    tl.fromTo("#rb-dark",   { attr: { d: SHAPES.rbDarkOrig } },   { attr: { d: SHAPES.rbDarkHand },   duration: 1.6, ease: "power2.inOut" }, T + 0);
    tl.fromTo("#rb-light",  { attr: { d: SHAPES.rbLightOrig } },  { attr: { d: SHAPES.rbLightHand },  duration: 1.6, ease: "power2.inOut" }, T + 0);
    tl.fromTo("#center-dot-outer", { attr: { r: 34.6 } }, { attr: { r: 21.5 }, duration: 1.6, ease: "power2.inOut" }, T + 0);
    tl.fromTo("#center-dot-inner", { attr: { r: 28.4 } }, { attr: { r: 17.5 }, duration: 1.6, ease: "power2.inOut" }, T + 0);

    tl.to("#ketra-word", { opacity: 0.75, duration: 0.9, ease: "power2.out" }, T + 0.1);
    tl.to("#ketra-word", { opacity: 1, x: 0, y: 0, scale: 1, duration: 0.66, ease: "power3.inOut" }, T + 1.02);
    tl.fromTo("#ver-badge", { opacity: 0, scale: 0.6 }, { opacity: 1, scale: 1, duration: 0.3, ease: "back.out(1.6)" }, T + 1.68);

    const HANDS = ["#hand-top-group", "#hand-rb-group", "#hand-lb-group"];
    for (const h of HANDS) {
      tl.to(h, { rotation: 192, svgOrigin: "120 114", duration: 2.4, ease: "power1.in" },  T + 0.9);
      tl.to(h, { rotation: 576, svgOrigin: "120 114", duration: 2.4, ease: "none" },       T + 3.3);
      tl.to(h, { rotation: 720, svgOrigin: "120 114", duration: 2.7, ease: "power2.out" }, T + 5.7);
    }

    tl.to("#ver-badge", { opacity: 0, scale: 0.6, duration: 0.3, ease: "power2.in" }, T + 8.02);
    tl.to("#ketra-word", { opacity: 0.75, x: 7.5, y: -97, scale: 0.5, duration: 0.66, ease: "power3.inOut" }, T + 8.32);
    tl.to("#ketra-word", { opacity: 0, duration: 0.9, ease: "power2.in" }, T + 9.0);

    const revShapeStart = T + 8.4;
    tl.to("#top-dark",  { attr: { d: SHAPES.topDarkOrig },  duration: 1.6, ease: "power2.inOut" }, revShapeStart);
    tl.to("#top-light", { attr: { d: SHAPES.topLightOrig }, duration: 1.6, ease: "power2.inOut" }, revShapeStart);
    tl.to("#lb-dark",   { attr: { d: SHAPES.lbDarkOrig },   duration: 1.6, ease: "power2.inOut" }, revShapeStart);
    tl.to("#lb-light",  { attr: { d: SHAPES.lbLightOrig },  duration: 1.6, ease: "power2.inOut" }, revShapeStart);
    tl.to("#rb-dark",   { attr: { d: SHAPES.rbDarkOrig },   duration: 1.6, ease: "power2.inOut" }, revShapeStart);
    tl.to("#rb-light",  { attr: { d: SHAPES.rbLightOrig },  duration: 1.6, ease: "power2.inOut" }, revShapeStart);
    tl.to("#center-dot-outer", { attr: { r: 34.6 }, duration: 1.6, ease: "power2.inOut" }, revShapeStart);
    tl.to("#center-dot-inner", { attr: { r: 28.4 }, duration: 1.6, ease: "power2.inOut" }, revShapeStart);

    window.__timelines = window.__timelines || {};
    window.__timelines["ketrawos-dualboot-ketra"] = tl;
  </script>
</body>
</html>
EOF

# --- PROJE 3: Dual Boot -> TCL Original (1.7s Kısa Video) ---
cat <<'EOF' > "$TCL_DIR/index.html"
<!doctype html>
<html lang="tr">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=240, height=240" />
  <title>KetraWOS — Dual Boot TCL Original (240x240)</title>
  <script src="https://cdn.jsdelivr.net/npm/gsap@3.14.2/dist/gsap.min.js"></script>
  <style>
    @font-face {
      font-family: "Lexend";
      src: url("assets/fonts/lexend.woff2") format("woff2");
      font-weight: 700;
      font-style: normal;
    }
    * { box-sizing: border-box; }
    html, body { margin: 0; padding: 0; width: 240px; height: 240px; overflow: hidden; background: #000000; }
    #root { position: relative; width: 100%; height: 100%; overflow: hidden; background: #000000; font-family: "Lexend", sans-serif; }
    .clip { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; }
    #tclboot-stage { position: relative; width: 240px; height: 240px; }
    #logo-wrap { position: absolute; inset: 0; width: 240px; height: 240px; pointer-events: none; }
    #logo-svg { position: absolute; inset: 0; width: 240px; height: 240px; pointer-events: none; }
    #ketra-menu-row { position: absolute; top: 76px; left: 104px; height: 20px; display: flex; align-items: center; gap: 5px; pointer-events: none; }
    #ketra-menu-word { font-family: "Lexend", sans-serif; font-weight: 700; font-size: 12px; line-height: 1; color: #ffffff; }
    #ketra-menu-ver { font-family: "Lexend", sans-serif; font-weight: 700; font-size: 12px; line-height: 1; color: #ffffff; }
    #tcl-logo-wrap { position: absolute; top: 99.5px; left: 54px; width: 132px; height: 41px; pointer-events: none; }
    #tcl-logo-svg { display: block; width: 132px; height: 41px; }
    #tcl-label { position: absolute; top: 138px; left: 105px; width: 82px; height: 20px; display: flex; align-items: center; font-family: "Lexend", sans-serif; font-weight: 700; font-size: 12px; line-height: 1; color: #e5e7eb; white-space: nowrap; pointer-events: none; }
  </style>
</head>
<body>
  <div id="root" data-composition-id="ketrawos-dualboot-tcl" data-start="0" data-duration="1.7" data-width="240" data-height="240">
    <section id="tclboot-clip" class="clip" data-start="0" data-duration="1.7" data-track-index="1">
      <div id="tclboot-stage">
        <div id="logo-wrap">
          <svg id="logo-svg" viewBox="0 0 240 240" width="240" height="240">
            <path id="top-dark" d="M 98.0,100.0 L 98.0,60.0 L 120.0,38.0 L 142.0,60.0 L 142.0,100.0 Z" fill="#8C0020" />
            <path id="top-light" d="M 104.0,94.0 L 104.0,63.0 L 120.0,44.0 L 136.0,63.0 L 136.0,94.0 Z" fill="#FF0055" />
            <path id="lb-dark" d="M 125.8,136.1 L 75.5,165.1 L 45.5,157.0 L 53.5,127.0 L 103.8,98.0 Z" fill="#8A5A00" />
            <path id="lb-light" d="M 117.6,133.8 L 75.2,158.3 L 50.7,154.0 L 59.1,130.7 L 101.6,106.2 Z" fill="#DD9500" />
            <path id="rb-dark" d="M 136.2,98.0 L 186.4,127.0 L 194.5,157.0 L 164.4,165.1 L 114.2,136.1 Z" fill="#008CAA" />
            <path id="rb-light" d="M 138.4,106.2 L 180.8,130.7 L 189.3,154.0 L 164.8,158.3 L 122.4,133.8 Z" fill="#82E9FF" />
            <circle id="center-dot-outer" cx="120.0" cy="114.0" r="34.6" fill="#950000" />
            <circle id="center-dot-inner" cx="120.0" cy="114.0" r="28.4" fill="#E00000" />
          </svg>
        </div>

        <div id="ketra-menu-row">
          <span id="ketra-menu-word">KetraWOS</span>
          <span id="ketra-menu-ver">1</span>
        </div>

        <div id="tcl-logo-wrap">
          <svg id="tcl-logo-svg" width="132" height="41" viewBox="0 0 235 73">
            <path id="tcl-t" fill="#FFFFFF" d="M 0.0,3.0 L 0.0,22.0 L 26.0,22.0 L 27.0,23.0 L 27.0,69.0 L 50.0,69.0 L 50.0,23.0 L 51.0,22.0 L 76.0,22.0 L 76.0,3.0 Z" />
            <path id="tcl-c" fill="#FFFFFF" d="M 97.0,6.0 L 89.0,14.0 L 89.0,15.0 L 87.0,17.0 L 87.0,18.0 L 86.0,19.0 L 86.0,21.0 L 84.0,24.0 L 84.0,27.0 L 83.0,28.0 L 83.0,44.0 L 84.0,45.0 L 84.0,48.0 L 85.0,49.0 L 85.0,51.0 L 86.0,52.0 L 87.0,55.0 L 89.0,57.0 L 89.0,58.0 L 96.0,65.0 L 99.0,66.0 L 101.0,68.0 L 103.0,68.0 L 106.0,70.0 L 109.0,70.0 L 110.0,71.0 L 114.0,71.0 L 115.0,72.0 L 131.0,72.0 L 132.0,71.0 L 136.0,71.0 L 137.0,70.0 L 140.0,70.0 L 141.0,69.0 L 142.0,69.0 L 143.0,68.0 L 144.0,68.0 L 145.0,67.0 L 148.0,66.0 L 156.0,58.0 L 156.0,57.0 L 157.0,56.0 L 157.0,55.0 L 160.0,50.0 L 160.0,45.0 L 161.0,44.0 L 140.0,44.0 L 140.0,46.0 L 139.0,47.0 L 138.0,50.0 L 134.0,54.0 L 133.0,54.0 L 132.0,55.0 L 130.0,55.0 L 129.0,56.0 L 118.0,56.0 L 117.0,55.0 L 115.0,55.0 L 114.0,54.0 L 113.0,54.0 L 107.0,48.0 L 107.0,47.0 L 104.0,42.0 L 104.0,30.0 L 105.0,29.0 L 105.0,27.0 L 106.0,26.0 L 106.0,25.0 L 110.0,20.0 L 111.0,20.0 L 114.0,17.0 L 116.0,17.0 L 117.0,16.0 L 120.0,16.0 L 121.0,15.0 L 126.0,15.0 L 127.0,16.0 L 130.0,16.0 L 131.0,17.0 L 133.0,17.0 L 138.0,22.0 L 138.0,23.0 L 140.0,26.0 L 140.0,28.0 L 161.0,28.0 L 160.0,27.0 L 160.0,22.0 L 159.0,21.0 L 159.0,19.0 L 158.0,18.0 L 157.0,15.0 L 154.0,12.0 L 154.0,11.0 L 151.0,8.0 L 150.0,8.0 L 145.0,4.0 L 144.0,4.0 L 143.0,3.0 L 141.0,3.0 L 140.0,2.0 L 138.0,2.0 L 137.0,1.0 L 134.0,1.0 L 133.0,0.0 L 113.0,0.0 L 112.0,1.0 L 109.0,1.0 L 108.0,2.0 L 105.0,2.0 L 104.0,3.0 L 103.0,3.0 L 102.0,4.0 L 101.0,4.0 L 100.0,5.0 Z" />
            <path id="tcl-l" fill="#FFFFFF" d="M 174.0,3.0 L 174.0,69.0 L 234.0,69.0 L 234.0,52.0 L 197.0,52.0 L 196.0,51.0 L 196.0,3.0 Z" />
          </svg>
        </div>

        <span id="tcl-label">TCL Original</span>
      </div>
    </section>
  </div>
  <script>
    gsap.set("#logo-wrap",     { x: -45, y: -25, scale: 0.29, transformOrigin: "120px 114px" });
    gsap.set("#tcl-logo-wrap", { x: -45, y: 28, scale: 0.333, transformOrigin: "center center" });

    const tl = gsap.timeline({ paused: true });
    tl.to("#logo-wrap",      { opacity: 0, y: -31, duration: 0.35, ease: "power2.in" }, 0.3);
    tl.to("#ketra-menu-row", { opacity: 0, y: -6,  duration: 0.35, ease: "power2.in" }, 0.3);
    tl.to("#tcl-label",      { opacity: 0, x: 6,   duration: 0.3,  ease: "power2.in" }, 0.3);
    tl.to("#tcl-logo-wrap",  { x: 0, y: 0, scale: 1, duration: 0.7, ease: "power3.inOut" }, 0.35);

    window.__timelines = window.__timelines || {};
    window.__timelines["ketrawos-dualboot-tcl"] = tl;
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
' "$MORPH_DIR/index.html" "$KETRA_DIR/index.html" "$TCL_DIR/index.html"
ok "HTML dış kaynak politikası doğrulandı."

"$HF_BIN" lint "$MORPH_DIR"
"$HF_BIN" check "$MORPH_DIR"
"$HF_BIN" lint "$KETRA_DIR"
"$HF_BIN" check "$KETRA_DIR"
"$HF_BIN" lint "$TCL_DIR"
"$HF_BIN" check "$TCL_DIR"
ok "Tüm 3 proje lint ve check kontrolünden geçti."

# 6. Tüm 3 Videoyu Render Etme (60fps)
log "6/6 — Tüm 3 video (240x240, 60fps) render ediliyor..."
"$HF_BIN" render "$MORPH_DIR" --fps 60 --output "$OUT_DIR/ketrawos-logo-morph-240x240.mp4"
"$HF_BIN" render "$KETRA_DIR" --fps 60 --output "$OUT_DIR/ketrawos-dualboot-ketra-240x240.mp4"
"$HF_BIN" render "$TCL_DIR"   --fps 60 --output "$OUT_DIR/ketrawos-dualboot-tcl-240x240.mp4"

log "TAMAMLANDI! Tüm 3 video başarıyla oluşturuldu:"
ls -lh \
  "$OUT_DIR/ketrawos-logo-morph-240x240.mp4" \
  "$OUT_DIR/ketrawos-dualboot-ketra-240x240.mp4" \
  "$OUT_DIR/ketrawos-dualboot-tcl-240x240.mp4"
