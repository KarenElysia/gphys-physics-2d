// 事例の絵: いまの gphys の様子を、横に並べたコマに描いて PPM で保存する
//   動かない物体=紺 / 動く物体=速さで色が変わる(遅い=ピンク → 速い=黄)
import std;
import math;
import os;

namespace pic;

var img: u8[>..] = [];
var head: i64 = 0;
var cols: i64 = 1;
var fw: i64 = 240;      // 1コマの幅・高さ(ピクセル)
var fh: i64 = 240;
var gap: i64 = 8;
var ww: f32 = 100.0;    // 1コマに映す世界の大きさ
var wh: f32 = 100.0;
var fast: f32 = 12.0;   // この速さで いちばん黄色

fn begin(n_cols: i64, frame_w: i64, frame_h: i64, world_w: f32, world_h: f32) {
    cols = n_cols; fw = frame_w; fh = frame_h; ww = world_w; wh = world_h;
    let w = cols * fw + (cols - 1) * gap;
    img.clear();
    format(img, "P6 ", w, " ", fh, " 255\n");
    head = img.len;
    for k in w * fh { img.push(250); img.push(246); img.push(238); }
}

fn dot(slot: i64, x: f32, y: f32, r: f32, cr: i64, cg: i64, cb: i64) {
    let s: f32 = fw / ww;
    let w = cols * fw + (cols - 1) * gap;
    let ox = slot * (fw + gap);
    let cx = x * s;
    let cy = fh - y * s;
    let rr = max(r * s, 0.7);
    for py in max(0, (cy - rr) as i64)..min(fh, (cy + rr) as i64 + 1) {
        for px in max(0, (cx - rr) as i64)..min(fw, (cx + rr) as i64 + 1) {
            let dx = px + 0.5 - cx;
            let dy = py + 0.5 - cy;
            if dx * dx + dy * dy <= rr * rr {
                let o = head + (py * w + ox + px) * 3;
                img[o] = cr as! u8; img[o + 1] = cg as! u8; img[o + 2] = cb as! u8;
            }
        }
    }
}

fn snap(slot: i64) {
    for i in gphys::count() {
        if gphys::im[i] == 0.0 { dot(slot, gphys::px[i], gphys::py[i], gphys::rad[i], 60, 56, 90); continue; }
        let sp = min(1.0, sqrt(gphys::vx[i] * gphys::vx[i] + gphys::vy[i] * gphys::vy[i]) / fast);
        dot(slot, gphys::px[i], gphys::py[i], gphys::rad[i], (250.0 - 20.0 * sp) as i64, (110.0 + 110.0 * sp) as i64, (165.0 - 125.0 * sp) as i64);
    }
}

fn save(path: u8[:]) -> bool { write_file(path, img) }
