# gphys-physics-2d — a lightweight, fast 2D physics engine in Goose

English | [日本語](README.ja.md)

`gphys` simulates rigid circles with position-based dynamics (PBD) and a uniform grid. The whole engine is one file, `gphys.goose` (about 430 lines). It uses no external libraries and allocates nothing while stepping. The same input always gives the same result.

- Language: [Goose](https://github.com/aardappel/goose) v2026.3
- Usage, examples and benchmarks in one page: `docs/showcase.html` (open it in a browser; the text is in Japanese)

## Features
- Rigid circles with gravity, restitution, friction and linear damping
- Static bodies: create a body with mass 0 (pegs, walls, floors)
- A world box whose walls also apply restitution and friction
- `explode(x, y, reach, power)`: push bodies outward from a point
- `is_free(x, y, r)`: check whether a circle fits before spawning it
- `reorder()`: sort the bodies in memory by grid cell. `uid` keeps track of each body
- `state_hash()`: a hash of the whole state, for checking lockstep and replay sync

## Usage
```goose
import .gphys;

fn main() {
    gphys::world(0.0, 0.0, 100.0, 100.0, 1.0);   // world box and cell size (>= the largest diameter)
    gphys::gy = -9.8;
    gphys::restitution = 0.2;
    let ball = gphys::add(50.0, 80.0, 0.5, 1.0);  // x, y, radius, mass (0 = static)
    gphys::add(50.0, 20.0, 0.5, 0.0);             // a static peg
    for f in 60 { gphys::step(1.0 / 60.0, 4); }   // 1/60 s in 4 substeps
    print(gphys::px[ball], ", ", gphys::py[ball]);
}
```
From another directory, put `import gphys from "<relative path to this directory>";` in the root file (see `examples/`).

All settings are plain variables:

| Variable | Meaning |
|---|---|
| `gx`, `gy` | Gravity |
| `restitution` | Bounciness, 0 to 1. Applies only when bodies approach faster than `2 × 9.8 × h`, so stacks come to rest |
| `friction` | 0 to 1. While bodies touch, each substep removes this fraction of their sliding speed (strong; 0.05 to 0.4 is typical) |
| `damping` | Air drag, per second |
| `relax` | How much of an overlap one pass removes (1 = all of it) |
| `max_push_speed` | Cap on the speed that overlap correction may add, so deep overlaps do not explode |

## Files
| Path | Contents |
|---|---|
| `gphys.goose` | The engine |
| `test.goose` | 18 checks: free fall, overlap, center of mass, static bodies, a 2000-body pile, determinism, reordering, restitution, friction |
| `bench.goose` | Benchmark from 1,000 to 100,000 bodies |
| `examples/` | Galton board, crowd, sand pile, explosion (`pic.goose` draws the pictures) |
| `compare/` | The same algorithm in hand-written C and JavaScript, plus an all-pairs version. `run.sh` measures them all |
| `docs/` | The showcase page (`tools/build_showcase.py` embeds the pictures) |
| `tools/ppm2png.py` | Converts the examples' PPM output to PNG, with no dependencies |

```sh
goose test.goose                               # run in-process (TinyCC)
goose build bench.goose && ./bench             # build with the system C compiler
cd examples && goose build galton.goose && ./galton && python3 ../tools/ppm2png.py galton.ppm
cd compare && goose build cmp.goose && gcc -O2 -o ref ref.c -lm && ./run.sh
```

## Performance
Measured in a cloud container: one core, gcc 13.3 `-O2`, Node 22, median of 3 runs. One frame is 1/60 s in 4 substeps. The box is half filled with circles that fall under gravity.

| Bodies | Goose | Hand-written C | JavaScript | All pairs (Goose) |
|---:|---:|---:|---:|---:|
| 1,000 | 0.26 ms | 0.25 ms | 0.33 ms | 2.64 ms |
| 5,000 | 1.26 ms | 1.16 ms | 1.76 ms | 66.46 ms |
| 10,000 | 2.16 ms | 2.10 ms | 3.40 ms | — |
| 50,000 | 8.22 ms | 8.57 ms | 11.84 ms | — |
| 100,000 | 17.03 ms | 17.23 ms | 29.30 ms | — |

- Goose and hand-written C report exactly the same contact counts at every size, so they compute the same thing
- Other processes shared the machine, so timings vary by 10 to 20% between runs. Your hardware will give different numbers

## Why it is fast
1. Every substep, a counting sort (O(n)) gathers the circles into scratch arrays ordered by grid cell
2. "This cell + the cell to the right" and "the three cells in the row below" are each one contiguous range in memory. Only this half of the neighborhood is checked, so no pair is tested twice
3. Cell ranges use Goose's index type `u32 upto sx`, so the compiler removes the bounds checks from the hot loop (check with `goose --bce-lines`)
4. Circle a stays in local variables while the loop walks its neighbors
5. Nothing is allocated or moved during a step

## Limitations
- Circles only. No rotation, boxes, polygons or joints
- Deep stacks keep a little jitter (mean speed 0.2/s in a 2000-body pile). More substeps reduce it
- Single-threaded
- No way to remove a single body (`reset()` clears everything)
- Determinism was verified on one machine (gcc and TinyCC builds give the same hash). Bit-exact results across different CPUs have not been tested

## License
MIT. See [LICENSE](LICENSE).
