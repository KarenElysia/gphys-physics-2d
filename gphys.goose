// gphys: 軽量・高速な 2D 物理エンジン(円の剛体)
//
// しくみ(1ステップ = substeps 回の小さなステップ):
//   1. 積分     : 速度に重力を足し、位置を進める(衝突の前の位置を q に残す)
//   2. 整列     : 一様グリッドに数え上げソート(O(n)・ヒープ確保なし)して、
//                 位置・半径・質量を「マスの順に並んだ作業用の配列 s*」へ集める
//   3. 衝突     : 同じマス+右のマス(=連続した1区間)と、下の行の3マス(=連続した1区間)
//                 だけを見て、重なりを質量の逆数の比で押し戻す(位置ベース・半分の近傍)
//   4. 壁       : 世界の箱の内側へ押し戻す
//   5. もどす   : 位置を元の並びへ戻し、v += (p - q) / h で押し戻した分だけ速度を変える
//                 (その速さには上限 max_push_speed。深く重なっても、はじけ飛ばない)
//   + restitution(はね返り)と friction(摩擦)を、ふれている組の速度へ足す
//
// 速さの工夫:
//   - SoA(性質ごとの配列)。ステップ中に確保も移動も起きない
//   - 作業用の配列は、マスの順に並んでいる → 近い物体はメモリでも近い(キャッシュに乗る)
//   - マスの区間は `u32 upto sx`(Goose のインデックス型)なので、
//     いちばん熱いループ(円どうしの判定)の配列の読み書きに、境界チェックが残らない
//   - ループの順番は決まっているので、同じ入力なら必ず同じ結果になる(決定論)
import std;
import math;

namespace gphys;

// ---- 設定 ----
var gx: f32 = 0.0;           // 重力
var gy: f32 = -9.8;
var bx0: f32 = 0.0;          // 世界の箱
var by0: f32 = 0.0;
var bx1: f32 = 100.0;
var by1: f32 = 100.0;
var cs: f32 = 1.0;           // マスの大きさ(いちばん大きい直径以上)
var ics: f32 = 1.0;          // 1 / cs
var gw: i64 = 1;             // マスの数(横・縦)
var gh: i64 = 1;
var relax: f32 = 1.0;        // 押し戻しの強さ(1=重なりを全部なくす)
var restitution: f32 = 0.0;  // はね返り(0〜1)
var friction: f32 = 0.0;     // 摩擦(0〜1: ふれている組の、接線方向の速度を減らす割合)
var damping: f32 = 0.0;      // 空気抵抗(1秒あたり)
var max_push_speed: f32 = 20.0;   // 押し戻しで生まれる速さの上限(深く重なった時に、はじけ飛ばない)

// ---- 物体(SoA・作った順) ----
var px: f32[>..] = [];       // 位置
var py: f32[>..] = [];
var vx: f32[>..] = [];       // 速度
var vy: f32[>..] = [];
var qx: f32[>..] = [];       // 衝突を解く前の位置(小さなステップごと)
var qy: f32[>..] = [];
var rad: f32[>..] = [];      // 半径
var im: f32[>..] = [];       // 質量の逆数(0=動かない)
var uid: i32[>..] = [];      // 作った順の番号(reorder の後も、同じ物体を指す)

// ---- マスの順に並んだ作業用(縮めない: インデックス型 `u32 in sx` が指す配列のため) ----
var sx: f32[>..] = [];
var sy: f32[>..] = [];
var sr: f32[>..] = [];
var sm: f32[>..] = [];
var svx: f32[>..] = [];
var svy: f32[>..] = [];
type Slot = u32 in sx;

// ---- グリッド ----
var cstart: (u32 upto sx)[>..] = [];   // マス c の物体は s*[cstart[c] .. cstart[c+1]]
var ccur: i32[>..] = [];               // 数える・詰める時のカーソル
var order: i32[>..] = [];              // order[k] = 作業用の k 番目にいる物体
var cell: i32[>..] = [];               // 物体ごとのマス
var tmpf: f32[>..] = [];               // reorder の作業用
var tmpi: i32[>..] = [];

