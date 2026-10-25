# PPM(P6) → PNG。外部ライブラリなし。使い方: python3 ppm2png.py a.ppm [b.ppm ...]
import struct, sys, zlib
for path in sys.argv[1:]:
    d = open(path, 'rb').read()
    head, px = d.split(b'\n', 1)
    _, w, h, _ = head.split(); w, h = int(w), int(h)
    raw = b''.join(b'\x00' + px[y * w * 3:(y + 1) * w * 3] for y in range(h))
    ch = lambda t, b: struct.pack('>I', len(b)) + t + b + struct.pack('>I', zlib.crc32(t + b) & 0xffffffff)
    out = path[:-4] + '.png'
    open(out, 'wb').write(b'\x89PNG\r\n\x1a\n' + ch(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + ch(b'IDAT', zlib.compress(raw, 9)) + ch(b'IEND', b''))
    print(out, w, h)
