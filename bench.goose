// gphys のベンチマーク: 玉の数ごとに、1フレーム(1/60秒・4小ステップ)の時間を測る
// 使い方: goose build bench.goose && ./bench   (最後の様子を bench.ppm に書く)
import std;
import math;
import os;
import .gphys;

fn fill_box(n: i64, size: f32, seed: u64) {
    gphys::reset();
    gphys::world(0.0, 0.0, size, size, 1.0);
    gphys::gx = 0.0; gphys::gy = -9.8;
    var r = rng { seed };
    let per_row = (size / 1.05) as i64 - 1;
    for k in n {
        let x = 0.6 + (k % per_row) * 1.05 + (r.rand_flt() as f32) * 0.04;
        let y = 0.6 + (k / per_row) * 1.05;
        gphys::add(x, y, 0.3 + (r.rand_flt() as f32) * 0.2, 1.0);
    }
}

fn run(n: i64, frames: i64, reorder_every: i64) -> f64 {
    let size: f32 = ceil(sqrt(n * 2.2)) as f32;          // 玉が箱の半分くらいを埋める
    fill_box(n, size, 42);
    for f in 30 { gphys::step(1.0 / 60.0, 4); }   // 慣らし(落ち始め)
    let t0 = clock();
    for f in frames {
        if reorder_every > 0 && f % reorder_every == 0 { gphys::reorder(); }
        gphys::step(1.0 / 60.0, 4);
    }
    let ms = (clock() - t0) * 1000.0 / frames;
    var line: u8[>..] = [];
    format(line, "玉 ", n, "  箱 ", size as i64, "x", size as i64, "  並べ直し ", if reorder_every > 0 { "あり" } else { "なし" }, "  1フレーム ");
    format_flt(line, ms, 3);
    format(line, " ms  (");
    format_flt(line, 1000.0 / ms, 0);
    format(line, " fps 相当)  衝突 ", gphys::contacts, "  調べた組 ", gphys::pairs_tested);
    print(line);
    return ms;
}

fn write_image(path: u8[:], px_size: i64) {
    let wpx = px_size;
    let hpx = px_size;
    var img: u8[>..] = [];
    format(img, "P6 ", wpx, " ", hpx, " 255\n");
    let head = img.len;
    for k in wpx * hpx { img.push(250); img.push(246); img.push(238); }
    let sx = wpx / (gphys::bx1 - gphys::bx0);
    let sy = hpx / (gphys::by1 - gphys::by0);
    for i in gphys::count() {
        let cx = (gphys::px[i] - gphys::bx0) * sx;
        let cy = hpx - (gphys::py[i] - gphys::by0) * sy;
        let rr = gphys::rad[i] * sx;
        let sp = min(1.0, sqrt(gphys::vx[i] * gphys::vx[i] + gphys::vy[i] * gphys::vy[i]) / 6.0);
        let u = gphys::uid[i] as i64;
        let cr = (90.0 + 160.0 * sp) as i64;
        let cg = 150 + (u * 37) % 80;
        let cb = (230.0 - 150.0 * sp) as i64;
        for y in max(0, (cy - rr) as i64)..min(hpx, (cy + rr) as i64 + 1) {
            for x in max(0, (cx - rr) as i64)..min(wpx, (cx + rr) as i64 + 1) {
                let dx = x + 0.5 - cx;
                let dy = y + 0.5 - cy;
                if dx * dx + dy * dy <= rr * rr {
                    let o = head + (y * wpx + x) * 3;
                    img[o] = cr as! u8; img[o + 1] = cg as! u8; img[o + 2] = cb as! u8;
                }
            }
        }
    }
    let ok = write_file(path, img);
    print("絵: ", path, " ", ok);
}

fn main() {
    print("gphys ベンチマーク(1フレーム = 1/60秒 を 4小ステップ)");
    for n in [1000, 10000, 50000, 100000] {
        let frames = if n <= 10000 { 300 } else { 120 };
        run(n, frames, 0);
        run(n, frames, 30);
    }
    // 最後の様子(10000個・3秒)
    fill_box(10000, 150.0, 7);
    for f in 180 { if f % 30 == 0 { gphys::reorder(); } gphys::step(1.0 / 60.0, 4); }
    write_image("bench.ppm", 600);
}
