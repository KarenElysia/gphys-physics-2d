// 事例: ゴルトンボード(動かない釘の間を、玉が落ちて山の形に積もる)
// 使い方: goose build galton.goose && ./galton → galton.ppm(3つの時刻を横に並べた絵)
import std;
import math;
import os;
import gphys from "..";

let WW = 120.0;
let WH = 160.0;
let PX = 240;     // 1コマの絵の大きさ
let PY = 320;

fn build_board() {
    gphys::reset();
    gphys::world(0.0, 0.0, WW, WH, 1.0);
    gphys::gx = 0.0; gphys::gy = -20.0;
    gphys::restitution = 0.15; gphys::friction = 0.0;   // 釘には摩擦なし(あると、玉が釘の上で止まる)
    // 釘(三角に並べる)
    for row in 26 {
        let y: f32 = 122.0 - row * 2.6;
        let off: f32 = if row % 2 == 0 { 0.0 } else { 1.5 };
        var x: f32 = 1.5 + off;
        while x < WW - 1.0 { gphys::add(x, y, 0.45, 0.0); x += 3.0; }
    }
    // ろうと(玉を真ん中へ集める)
    for k in 34 {
        let t: f32 = k * 0.7;
        gphys::add(33.0 + t, 152.0 - t * 0.75, 0.45, 0.0);   // 左の腕: (33,152) → (56,135)
        gphys::add(87.0 - t, 152.0 - t * 0.75, 0.45, 0.0);   // 右の腕: (87,152) → (64,135)
    }
    // 下の仕切り(縦にならべた釘)
    var x: f32 = 3.0;
    while x < WW - 1.0 {
        var y: f32 = 0.5;
        while y < 50.0 { gphys::add(x, y, 0.45, 0.0); y += 0.85; }
        x += 3.0;
    }
}

fn is_free(x: f32, y: f32, r: f32) -> bool {
    for i in gphys::count() {
        let dx = gphys::px[i] - x;
        let dy = gphys::py[i] - y;
        let rr = gphys::rad[i] + r;
        if dx * dx + dy * dy < rr * rr { return false; }
    }
    return true;
}

fn draw(img: u8[>..]&, head: i64, stride: i64, ox: i64) {
    let s: f32 = PX / WW;
    for i in gphys::count() {
        let cx = gphys::px[i] * s;
        let cy = PY - gphys::py[i] * s;
        let rr = max(gphys::rad[i] * s, 0.8);
        let still = gphys::im[i] == 0.0;
        let sp = min(1.0, sqrt(gphys::vx[i] * gphys::vx[i] + gphys::vy[i] * gphys::vy[i]) / 12.0);
        let cr: i64 = if still { 70 } else { (255.0 - 30.0 * sp) as i64 };
        let cg: i64 = if still { 64 } else { (120.0 + 90.0 * sp) as i64 };
        let cb: i64 = if still { 90 } else { (160.0 - 120.0 * sp) as i64 };
        for y in max(0, (cy - rr) as i64)..min(PY, (cy + rr) as i64 + 1) {
            for x in max(0, (cx - rr) as i64)..min(PX, (cx + rr) as i64 + 1) {
                let dx = x + 0.5 - cx;
                let dy = y + 0.5 - cy;
                if dx * dx + dy * dy <= rr * rr {
                    let o = head + y * stride + (ox + x) * 3;
                    img[o] = cr as! u8; img[o + 1] = cg as! u8; img[o + 2] = cb as! u8;
                }
            }
        }
    }
}

fn main() {
    build_board();
    let pegs = gphys::count();
    let frames = [240, 700, 1500];
    let gap = 8;
    let W = PX * 3 + gap * 2;
    var img: u8[>..] = [];
    format(img, "P6 ", W, " ", PY, " 255\n");
    let head = img.len;
    for k in W * PY { img.push(250); img.push(246); img.push(238); }
    var r = rng { 2026 };
    var shot = 0;
    var ms: f64 = 0.0;
    for f in 1501 {
        // 毎フレーム 4 個まで、上の空いている所に入れる(全部で 3000 個まで)
        if gphys::count() - pegs < 3000 {
            for k in 4 {
                let x: f32 = 48.0 + (r.rand_flt() as f32) * 24.0;
                let y: f32 = 154.0 + (r.rand_flt() as f32) * 4.0;
                let rr: f32 = 0.4 + (r.rand_flt() as f32) * 0.08;
                if is_free(x, y, rr) { gphys::add(x, y, rr, 1.0); }   // 重ねて入れない
            }
        }
        let t0 = clock();
        gphys::step(1.0 / 60.0, 6);
        ms += clock() - t0;
        if shot < 3 && f == frames[shot] {
            draw(img, head, W * 3, shot * (PX + gap));
            print("コマ ", shot + 1, ": ", f, " フレーム目(", f / 60.0, " 秒)  玉 ", gphys::count() - pegs, " 個");
            shot += 1;
        }
    }
    print("釘など動かない物体 ", pegs, " 個 + 玉 ", gphys::count() - pegs, " 個  1フレームの平均 ", ms * 1000.0 / 1501, " ms(6小ステップ)");
    print("絵: galton.ppm ", write_file("galton.ppm", img));
}