// ---- 統計(最後のステップ) ----
var pairs_tested: i64 = 0;
var contacts: i64 = 0;

fn count() -> i64 { px.len }

// 世界の箱と、マスの大きさ(いちばん大きい物体の直径以上にする)
fn world(x0: f32, y0: f32, x1: f32, y1: f32, cell_size: f32) {
    assert(x1 > x0 && y1 > y0 && cell_size > 0.0);
    bx0 = x0; by0 = y0; bx1 = x1; by1 = y1;
    cs = cell_size; ics = 1.0 / cell_size;
    gw = max(1, ceil((x1 - x0) * ics) as i64);
    gh = max(1, ceil((y1 - y0) * ics) as i64);
    cstart.clear(); ccur.clear();
    let zero = 0 as (u32 upto sx);
    for c in gw * gh + 1 { cstart.push(zero); ccur.push(0); }
}

// 円を足す。mass <= 0 は動かない物体。番号(uid)を返す
fn add(x: f32, y: f32, r: f32, mass: f32) -> i64 {
    assert(r > 0.0 && 2.0 * r <= cs);
    let id = px.len;
    px.push(x); py.push(y); vx.push(0.0); vy.push(0.0); qx.push(x); qy.push(y);
    rad.push(r); im.push(if mass > 0.0 { 1.0 / mass } else { 0.0 });
    uid.push(id as i32); order.push(0); cell.push(0); tmpf.push(0.0); tmpi.push(0);
    while sx.len < px.len { sx.push(0.0); sy.push(0.0); sr.push(0.0); sm.push(0.0); svx.push(0.0); svy.push(0.0); }
    return id;
}

fn set_velocity(i: i64, x: f32, y: f32) { vx[i] = x; vy[i] = y; }

// マスの番号(箱の外は、いちばん近い端のマス)
inline fn cell_of(x: f32, y: f32) -> i64 {
    let cx = clamp(((x - bx0) * ics) as! i64, 0, gw - 1);
    let cy = clamp(((y - by0) * ics) as! i64, 0, gh - 1);
    return cy * gw + cx;
}

// 数え上げソート(O(n + マス数))をして、位置・半径・質量を作業用へ集める
fn build_grid() {
    let n = px.len;
    let nc = gw * gh;
    assert(cstart.len == nc + 1 && ccur.len == nc + 1);
    assert(cell.len == n && order.len == n && py.len == n && rad.len == n && im.len == n);
    assert(sx.len >= n && sy.len == sx.len && sr.len == sx.len && sm.len == sx.len);
    for c in nc + 1 { ccur[c] = 0; }
    for i in n {
        let c = cell_of(px[i], py[i]);
        cell[i] = c as! i32;
        ccur[c + 1] += 1;
    }
    var run: i64 = 0;
    for c in nc + 1 {
        run += ccur[c];
        ccur[c] = run as! i32;            // マス c のはじまり
        cstart[c] = run as (u32 upto sx);
    }
    for i in n {
        let c = cell[i];
        let k = ccur[c];
        ccur[c] = k + 1;
        order[k] = i as! i32;
        sx[k] = px[i]; sy[k] = py[i]; sr[k] = rad[i]; sm[k] = im[i];
    }
}

// 近くにいる組(a, b)を、それぞれ1回ずつ F に渡す(作業用の番号)
//   同じマス+右のマス = cstart[c] .. cstart[c+2] の1区間(a より後ろだけ)
//   下の行の3マス     = cstart[左下] .. cstart[右下+1] の1区間
fn each_near_pair<F>() {
    assert(cstart.len == gw * gh + 1);
    for cy in gh {
        for cx in gw {
            let c = cy * gw + cx;
            let a0 = cstart[c];
            let a1 = cstart[c + 1];
            let r1 = if cx + 1 < gw { cstart[c + 2] } else { a1 };
            var d0 = a0;
            var d1 = a0;
            if cy + 1 < gh {
                d0 = cstart[if cx > 0 { c + gw - 1 } else { c + gw }];
                d1 = cstart[if cx + 1 < gw { c + gw + 2 } else { c + gw + 1 }];
            }
            for a in a0..a1 {
                let a_next = (a + 1) as (u32 upto sx);
                pairs_tested += (r1 - a_next) + (d1 - d0);
                for b in a_next..r1 { F(a, b); }
                for b in d0..d1 { F(a, b); }
            }
        }
    }
}

