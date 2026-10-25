// 事例: 群衆(ゲームの敵)。2000体が、動く目標へ向かって集まる。体どうしは重ならず、押し合って回り込む
//   使いどころ: タワーディフェンス・RTS・ゾンビの群れ。「重ならない」だけを物理に任せ、向かう先はゲーム側で決める
//   使い方: goose build crowd.goose && ./crowd → crowd.ppm
import std;
import math;
import os;
import gphys from "..";
import .pic;

fn main() {
    gphys::world(0.0, 0.0, 100.0, 100.0, 1.0);
    gphys::gx = 0.0; gphys::gy = 0.0;      // 上から見た世界: 重力なし
    gphys::damping = 2.0;
    // 本拠地の壁(動かない円の輪。真ん中に入口)
    for k in 72 {
        let a = k * TAU / 72.0;
        if k > 16 && k < 20 { continue; }                       // 入口
        gphys::add(50.0 + cos(a) as f32 * 12.0, 50.0 + sin(a) as f32 * 12.0, 0.5, 0.0);
    }
    let walls = gphys::count();
    // 敵: まわりの4すみから
    var r = rng { 99 };
    for k in 2000 {
        let side = k % 4;
        let bx: f32 = if side % 2 == 0 { 3.0 } else { 80.0 };
        let by: f32 = if side < 2 { 3.0 } else { 80.0 };
        gphys::add(bx + (r.rand_flt() as f32) * 17.0, by + (r.rand_flt() as f32) * 17.0, 0.35 + (r.rand_flt() as f32) * 0.12, 1.0);
    }
    pic::begin(3, 240, 240, 100.0, 100.0);
    pic::fast = 8.0;
    let shots = [1, 240, 600];
    var shot = 0;
    var ms: f64 = 0.0;
    for f in 601 {
        // ゲーム側: 目標(本拠地の中)へ向かう速さを決める。物理は「重ならない」ことだけを守る
        let tx: f32 = 50.0;
        let ty: f32 = 50.0;
        for i in walls..gphys::count() {
            let dx = tx - gphys::px[i];
            let dy = ty - gphys::py[i];
            let d = sqrt(dx * dx + dy * dy) + 0.001;
            let want: f32 = 6.0;                                 // 歩く速さ
            gphys::vx[i] += (dx / d * want - gphys::vx[i]) * 0.1;
            gphys::vy[i] += (dy / d * want - gphys::vy[i]) * 0.1;
        }
        let t0 = clock();
        gphys::step(1.0 / 60.0, 4);
        ms += clock() - t0;
        if shot < 3 && f == shots[shot] { pic::snap(shot); shot += 1; }
    }
    var inside = 0;
    for i in walls..gphys::count() {
        let dx = gphys::px[i] - 50.0;
        let dy = gphys::py[i] - 50.0;
        if dx * dx + dy * dy < 144.0 { inside += 1; }
    }
    var line: u8[>..] = [];
    format(line, "群衆: 敵 2000体 + 壁 ", walls, "  10秒後に本拠地の中 ", inside, "体  重なり最大 ");
    format_flt(line, gphys::max_overlap_ratio() * 100.0, 1);
    format(line, "%  1フレーム平均 ");
    format_flt(line, ms * 1000.0 / 601, 3);
    format(line, " ms");
    print(line);
    print("絵: crowd.ppm ", pic::save("crowd.ppm"));
}
