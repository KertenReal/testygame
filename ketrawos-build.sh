#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# KetraWOS Dual Boot (KetraWOS 1 & Kısa TCL Geçişi) Video Üretici (240x240)
# ==============================================================================

WORKDIR="$(pwd)/ketrawos-workspace"
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
mkdir -p "$WORKDIR" "$KETRA_DIR/assets/fonts" "$TCL_DIR/assets/fonts" "$OUT_DIR"
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
' "$KETRA_DIR/assets/fonts/lexend.woff2" "$TCL_DIR/assets/fonts/lexend.woff2"
ok "GSAP ve Lexend fontu güvenle doğrulandı."

# 4. İki Dual Boot Kompozisyonunu Oluşturma
log "4/6 — Dual Boot (KetraWOS 1 + Kısa TCL) projeleri oluşturuluyor..."

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
    #clock-svg { position: absolute; inset: 0; width: 240px; height: 240px; pointer-events: none; }
    #brand-row { position: absolute; top: 201px; left: 0; width: 240px; height: 20px; display: flex; align-items: center; justify-content: center; gap: 5px; pointer-events: none; }
    #ketra-word { display: inline-block; font-family: "Lexend", sans-serif; font-weight: 700; font-size: 13px; line-height: 1; letter-spacing: -0.01em; color: #ffffff; }
    #ver-badge { display: inline-block; width: 10px; font-family: "Lexend", sans-serif; font-weight: 700; font-size: 13px; line-height: 1; text-align: center; color: #ffffff; }
    #row-tcl { position: absolute; top: 138px; left: 0; width: 240px; height: 20px; display: flex; align-items: center; justify-content: center; gap: 8px; pointer-events: none; }
    #tcl-label { width: 82px; font-family: "Lexend", sans-serif; font-weight: 700; font-size: 12px; line-height: 1; color: #e5e7eb; white-space: nowrap; }
  </style>
