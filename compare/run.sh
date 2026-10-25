#!/bin/sh
# 比較をまとめて回す(3回の中央値)。出力: 種類 玉の数 ms 衝突
cd "$(dirname "$0")"
med() { sort -k3 -n | sed -n 2p; }
for n in 1000 5000 10000 50000 100000; do
  f=120; [ $n -ge 50000 ] && f=60
  for k in 1 2 3; do ./cmp grid $n $f; done | med
  for k in 1 2 3; do ./ref $n $f; done | med
  for k in 1 2 3; do node ref.mjs $n $f; done | med
done
for n in 1000 2000 5000; do
  f=20; [ $n -ge 5000 ] && f=5
  for k in 1 2 3; do ./cmp naive $n $f; done | med
done
