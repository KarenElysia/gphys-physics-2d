// 比較用: gphys.goose と同じアルゴリズムを、手で書いた C(gcc -O2)
// 使い方: gcc -O2 -o ref ref.c -lm && ./ref 10000 120
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static int n, gw, gh;
static float *px, *py, *vx, *vy, *qx, *qy, *rad, *im, *sx, *sy, *sr, *sm;
static int *cstart, *ccur, *order, *cell;
static float bx0 = 0, by0 = 0, bx1, by1, ics = 1, gy = -9.8f, max_push = 20;
static long contacts;

static int cell_of(float x, float y) {
  int cx = (int)((x - bx0) * ics), cy = (int)((y - by0) * ics);
  if (cx < 0) cx = 0; if (cx > gw - 1) cx = gw - 1;
  if (cy < 0) cy = 0; if (cy > gh - 1) cy = gh - 1;
  return cy * gw + cx;
}

static void build_grid(void) {
  int nc = gw * gh;
  for (int c = 0; c <= nc; c++) ccur[c] = 0;
  for (int i = 0; i < n; i++) { int c = cell_of(px[i], py[i]); cell[i] = c; ccur[c + 1]++; }
  int run = 0;
  for (int c = 0; c <= nc; c++) { run += ccur[c]; ccur[c] = run; cstart[c] = run; }
  for (int i = 0; i < n; i++) {
    int c = cell[i], k = ccur[c]++;
    order[k] = i; sx[k] = px[i]; sy[k] = py[i]; sr[k] = rad[i]; sm[k] = im[i];
  }
}

static long solve_range(float *ax, float *ay, float ar, float am, int b0, int b1) {
  long hits = 0;
  for (int b = b0; b < b1; b++) {
    float dx = sx[b] - *ax, dy = sy[b] - *ay, r = ar + sr[b], d2 = dx * dx + dy * dy;
    if (d2 < r * r && d2 > 1e-12f) {
      float mb = sm[b], w = am + mb;
      if (w > 0) {
        float d = sqrtf(d2), k = (r - d) / (d * w);
        *ax -= dx * k * am; *ay -= dy * k * am; sx[b] += dx * k * mb; sy[b] += dy * k * mb; hits++;
      }
    }
  }
  return hits;
}

static void solve(void) {
  for (int cy = 0; cy < gh; cy++)
    for (int cx = 0; cx < gw; cx++) {
      int c = cy * gw + cx, a0 = cstart[c], a1 = cstart[c + 1];
      int r1 = cx + 1 < gw ? cstart[c + 2] : a1, d0 = a0, d1 = a0;
      if (cy + 1 < gh) { d0 = cstart[cx > 0 ? c + gw - 1 : c + gw]; d1 = cstart[cx + 1 < gw ? c + gw + 2 : c + gw + 1]; }
      for (int a = a0; a < a1; a++) {
        float ax = sx[a], ay = sy[a], ar = sr[a], am = sm[a];
        contacts += solve_range(&ax, &ay, ar, am, a + 1, r1);
        contacts += solve_range(&ax, &ay, ar, am, d0, d1);
        sx[a] = ax; sy[a] = ay;
      }
    }
}

static void step(float dt, int subs) {
  float h = dt / subs, ih = 1 / h, cap2 = max_push * max_push;
  contacts = 0;
  for (int s = 0; s < subs; s++) {
    for (int i = 0; i < n; i++) {
      if (im[i] > 0) { vy[i] += gy * h; px[i] += vx[i] * h; py[i] += vy[i] * h; }
      qx[i] = px[i]; qy[i] = py[i];
    }
    build_grid(); solve();
    for (int k = 0; k < n; k++) {
      float r = sr[k];
      sx[k] = fminf(fmaxf(sx[k], bx0 + r), bx1 - r);
      sy[k] = fminf(fmaxf(sy[k], by0 + r), by1 - r);
    }
    for (int k = 0; k < n; k++) {
      int i = order[k];
      if (im[i] > 0) {
        px[i] = sx[k]; py[i] = sy[k];
        float dvx = (px[i] - qx[i]) * ih, dvy = (py[i] - qy[i]) * ih, d2 = dvx * dvx + dvy * dvy;
        if (d2 > cap2) { float k2 = sqrtf(cap2 / d2); dvx *= k2; dvy *= k2; }
        vx[i] += dvx; vy[i] += dvy;
      } else { vx[i] = 0; vy[i] = 0; }
    }
  }
}

static float *fa(int m) { return calloc(m, sizeof(float)); }
static int *ia(int m) { return calloc(m, sizeof(int)); }

int main(int argc, char **argv) {
  n = argc > 1 ? atoi(argv[1]) : 10000;
  int frames = argc > 2 ? atoi(argv[2]) : 120;
  float size = ceilf(sqrtf(n * 2.2f));
  bx1 = size; by1 = size; gw = gh = (int)ceilf(size);
  px = fa(n); py = fa(n); vx = fa(n); vy = fa(n); qx = fa(n); qy = fa(n); rad = fa(n); im = fa(n);
  sx = fa(n); sy = fa(n); sr = fa(n); sm = fa(n);
  cstart = ia(gw * gh + 1); ccur = ia(gw * gh + 1); order = ia(n); cell = ia(n);
  int per_row = (int)(size / 1.05f) - 1;
  for (int k = 0; k < n; k++) {
    float j1 = (float)((k * 7919L + 13) % 1000) / 1000, j2 = (float)((k * 104729L + 7) % 1000) / 1000;
    px[k] = 0.6f + (k % per_row) * 1.05f + j1 * 0.04f; py[k] = 0.6f + (k / per_row) * 1.05f;
    rad[k] = 0.3f + j2 * 0.2f; im[k] = 1;
  }
  for (int f = 0; f < 30; f++) step(1 / 60.0f, 4);
  struct timespec t0, t1; clock_gettime(CLOCK_MONOTONIC, &t0);
  for (int f = 0; f < frames; f++) step(1 / 60.0f, 4);
  clock_gettime(CLOCK_MONOTONIC, &t1);
  double ms = ((t1.tv_sec - t0.tv_sec) * 1e3 + (t1.tv_nsec - t0.tv_nsec) / 1e6) / frames;
  printf("C %d %.3f %ld\n", n, ms, contacts);
  return 0;
}
