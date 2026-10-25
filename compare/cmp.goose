// 比較用: 同じ場面を gphys(グリッド)と、総当たり(全部の組を調べる O(n^2))で
// 使い方: goose build cmp.goose && ./cmp grid 10000 120   /   ./cmp naive 2000 30
import std;
import math;
import os;
import gphys from "..";

fn setup(n: i64) {
    let size: f32 = ceil(sqrt(n * 2.2)) as f32;
    gphys::reset();
    gphys::world(0.0, 0.0, size, size, 1.0);
    gphys::gx = 0.0; gphys::gy = -9.8;
    let per_row = (size / 1.05) as i64 - 1;
    for k in n {
        let j1: f32 = ((k * 7919 + 13) % 1000) / 1000.0;
        let j2: f32 = ((k * 104729 + 7) % 1000) / 1000.0;
        gphys::add(0.6 + (k % per_row) * 1.05 + j1 * 0.04, 0.6 + (k / per_row) * 1.05, 0.3 + j2 * 0.2, 1.0);
    }
}

// 総当たり: 衝突だけ全組で解く(それ以外は gphys と同じ手順)
fn naive_step(dt: f32, subs: i64) -> i64 {
    let n = gphys::px.len;
    assert(gphys::py.len == n && gphys::vx.len == n && gphys::vy.len == n && gphys::qx.len == n && gphys::qy.len == n && gphys::rad.len == n && gphys::im.len == n);
    let h = dt / subs;
    let ih = 1.0 / h;
    var hits: i64 = 0;
    for s in subs {
        for i in n {
            gphys::vy[i] += gphys::gy * h;
            gphys::px[i] += gphys::vx[i] * h; gphys::py[i] += gphys::vy[i] * h;
            gphys::qx[i] = gphys::px[i]; gphys::qy[i] = gphys::py[i];
        }
        for i in n {
            for j in i + 1..n {
                let dx = gphys::px[j] - gphys::px[i];
                let dy = gphys::py[j] - gphys::py[i];
                let r = gphys::rad[i] + gphys::rad[j];
                let d2 = dx * dx + dy * dy;
                if d2 < r * r && d2 > 1.0e-12 {
                    let d = sqrt(d2);
                    let k = (r - d) / (d * 2.0);
                    gphys::px[i] -= dx * k; gphys::py[i] -= dy * k;
                    gphys::px[j] += dx * k; gphys::py[j] += dy * k;
                    hits += 1;
                }
            }
        }
        for i in n {
            let r = gphys::rad[i];
            gphys::px[i] = clamp(gphys::px[i], gphys::bx0 + r, gphys::bx1 - r);
            gphys::py[i] = clamp(gphys::py[i], gphys::by0 + r, gphys::by1 - r);
            var dvx = (gphys::px[i] - gphys::qx[i]) * ih;
            var dvy = (gphys::py[i] - gphys::qy[i]) * ih;
            let d2 = dvx * dvx + dvy * dvy;
            let cap2 = gphys::max_push_speed * gphys::max_push_speed;
            if d2 > cap2 { let k2 = sqrt(cap2 / d2); dvx *= k2; dvy *= k2; }
            gphys::vx[i] += dvx;
            gphys::vy[i] += dvy;
        }
    }
    return hits;
}

fn main() {
    let a = args();
    let mode = if a.len > 1 { a[1] } else { "grid" };
    var n: i64 = 10000;
    var frames: i64 = 120;
    if a.len > 2 { let v, ok = parse_int(a[2]); if ok { n = v; } }
    if a.len > 3 { let v, ok = parse_int(a[3]); if ok { frames = v; } }
    setup(n);
    let naive = mode == "naive";
    let warm = 30;   // 同じだけ落としてから測る
    var hits: i64 = 0;
    for f in warm { if naive { hits = naive_step(1.0 / 60.0, 4); } else { gphys::step(1.0 / 60.0, 4); } }
    let t0 = clock();
    for f in frames { if naive { hits = naive_step(1.0 / 60.0, 4); } else { gphys::step(1.0 / 60.0, 4); } }
    let ms = (clock() - t0) * 1000.0 / frames;
    var line: u8[>..] = [];
    format(line, if naive { "Goose総当たり " } else { "Goose " }, n, " ");
    format_flt(line, ms, 3);
    format(line, " ", if naive { hits } else { gphys::contacts });
    print(line);
}