// a と、作業用の区間 [b0, b1) の物体の重なりを解く。a の値はローカル(レジスタ)に置いたまま
inline fn solve_range(ax: f32&, ay: f32&, ar: f32, am: f32, b0: u32 upto sx, b1: u32 upto sx, k_relax: f32) -> i64 {
    var hits: i64 = 0;
    for b in b0..b1 {
        let dx = sx[b] - ax;
        let dy = sy[b] - ay;
        let r = ar + sr[b];
        let d2 = dx * dx + dy * dy;
        if d2 < r * r && d2 > 1.0e-12 {
            let mb = sm[b];
            let w = am + mb;
            if w > 0.0 {
                let d = sqrt(d2);
                let k = (r - d) / (d * w) * k_relax;
                ax -= dx * k * am; ay -= dy * k * am;
                sx[b] += dx * k * mb; sy[b] += dy * k * mb;
                hits += 1;
            }
        }
    }
    return hits;
}

// 2つの円の重なりを解く(位置ベース・作業用の配列の上で。組の回し方は each_near_pair と同じ)
fn solve_contacts() {
    assert(sy.len == sx.len && sr.len == sx.len && sm.len == sx.len);
    assert(cstart.len == gw * gh + 1);
    let k_relax = relax;
    var hits: i64 = 0;
    var tested: i64 = 0;
    for cy in gh {
        for cx in gw {
            let c = cy * gw + cx;
            let a0 = cstart[c];
            let a1 = cstart[c + 1];
            let r1 = if cx + 1 < gw { cstart[c + 2] } else { a1 };
            var d0 = a0;
            var d1 = a0;
            if cy + 1 < gh {
                d0 = cstart[if cx > 0 { c + gw - 1 } else { c + gw }];
                d1 = cstart[if cx + 1 < gw { c + gw + 2 } else { c + gw + 1 }];
            }
            for a in a0..a1 {
                var ax = sx[a];
                var ay = sy[a];
                let ar = sr[a];
                let am = sm[a];
                let a_next = (a + 1) as (u32 upto sx);
                tested += (r1 - a_next) + (d1 - d0);
                hits += solve_range(ax, ay, ar, am, a_next, r1, k_relax);
                hits += solve_range(ax, ay, ar, am, d0, d1, k_relax);
                sx[a] = ax; sy[a] = ay;
            }
        }
    }
    contacts += hits;
    pairs_tested += tested;
}

// ふれている組の速度に、はね返りと摩擦を足す(作業用の配列の上で)
fn velocity_contacts(h: f32) {
    assert(sy.len == sx.len && sr.len == sx.len && sm.len == sx.len && svx.len == sx.len && svy.len == sx.len);
    let e_on = restitution;
    let fr = friction;
    let slow = 2.0 * 9.8 * h;   // これより遅くぶつかる組は、はねない(積み重なりが落ち着く)
    let touch = 1.0e-3 * cs;    // くっついている組も含める
    each_near_pair() { a, b =>
        let dx = sx[b] - sx[a];
        let dy = sy[b] - sy[a];
        let r = sr[a] + sr[b] + touch;
        let d2 = dx * dx + dy * dy;
        if d2 < r * r && d2 > 1.0e-12 {
            let ma = sm[a];
            let mb = sm[b];
            let w = ma + mb;
            let d = sqrt(d2);
            let nx = dx / d;
            let ny = dy / d;
            let rvx = svx[b] - svx[a];
            let rvy = svy[b] - svy[a];
            let vn = rvx * nx + rvy * ny;
            if w > 0.0 {
                // はね返り: 近づいている時だけ(遅い組は はねない=積み重なりが落ち着く)
                let e = if vn < 0.0 - slow { e_on } else { 0.0 };
                let jn = if vn < 0.0 { (0.0 - (1.0 + e) * vn) / w } else { 0.0 };
                // 摩擦: ふれている間は いつも(押し戻しの後は vn が 0 近くなので、近づく時だけにすると効かない)
                // 相対速度の接線の分を fr の割合だけ減らす向き(符号に注意: 減らすので マイナス)
                let jt = 0.0 - fr / w;
                let ix = nx * jn + (rvx - vn * nx) * jt;
                let iy = ny * jn + (rvy - vn * ny) * jt;
                svx[a] -= ix * ma; svy[a] -= iy * ma;
                svx[b] += ix * mb; svy[b] += iy * mb;
            }
        }
    };
}

