// 事例: 砂山。左に積んだ柱が崩れて、斜面になる。摩擦 0 と 0.4 を並べて比べる(どちらも 崩れる前 → 10秒後)
//   使いどころ: 砂・豆・コイン・ガレキ。摩擦で「どこまで流れるか」が変わる
//   使い方: goose build sand.goose && ./sand → sand.ppm
import std;
import math;
import os;
import gphys from "..";
import .pic;

fn run(fr: f32, slot0: i64) -> f32 {
    gphys::reset();
    gphys::world(0.0, 0.0, 100.0, 60.0, 1.0);
    gphys::gx = 0.0; gphys::gy = -9.8;
    gphys::friction = fr;
    gphys::restitution = 0.0;
    var r = rng { 5 };
    for k in 1200 {
        let x: f32 = 1.0 + (k % 20) * 0.95 + (r.rand_flt() as f32) * 0.05;
        let y: f32 = 0.5 + (k / 20) * 0.95;
        if y < 59.0 { gphys::add(x, y, 0.42 + (r.rand_flt() as f32) * 0.05, 1.0); }
    }
    pic::snap(slot0);
    for f in 600 { gphys::step(1.0 / 60.0, 6); }
    pic::snap(slot0 + 1);
    // 粒の 90% が入る、左からの幅(いちばん遠い1粒ではなく)
    var xs: f32[>..] = [];
    for i in gphys::count() { xs.push(gphys::px[i]); }
    sort(xs);
    return xs[xs.len * 9 / 10];
}

fn main() {
    pic::begin(4, 200, 120, 100.0, 60.0);
    pic::fast = 6.0;
    let a = run(0.0, 0);
    let b = run(0.4, 2);
    print("砂山(", gphys::count(), "粒・10秒後): 粒の90%が入る幅  摩擦 0 → x=", a, "   摩擦 0.4 → x=", b);
    print("絵: sand.ppm ", pic::save("sand.ppm"));
}