</head>
<body>
  <div id="root" data-composition-id="ketrawos-dualboot-ketra" data-start="0" data-duration="6.5" data-width="240" data-height="240">
    <section id="dualboot-clip" class="clip" data-start="0" data-duration="6.5" data-track-index="1">
      <div id="dualboot-stage">
        <svg id="clock-svg" viewBox="0 0 240 240" width="240" height="240">
          <g id="ketra-clock-group">
            <g id="hand-top-group">
              <path id="top-dark" d="M 117.0,98.0 L 117.0,28.0 L 120.0,28.0 L 123.0,28.0 L 123.0,98.0 Z" fill="#8C0020" />
              <path id="top-light" d="M 118.3,98.0 L 118.3,30.2 L 120.0,30.2 L 121.7,30.2 L 121.7,98.0 Z" fill="#FF0055" />
            </g>
            <g id="hand-lb-group">
              <path id="lb-dark" d="M 112.8,115.6 L 74.7,137.6 L 73.2,135.0 L 71.7,132.4 L 109.8,110.4 Z" fill="#8A5A00" />
              <path id="lb-light" d="M 112.2,114.5 L 76.0,135.4 L 75.1,133.9 L 74.3,132.4 L 110.5,111.5 Z" fill="#DD9500" />
            </g>
            <g id="hand-rb-group">
              <path id="rb-dark" d="M 130.2,110.4 L 182.1,140.4 L 180.6,143.0 L 179.1,145.6 L 127.2,115.6 Z" fill="#008CAA" />
              <path id="rb-light" d="M 129.5,111.5 L 179.6,140.4 L 178.7,141.9 L 177.9,143.4 L 127.8,114.5 Z" fill="#82E9FF" />
            </g>
            <circle id="center-dot-outer" cx="120.0" cy="108.0" r="21.5" fill="#950000" />
            <circle id="center-dot-inner" cx="120.0" cy="108.0" r="17.5" fill="#E00000" />
          </g>
        </svg>

        <div id="brand-row">
          <span id="ketra-word">KetraWOS</span>
          <span id="ver-badge">1</span>
        </div>

        <div id="row-tcl">
          <svg id="tcl-logo-svg" width="44" height="14" viewBox="0 0 235 73">
            <path id="tcl-t" fill="#FFFFFF" d="M 0.0,3.0 L 0.0,22.0 L 26.0,22.0 L 27.0,23.0 L 27.0,69.0 L 50.0,69.0 L 50.0,23.0 L 51.0,22.0 L 76.0,22.0 L 76.0,3.0 Z" />
            <path id="tcl-c" fill="#FFFFFF" d="M 97.0,6.0 L 89.0,14.0 L 89.0,15.0 L 87.0,17.0 L 87.0,18.0 L 86.0,19.0 L 86.0,21.0 L 84.0,24.0 L 84.0,27.0 L 83.0,28.0 L 83.0,44.0 L 84.0,45.0 L 84.0,48.0 L 85.0,49.0 L 85.0,51.0 L 86.0,52.0 L 87.0,55.0 L 89.0,57.0 L 89.0,58.0 L 96.0,65.0 L 99.0,66.0 L 101.0,68.0 L 103.0,68.0 L 106.0,70.0 L 109.0,70.0 L 110.0,71.0 L 114.0,71.0 L 115.0,72.0 L 131.0,72.0 L 132.0,71.0 L 136.0,71.0 L 137.0,70.0 L 140.0,70.0 L 141.0,69.0 L 142.0,69.0 L 143.0,68.0 L 144.0,68.0 L 145.0,67.0 L 148.0,66.0 L 156.0,58.0 L 156.0,57.0 L 157.0,56.0 L 157.0,55.0 L 160.0,50.0 L 160.0,45.0 L 161.0,44.0 L 140.0,44.0 L 140.0,46.0 L 139.0,47.0 L 138.0,50.0 L 134.0,54.0 L 133.0,54.0 L 132.0,55.0 L 130.0,55.0 L 129.0,56.0 L 118.0,56.0 L 117.0,55.0 L 115.0,55.0 L 114.0,54.0 L 113.0,54.0 L 107.0,48.0 L 107.0,47.0 L 104.0,42.0 L 104.0,30.0 L 105.0,29.0 L 105.0,27.0 L 106.0,26.0 L 106.0,25.0 L 110.0,20.0 L 111.0,20.0 L 114.0,17.0 L 116.0,17.0 L 117.0,16.0 L 120.0,16.0 L 121.0,15.0 L 126.0,15.0 L 127.0,16.0 L 130.0,16.0 L 131.0,17.0 L 133.0,17.0 L 138.0,22.0 L 138.0,23.0 L 140.0,26.0 L 140.0,28.0 L 161.0,28.0 L 160.0,27.0 L 160.0,22.0 L 159.0,21.0 L 159.0,19.0 L 158.0,18.0 L 157.0,15.0 L 154.0,12.0 L 154.0,11.0 L 151.0,8.0 L 150.0,8.0 L 145.0,4.0 L 144.0,4.0 L 143.0,3.0 L 141.0,3.0 L 140.0,2.0 L 138.0,2.0 L 137.0,1.0 L 134.0,1.0 L 133.0,0.0 L 113.0,0.0 L 112.0,1.0 L 109.0,1.0 L 108.0,2.0 L 105.0,2.0 L 104.0,3.0 L 103.0,3.0 L 102.0,4.0 L 101.0,4.0 L 100.0,5.0 Z" />
            <path id="tcl-l" fill="#FFFFFF" d="M 174.0,3.0 L 174.0,69.0 L 234.0,69.0 L 234.0,52.0 L 197.0,52.0 L 196.0,51.0 L 196.0,3.0 Z" />
          </svg>
          <span id="tcl-label">TCL Original</span>
        </div>
      </div>
    </section>
  </div>
  <script>
    const SPIN_CYCLES = 1;
    gsap.set("#ketra-clock-group", { x: -56, y: -22, scale: 0.33, svgOrigin: "120 108" });
    gsap.set("#brand-row", { x: 25, y: -125, scale: 0.92 });

    const tl = gsap.timeline({ paused: true });
    tl.to("#row-tcl", { opacity: 0, y: 8, duration: 0.4, ease: "power2.in" }, 0.3);
    tl.to("#ver-badge", { opacity: 0, scale: 0.6, duration: 0.18, ease: "power2.in" }, 0.3);
    tl.to("#ketra-clock-group", { x: 0, y: 0, scale: 1, svgOrigin: "120 108", duration: 0.6, ease: "power3.inOut" }, 0.35);
    tl.to("#brand-row", { x: 0, y: 0, scale: 1, duration: 0.55, ease: "power3.inOut" }, 0.35);
    tl.to("#ver-badge", { opacity: 1, scale: 1, duration: 0.25, ease: "back.out(1.6)" }, 0.88);

    let tCursor = 1.15;
    let aTop = 0, aRb = 0, aLb = 0;
    for (let c = 0; c < SPIN_CYCLES; c++) {
      aTop += 720; aRb += 360; aLb += 90;
      tl.to("#hand-top-group", { rotation: aTop, svgOrigin: "120 108", duration: 1.6, ease: "power1.in" }, tCursor);
      tl.to("#hand-rb-group",  { rotation: aRb,  svgOrigin: "120 108", duration: 1.6, ease: "power1.in" }, tCursor);
      tl.to("#hand-lb-group",  { rotation: aLb,  svgOrigin: "120 108", duration: 1.6, ease: "power1.in" }, tCursor);
      tCursor += 1.6;

      aTop += 1440; aRb += 720; aLb += 180;
      tl.to("#hand-top-group", { rotation: aTop, svgOrigin: "120 108", duration: 1.6, ease: "none" }, tCursor);
      tl.to("#hand-rb-group",  { rotation: aRb,  svgOrigin: "120 108", duration: 1.6, ease: "none" }, tCursor);
      tl.to("#hand-lb-group",  { rotation: aLb,  svgOrigin: "120 108", duration: 1.6, ease: "none" }, tCursor);
      tCursor += 1.6;

      aTop += 720; aRb += 360; aLb += 90;
      tl.to("#hand-top-group", { rotation: aTop, svgOrigin: "120 108", duration: 1.6, ease: "power1.out" }, tCursor);
      tl.to("#hand-rb-group",  { rotation: aRb,  svgOrigin: "120 108", duration: 1.6, ease: "power1.out" }, tCursor);
      tl.to("#hand-lb-group",  { rotation: aLb,  svgOrigin: "120 108", duration: 1.6, ease: "power1.out" }, tCursor);
      tCursor += 1.6;
    }

    window.__timelines = window.__timelines || {};
    window.__timelines["ketrawos-dualboot-ketra"] = tl;
  </script>