// 壁・床にふれている物体の速度に、はね返りと摩擦を足す(作業用の配列の上で)
//   ふれている向きの速さは、押し戻しでもう 0 近くになっているので、
//   はね返りは「押し戻す前の速さ」= (svx - 押し戻しの分) から作る
fn wall_contacts(h: f32, n: i64) {
    assert(sx.len >= n && sy.len == sx.len && sr.len == sx.len && sm.len == sx.len && svx.len == sx.len && svy.len == sx.len);
    assert(order.len == n && qx.len == n && qy.len == n);
    let tol = 1.0e-3 * cs;
    let slow = 2.0 * 9.8 * h;
    let keep_t = 1.0 - friction;
    let ih = 1.0 / h;
    for k in n {
        guard sm[k] > 0.0 else { continue; }
        let r = sr[k] + tol;
        let i = order[k];
        let prex = svx[k] - (sx[k] - qx[i]) * ih;   // 押し戻す前の速さ(近い値)
        let prey = svy[k] - (sy[k] - qy[i]) * ih;
        if sy[k] <= by0 + r || sy[k] >= by1 - r {   // 床・天井
            svx[k] *= keep_t;
            let into = if sy[k] <= by0 + r { prey < 0.0 - slow } else { prey > slow };
            if into { svy[k] = 0.0 - restitution * prey; }
        }
        if sx[k] <= bx0 + r || sx[k] >= bx1 - r {   // 左右の壁
            svy[k] *= keep_t;
            let into = if sx[k] <= bx0 + r { prex < 0.0 - slow } else { prex > slow };
            if into { svx[k] = 0.0 - restitution * prex; }
        }
    }
}

// 1ステップ(dt 秒)を substeps 回に分けて進める
fn step(dt: f32, substeps: i64) {
    let n = px.len;
    assert(substeps > 0 && dt > 0.0);
    assert(py.len == n && vx.len == n && vy.len == n && qx.len == n && qy.len == n && rad.len == n && im.len == n && order.len == n);
    assert(sx.len >= n && sy.len == sx.len && sr.len == sx.len && svx.len == sx.len && svy.len == sx.len);
    let h = dt / substeps;
    let ih = 1.0 / h;
    let keep = max(0.0, 1.0 - damping * h);
    let vel = restitution > 0.0 || friction > 0.0;
    let cap2 = max_push_speed * max_push_speed;
    pairs_tested = 0; contacts = 0;
    for s in substeps {
        // 1. 積分(q = 衝突を解く前の、予想の位置)
        for i in n {
            if im[i] > 0.0 {
                vx[i] = (vx[i] + gx * h) * keep;
                vy[i] = (vy[i] + gy * h) * keep;
                px[i] += vx[i] * h;
                py[i] += vy[i] * h;
            }
            qx[i] = px[i]; qy[i] = py[i];
        }
        // 2-3. 整列して、衝突を解く
        build_grid();
        solve_contacts();
        // 4. 壁(作業用の上で)
        for k in n {
            let r = sr[k];
            sx[k] = clamp(sx[k], bx0 + r, bx1 - r);
            sy[k] = clamp(sy[k], by0 + r, by1 - r);
        }
        // 5. 元の並びへ戻し、押し戻した分だけ速度を変える(押されていない物体は f32 の丸めが入らない)
        for k in n {
            let i = order[k];
            if im[i] > 0.0 {
                px[i] = sx[k]; py[i] = sy[k];
                var dvx = (px[i] - qx[i]) * ih;
                var dvy = (py[i] - qy[i]) * ih;
                let d2 = dvx * dvx + dvy * dvy;
                if d2 > cap2 { let k2 = sqrt(cap2 / d2); dvx *= k2; dvy *= k2; }   // 位置はそのまま・速さだけ上限
                vx[i] += dvx;
                vy[i] += dvy;
            } else {
                vx[i] = 0.0; vy[i] = 0.0;   // 動かない物体は、そのまま
            }
        }
        // 6. はね返り・摩擦(使う時だけ)
        if vel {
            for k in n { let i = order[k]; svx[k] = vx[i]; svy[k] = vy[i]; }
            velocity_contacts(h);
            wall_contacts(h, n);
            for k in n { let i = order[k]; vx[i] = svx[k]; vy[i] = svy[k]; }
        }
    }
}

