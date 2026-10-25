// gphys のテスト: 自由落下・運動量・動かない物体・積み重なり・決定論・並べ直し
import std;
import math;
import .gphys;

var fails: i64 = 0;

fn check(name: u8[:], ok: bool, note: u8[:]) {
    if ok { print("OK  ", name, "  ", note); } else { print("NG  ", name, "  ", note); fails += 1; }
}

fn setup(gravity: f32) {
    gphys::reset();
    gphys::world(0.0, 0.0, 100.0, 100.0, 2.0);
    gphys::gx = 0.0; gphys::gy = gravity;
    gphys::restitution = 0.0; gphys::friction = 0.0; gphys::damping = 0.0; gphys::relax = 1.0;
}

// 箱に n 個の玉を、乱数で少しずらして並べる
fn pile(n: i64, seed: u64) {
    var r = rng { seed };
    let per_row = 44;
    for k in n {
        let x = 8.0 + (k % per_row) * 2.0 + r.rand_flt() as f32 * 0.4;
        let y = 5.0 + (k / per_row) as f32 * 2.1;
        gphys::add(x, y, 0.5 + r.rand_flt() as f32 * 0.4, 1.0);
    }
}

fn main() {
    // 1. 自由落下: y = y0 + v0 t + g t^2 / 2(半陰的オイラーの誤差は h に比例して小さい)
    setup(-9.8);
    gphys::add(50.0, 90.0, 0.5, 1.0);
    for s in 60 { gphys::step(1.0 / 60.0, 8); }
    let want: f32 = 90.0 - 0.5 * 9.8;
    let err = abs(gphys::py[0] - want);
    check("自由落下(1秒)", err < 0.05, str("y=", gphys::py[0], " 期待=", want, " 誤差=", err));

    // 2. 重なった2つ(重力なし): 1ステップで離れ、重心は動かない
    setup(0.0);
    gphys::add(50.0, 50.0, 0.5, 1.0);
    gphys::add(50.6, 50.0, 0.5, 1.0);
    let cx0 = (gphys::px[0] + gphys::px[1]) * 0.5;
    gphys::step(1.0 / 60.0, 4);
    let gap = gphys::px[1] - gphys::px[0];
    let cx1 = (gphys::px[0] + gphys::px[1]) * 0.5;
    check("重なりが解ける", gap >= 0.999, str("中心の距離=", gap));
    check("重心が動かない", abs(cx1 - cx0) < 1.0e-4, str("ずれ=", abs(cx1 - cx0)));

    // 3. 動かない物体: 何が当たっても動かない
    setup(-9.8);
    let wall = gphys::add(50.0, 20.0, 0.9, 0.0);
    gphys::add(50.2, 30.0, 0.5, 1.0);
    for s in 120 { gphys::step(1.0 / 60.0, 8); }
    check("動かない物体は動かない", gphys::px[wall] == 50.0 && gphys::py[wall] == 20.0, str("(", gphys::px[wall], ", ", gphys::py[wall], ")"));
    check("落ちた玉は 動かない物体の上を すべり落ちる", gphys::py[1] < 20.0, str("y=", gphys::py[1]));

    // 4. 2000個の積み重なり: NaN なし・箱の外に出ない・重なりが小さい
    setup(-9.8);
    gphys::world(0.0, 0.0, 100.0, 100.0, 2.0);
    pile(2000, 7);
    for s in 600 { gphys::step(1.0 / 60.0, 8); }
    var bad = 0;
    var outside = 0;
    for i in gphys::count() {
        let x = gphys::px[i]; let y = gphys::py[i];
        if is_nan(x) || is_nan(y) { bad += 1; }
        if x < 0.0 || x > 100.0 || y < 0.0 || y > 100.0 { outside += 1; }
    }
    let ov = gphys::max_overlap_ratio();
    check("2000個: NaN なし", bad == 0, str(bad, " 個"));
    check("2000個: 箱の外に出ない", outside == 0, str(outside, " 個"));
    check("2000個: 落ち着いた後の重なり < 半径の 10%", ov < 0.1, str("最大 ", ov * 100.0, "%"));
    var top: f32 = 0.0;
    var speed: f32 = 0.0;
    var avg: f64 = 0.0;
    for i in gphys::count() {
        let v = sqrt(gphys::vx[i] * gphys::vx[i] + gphys::vy[i] * gphys::vy[i]);
        top = max(top, gphys::py[i]); speed = max(speed, v); avg += v;
    }
    avg = avg / gphys::count();
    check("2000個: 床に落ち着く(10秒後: 高さ・平均の速さ)", top < 60.0 && avg < 0.3, str("いちばん上 y=", top, " 平均の速さ=", avg, " 最大=", speed));

    // 5. 決定論: 同じ入力 → 同じハッシュ / 違う乱数 → 違うハッシュ
    var hs: u64[3] = [0, 0, 0];
    for t in 3 {
        setup(-9.8);
        pile(800, if t < 2 { 11 } else { 12 });
        for s in 120 { gphys::step(1.0 / 60.0, 4); }
        hs[t] = gphys::state_hash();
    }
    check("決定論: 同じシードは同じ結果", hs[0] == hs[1], str(hs[0], " / ", hs[1]));
    check("決定論: 違うシードは違う結果", hs[0] != hs[2], str(hs[2]));

    // 6. 並べ直し: 物体の数・位置の合計は変わらず、uid で同じ物体をたどれる
    setup(-9.8);
    pile(500, 3);
    for s in 30 { gphys::step(1.0 / 60.0, 4); }
    let k7 = gphys::index_of_uid(7);
    let x7 = gphys::px[k7]; let y7 = gphys::py[k7];
    var sum0: f64 = 0.0;
    for i in gphys::count() { sum0 += gphys::px[i] + gphys::py[i]; }
    gphys::reorder();
    var sum1: f64 = 0.0;
    for i in gphys::count() { sum1 += gphys::px[i] + gphys::py[i]; }
    let k7b = gphys::index_of_uid(7);
    check("並べ直し: 位置の合計が同じ", abs(sum1 - sum0) < 1.0e-3, str(sum0, " / ", sum1));
    check("並べ直し: uid 7 は同じ場所", gphys::px[k7b] == x7 && gphys::py[k7b] == y7, str("番号 ", k7, " → ", k7b));
    var seen: bool[>..] = [];
    for i in gphys::count() { seen.push(false); }
    var dup = 0;
    for i in gphys::count() { let u = gphys::uid[i] as i64; if seen[u] { dup += 1; } seen[u] = true; }
    check("並べ直し: uid は重複なし", dup == 0, str(dup));

    // 7. はね返り: restitution 0.8 の玉は、床から 0 より高くはね返る
    setup(-9.8);
    gphys::restitution = 0.8;
    gphys::add(50.0, 30.0, 0.5, 1.0);
    let floor_ball = gphys::add(50.0, 10.0, 0.9, 0.0);
    var peak: f32 = 0.0;
    var hit = false;
    for s in 180 {
        gphys::step(1.0 / 60.0, 8);
        if gphys::vy[0] > 0.0 { hit = true; }
        if hit { peak = max(peak, gphys::py[0]); }
    }
    check("はね返り: 当たった後に上へ", hit && peak > 15.0, str("最高 y=", peak));

    // 8. 摩擦: 床の上をすべる玉は止まる / ふれ合って逆向きにずれる2つの玉は、ずれが減り、エネルギーが増えない
    setup(-9.8);
    gphys::friction = 0.4;
    let b0 = gphys::add(25.0, 0.5, 0.5, 1.0);
    gphys::set_velocity(b0, 5.0, 0.0);
    var fastest: f32 = 0.0;
    for s in 60 { gphys::step(1.0 / 60.0, 6); fastest = max(fastest, abs(gphys::vx[b0])); }
    check("摩擦: 床の上で 止まる", abs(gphys::vx[b0]) < 0.5 && fastest < 5.05, str("1秒後 ", abs(gphys::vx[b0]), "/秒  最大 ", fastest, "/秒(はじめ 5)"));
    setup(0.0);
    gphys::friction = 0.4;
    let p = gphys::add(50.0, 50.0, 0.5, 1.0);
    let q = gphys::add(50.0, 50.999, 0.5, 1.0);
    gphys::set_velocity(p, 2.0, 0.0);
    gphys::set_velocity(q, -2.0, 0.0);
    let ke0 = 2.0 * 2.0 + 2.0 * 2.0;
    gphys::step(1.0 / 60.0, 1);
    let slip = gphys::vx[p] - gphys::vx[q];
    let ke1 = gphys::vx[p] * gphys::vx[p] + gphys::vy[p] * gphys::vy[p] + gphys::vx[q] * gphys::vx[q] + gphys::vy[q] * gphys::vy[q];
    check("摩擦: ずれる速さが減る(符号の確認)", slip < 4.0 && slip > 0.0, str("ずれ 4 → ", slip));
    check("摩擦: エネルギーが増えない", ke1 <= ke0 + 1.0e-4, str("2倍の運動エネルギー ", ke0, " → ", ke1));

    print("");
    if fails == 0 { print("すべて OK"); } else { print("NG ", fails, " 件"); exit(1); }
}