</body>
</html>
EOF

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
    #clock-svg { position: absolute; inset: 0; width: 240px; height: 240px; pointer-events: none; }
    #ketra-menu-row { position: absolute; top: 76px; left: 104px; height: 20px; display: flex; align-items: center; gap: 5px; pointer-events: none; }
    #ketra-menu-word { font-family: "Lexend", sans-serif; font-weight: 700; font-size: 12px; line-height: 1; color: #ffffff; }
    #ketra-menu-ver { font-family: "Lexend", sans-serif; font-weight: 700; font-size: 12px; line-height: 1; color: #ffffff; }
    #tcl-logo-svg { position: absolute; top: 99.5px; left: 54px; width: 132px; height: 41px; pointer-events: none; }
    #tcl-label { position: absolute; top: 138px; left: 105px; width: 82px; height: 20px; display: flex; align-items: center; font-family: "Lexend", sans-serif; font-weight: 700; font-size: 12px; line-height: 1; color: #e5e7eb; white-space: nowrap; pointer-events: none; }
  </style>
</head>
<body>
  <div id="root" data-composition-id="ketrawos-dualboot-tcl" data-start="0" data-duration="1.7" data-width="240" data-height="240">
    <section id="tclboot-clip" class="clip" data-start="0" data-duration="1.7" data-track-index="1">
      <div id="tclboot-stage">
        <svg id="clock-svg" viewBox="0 0 240 240" width="240" height="240">
          <g id="ketra-clock-group">
            <path id="top-dark" d="M 117.0,98.0 L 117.0,28.0 L 120.0,28.0 L 123.0,28.0 L 123.0,98.0 Z" fill="#8C0020" />
            <path id="top-light" d="M 118.3,98.0 L 118.3,30.2 L 120.0,30.2 L 121.7,30.2 L 121.7,98.0 Z" fill="#FF0055" />
            <path id="lb-dark" d="M 112.8,115.6 L 74.7,137.6 L 73.2,135.0 L 71.7,132.4 L 109.8,110.4 Z" fill="#8A5A00" />
            <path id="lb-light" d="M 112.2,114.5 L 76.0,135.4 L 75.1,133.9 L 74.3,132.4 L 110.5,111.5 Z" fill="#DD9500" />
            <path id="rb-dark" d="M 130.2,110.4 L 182.1,140.4 L 180.6,143.0 L 179.1,145.6 L 127.2,115.6 Z" fill="#008CAA" />
            <path id="rb-light" d="M 129.5,111.5 L 179.6,140.4 L 178.7,141.9 L 177.9,143.4 L 127.8,114.5 Z" fill="#82E9FF" />
            <circle id="center-dot-outer" cx="120.0" cy="108.0" r="21.5" fill="#950000" />
            <circle id="center-dot-inner" cx="120.0" cy="108.0" r="17.5" fill="#E00000" />
          </g>
        </svg>

        <div id="ketra-menu-row">
          <span id="ketra-menu-word">KetraWOS</span>
          <span id="ketra-menu-ver">1</span>
        </div>

        <svg id="tcl-logo-svg" width="132" height="41" viewBox="0 0 235 73">
          <path id="tcl-t" fill="#FFFFFF" d="M 0.0,3.0 L 0.0,22.0 L 26.0,22.0 L 27.0,23.0 L 27.0,69.0 L 50.0,69.0 L 50.0,23.0 L 51.0,22.0 L 76.0,22.0 L 76.0,3.0 Z" />
          <path id="tcl-c" fill="#FFFFFF" d="M 97.0,6.0 L 89.0,14.0 L 89.0,15.0 L 87.0,17.0 L 87.0,18.0 L 86.0,19.0 L 86.0,21.0 L 84.0,24.0 L 84.0,27.0 L 83.0,28.0 L 83.0,44.0 L 84.0,45.0 L 84.0,48.0 L 85.0,49.0 L 85.0,51.0 L 86.0,52.0 L 87.0,55.0 L 89.0,57.0 L 89.0,58.0 L 96.0,65.0 L 99.0,66.0 L 101.0,68.0 L 103.0,68.0 L 106.0,70.0 L 109.0,70.0 L 110.0,71.0 L 114.0,71.0 L 115.0,72.0 L 131.0,72.0 L 132.0,71.0 L 136.0,71.0 L 137.0,70.0 L 140.0,70.0 L 141.0,69.0 L 142.0,69.0 L 143.0,68.0 L 144.0,68.0 L 145.0,67.0 L 148.0,66.0 L 156.0,58.0 L 156.0,57.0 L 157.0,56.0 L 157.0,55.0 L 160.0,50.0 L 160.0,45.0 L 161.0,44.0 L 140.0,44.0 L 140.0,46.0 L 139.0,47.0 L 138.0,50.0 L 134.0,54.0 L 133.0,54.0 L 132.0,55.0 L 130.0,55.0 L 129.0,56.0 L 118.0,56.0 L 117.0,55.0 L 115.0,55.0 L 114.0,54.0 L 113.0,54.0 L 107.0,48.0 L 107.0,47.0 L 104.0,42.0 L 104.0,30.0 L 105.0,29.0 L 105.0,27.0 L 106.0,26.0 L 106.0,25.0 L 110.0,20.0 L 111.0,20.0 L 114.0,17.0 L 116.0,17.0 L 117.0,16.0 L 120.0,16.0 L 121.0,15.0 L 126.0,15.0 L 127.0,16.0 L 130.0,16.0 L 131.0,17.0 L 133.0,17.0 L 138.0,22.0 L 138.0,23.0 L 140.0,26.0 L 140.0,28.0 L 161.0,28.0 L 160.0,27.0 L 160.0,22.0 L 159.0,21.0 L 159.0,19.0 L 158.0,18.0 L 157.0,15.0 L 154.0,12.0 L 154.0,11.0 L 151.0,8.0 L 150.0,8.0 L 145.0,4.0 L 144.0,4.0 L 143.0,3.0 L 141.0,3.0 L 140.0,2.0 L 138.0,2.0 L 137.0,1.0 L 134.0,1.0 L 133.0,0.0 L 113.0,0.0 L 112.0,1.0 L 109.0,1.0 L 108.0,2.0 L 105.0,2.0 L 104.0,3.0 L 103.0,3.0 L 102.0,4.0 L 101.0,4.0 L 100.0,5.0 Z" />
          <path id="tcl-l" fill="#FFFFFF" d="M 174.0,3.0 L 174.0,69.0 L 234.0,69.0 L 234.0,52.0 L 197.0,52.0 L 196.0,51.0 L 196.0,3.0 Z" />
        </svg>

        <span id="tcl-label">TCL Original</span>
      </div>
    </section>
  </div>
  <script>
    gsap.set("#ketra-clock-group", { x: -56, y: -22, scale: 0.33, svgOrigin: "120 108" });
    gsap.set("#tcl-logo-svg", { x: -45, y: 28, scale: 0.333 });

    const tl = gsap.timeline({ paused: true });

    // 0.00s -> 0.30s sabit durur; 0.30s sonrası KetraWOS 1 ve "TCL Original" yazısı kaybolur
    tl.to("#ketra-clock-group", { opacity: 0, y: -28, duration: 0.35, ease: "power2.in" }, 0.3);
    tl.to("#ketra-menu-row",    { opacity: 0, y: -6,  duration: 0.35, ease: "power2.in" }, 0.3);
    tl.to("#tcl-label",         { opacity: 0, x: 6,   duration: 0.3,  ease: "power2.in" }, 0.3);

    // Beyaz TCL logosu ekran ortasına (120, 120) gelip büyür ve kısa sürede kesilir (1.7s)
    tl.to("#tcl-logo-svg", { x: 0, y: 0, scale: 1, duration: 0.7, ease: "power3.inOut" }, 0.35);

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
' "$KETRA_DIR/index.html" "$TCL_DIR/index.html"
ok "HTML dış kaynak politikası doğrulandı."

"$HF_BIN" lint "$KETRA_DIR"
"$HF_BIN" check "$KETRA_DIR"
"$HF_BIN" lint "$TCL_DIR"
"$HF_BIN" check "$TCL_DIR"
ok "Her iki proje lint ve check kontrolünden geçti."

# 6. İki Dual Boot Videosu Render (60fps)
log "6/6 — KetraWOS 1 ve Kısa TCL Dual Boot videoları render ediliyor..."
"$HF_BIN" render "$KETRA_DIR" --fps 60 --output "$OUT_DIR/ketrawos-dualboot-ketra-240x240.mp4"
"$HF_BIN" render "$TCL_DIR"   --fps 60 --output "$OUT_DIR/ketrawos-dualboot-tcl-240x240.mp4"

log "TAMAMLANDI! İki video başarıyla oluşturuldu:"
ls -lh "$OUT_DIR/ketrawos-dualboot-ketra-240x240.mp4" "$OUT_DIR/ketrawos-dualboot-tcl-240x240.mp4"
