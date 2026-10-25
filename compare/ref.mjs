// 比較用: gphys.goose と同じアルゴリズムを JavaScript(Node・Float32Array)で
// 使い方: node ref.mjs 10000 120
const n = +(process.argv[2] || 10000), frames = +(process.argv[3] || 120);
const size = Math.ceil(Math.sqrt(n * 2.2)), gw = Math.ceil(size), gh = gw, nc = gw * gh;
const F = () => new Float32Array(n), I = m => new Int32Array(m);
const px = F(), py = F(), vx = F(), vy = F(), qx = F(), qy = F(), rad = F(), im = F(), sx = F(), sy = F(), sr = F(), sm = F();
const cstart = I(nc + 1), ccur = I(nc + 1), order = I(n), cell = I(n);
const bx0 = 0, by0 = 0, bx1 = size, by1 = size, ics = 1, gy = -9.8, maxPush = 20;
let contacts = 0;

function cellOf(x, y) {
  let cx = Math.trunc((x - bx0) * ics), cy = Math.trunc((y - by0) * ics);
  cx = cx < 0 ? 0 : cx > gw - 1 ? gw - 1 : cx; cy = cy < 0 ? 0 : cy > gh - 1 ? gh - 1 : cy;
  return cy * gw + cx;
}
function buildGrid() {
  ccur.fill(0);
  for (let i = 0; i < n; i++) { const c = cellOf(px[i], py[i]); cell[i] = c; ccur[c + 1]++; }
  let run = 0;
  for (let c = 0; c <= nc; c++) { run += ccur[c]; ccur[c] = run; cstart[c] = run; }
  for (let i = 0; i < n; i++) { const c = cell[i], k = ccur[c]++; order[k] = i; sx[k] = px[i]; sy[k] = py[i]; sr[k] = rad[i]; sm[k] = im[i]; }
}
function solve() {
  for (let cy = 0; cy < gh; cy++) for (let cx = 0; cx < gw; cx++) {
    const c = cy * gw + cx, a0 = cstart[c], a1 = cstart[c + 1], r1 = cx + 1 < gw ? cstart[c + 2] : a1;
    let d0 = a0, d1 = a0;
    if (cy + 1 < gh) { d0 = cstart[cx > 0 ? c + gw - 1 : c + gw]; d1 = cstart[cx + 1 < gw ? c + gw + 2 : c + gw + 1]; }
    for (let a = a0; a < a1; a++) {
      let ax = sx[a], ay = sy[a]; const ar = sr[a], am = sm[a];
      for (let pass = 0; pass < 2; pass++) {
        const b0 = pass ? d0 : a + 1, b1 = pass ? d1 : r1;
        for (let b = b0; b < b1; b++) {
          const dx = sx[b] - ax, dy = sy[b] - ay, r = ar + sr[b], d2 = dx * dx + dy * dy;
          if (d2 < r * r && d2 > 1e-12) {
            const mb = sm[b], w = am + mb;
            if (w > 0) { const d = Math.sqrt(d2), k = (r - d) / (d * w); ax -= dx * k * am; ay -= dy * k * am; sx[b] += dx * k * mb; sy[b] += dy * k * mb; contacts++; }
          }
        }
      }
      sx[a] = ax; sy[a] = ay;
    }
  }
}
function step(dt, subs) {
  const h = dt / subs, ih = 1 / h, cap2 = maxPush * maxPush; contacts = 0;
  for (let s = 0; s < subs; s++) {
    for (let i = 0; i < n; i++) { if (im[i] > 0) { vy[i] += gy * h; px[i] += vx[i] * h; py[i] += vy[i] * h; } qx[i] = px[i]; qy[i] = py[i]; }
    buildGrid(); solve();
    for (let k = 0; k < n; k++) { const r = sr[k]; sx[k] = Math.min(Math.max(sx[k], bx0 + r), bx1 - r); sy[k] = Math.min(Math.max(sy[k], by0 + r), by1 - r); }
    for (let k = 0; k < n; k++) {
      const i = order[k];
      if (im[i] > 0) {
        px[i] = sx[k]; py[i] = sy[k];
        let dvx = (px[i] - qx[i]) * ih, dvy = (py[i] - qy[i]) * ih; const d2 = dvx * dvx + dvy * dvy;
        if (d2 > cap2) { const k2 = Math.sqrt(cap2 / d2); dvx *= k2; dvy *= k2; }
        vx[i] += dvx; vy[i] += dvy;
      } else { vx[i] = 0; vy[i] = 0; }
    }
  }
}
const perRow = Math.trunc(size / 1.05) - 1;
for (let k = 0; k < n; k++) {
  const j1 = ((k * 7919 + 13) % 1000) / 1000, j2 = ((k * 104729 + 7) % 1000) / 1000;
  px[k] = 0.6 + (k % perRow) * 1.05 + j1 * 0.04; py[k] = 0.6 + Math.trunc(k / perRow) * 1.05; rad[k] = 0.3 + j2 * 0.2; im[k] = 1;
}
for (let f = 0; f < 30; f++) step(1 / 60, 4);
const t0 = performance.now();
for (let f = 0; f < frames; f++) step(1 / 60, 4);
console.log(`JS ${n} ${((performance.now() - t0) / frames).toFixed(3)} ${contacts}`);
