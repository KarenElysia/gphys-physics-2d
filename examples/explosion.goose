// 事例: 爆発。積み上げた玉の山の真ん中で爆発させて、飛び散らせる
//   使いどころ: 爆弾・衝撃波・ノックバック。explode(x, y, 届く半径, 強さ) の1行
//   使い方: goose build explosion.goose && ./explosion → explosion.ppm
import std;
import math;
import os;
import gphys from "..";
import .pic;

fn main() {
    gphys::world(0.0, 0.0, 100.0, 100.0, 1.0);
    gphys::gx = 0.0; gphys::gy = -9.8;
    gphys::restitution = 0.3;
    gphys::friction = 0.2;
    // 三角の山(下ほど広い)
    var rows = 0;
    for row in 40 {
        let w = 40 - row;
        for k in w { gphys::add(30.0 + row * 0.5 + k * 1.0, 0.5 + row * 0.87, 0.49, 1.0); }
        rows += 1;
    }
    pic::begin(3, 240, 240, 100.0, 100.0);
    pic::fast = 25.0;
    for f in 60 { gphys::step(1.0 / 60.0, 6); }      // 落ち着かせる
    pic::snap(0);
    let hit = gphys::explode(50.0, 3.0, 14.0, 60.0);
    for f in 20 { gphys::step(1.0 / 60.0, 6); }
    pic::snap(1);
    for f in 220 { gphys::step(1.0 / 60.0, 6); }
    pic::snap(2);
    print("爆発: 玉 ", gphys::count(), " 個のうち ", hit, " 個を吹き飛ばした(爆発の直前・0.33秒後・4秒後)");
    print("絵: explosion.ppm ", pic::save("explosion.ppm"));
}