// 物体そのものを、マスの順に並べ直す(作った順がバラバラな時、元の並びの読み書きも速くなる)
// uid で同じ物体をたどれる
fn reorder() {
    build_grid();
    let n = px.len;
    assert(order.len == n && tmpf.len == n && tmpi.len == n && uid.len == n);
    permute_f(px); permute_f(py); permute_f(vx); permute_f(vy);
    permute_f(qx); permute_f(qy); permute_f(rad); permute_f(im);
    for k in n { tmpi[k] = uid[order[k]]; }
    for k in n { uid[k] = tmpi[k]; }
}

fn permute_f(a: f32[>..]&) {
    let n = a.len;
    assert(order.len == n && tmpf.len == n);
    for k in n { tmpf[k] = a[order[k]]; }
    for k in n { a[k] = tmpf[k]; }
}

// (x, y) に半径 r の円を置いても、どれとも重ならないか(O(n)。物を出す前の確認用)
fn is_free(x: f32, y: f32, r: f32) -> bool {
    let n = px.len;
    assert(py.len == n && rad.len == n);
    for i in n {
        let dx = px[i] - x;
        let dy = py[i] - y;
        let rr = rad[i] + r;
        if dx * dx + dy * dy < rr * rr { return false; }
    }
    return true;
}

// 爆発: (x, y) から半径 reach の中の動く物体を、外向きに吹き飛ばす(中心に近いほど強い・重いほど弱い)
fn explode(x: f32, y: f32, reach: f32, power: f32) -> i64 {
    let n = px.len;
    assert(py.len == n && vx.len == n && vy.len == n && im.len == n);
    var hit: i64 = 0;
    for i in n {
        let dx = px[i] - x;
        let dy = py[i] - y;
        let d2 = dx * dx + dy * dy;
        if im[i] > 0.0 && d2 < reach * reach && d2 > 1.0e-12 {
            let d = sqrt(d2);
            let k = power * (1.0 - d / reach) * im[i] / d;
            vx[i] += dx * k; vy[i] += dy * k;
            hit += 1;
        }
    }
    return hit;
}

// uid から、いまの番号をさがす(テスト・表示用。O(n))
fn index_of_uid(id: i64) -> i64 {
    for k in uid.len { if uid[k] == id { return k; } }
    return -1;
}

// 状態のハッシュ(決定論の確認用)
fn state_hash() -> u64 {
    var h: u64 = 1469598103934665603;
    for i in px.len {
        h = hash_combine(h, hash(px[i]));
        h = hash_combine(h, hash(py[i]));
        h = hash_combine(h, hash(vx[i]));
        h = hash_combine(h, hash(vy[i]));
    }
    return h;
}

// いちばん深い重なり(小さいほうの半径に対する割合)。テスト用
fn max_overlap_ratio() -> f32 {
    build_grid();
    var worst: f32 = 0.0;
    each_near_pair() { a, b =>
        let dx = sx[b] - sx[a];
        let dy = sy[b] - sy[a];
        let r = sr[a] + sr[b];
        let d = sqrt(dx * dx + dy * dy);
        if d < r { worst = max(worst, (r - d) / min(sr[a], sr[b])); }
    };
    return worst;
}

// ぜんぶ消す(設定と、作業用の配列の大きさは残す)
fn reset() {
    px.clear(); py.clear(); vx.clear(); vy.clear(); qx.clear(); qy.clear();
    rad.clear(); im.clear(); uid.clear(); order.clear(); cell.clear(); tmpf.clear(); tmpi.clear();
}
