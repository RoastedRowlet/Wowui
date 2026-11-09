"""Generate PlateTweaks marker art as 32x32 uncompressed 32-bit TGAs.

White with an alpha channel, so the engine's SetVertexColor tints them the way
it tints every other texture this addon draws. Rendered at 8x and box-filtered
down, which is what gives a clean edge at marker sizes rather than the stair
step a hard-edged 32px source shows once the client scales it.
"""
import io, os, math

SS = 8          # supersample factor
N = 32          # final texture size (power of two, as WoW wants)
OUT = r'G:\World of Warcraft\_retail_\Interface\AddOns\PlateTweaks_Beta\media\markers'


def blank():
    return [[0.0] * (N * SS) for _ in range(N * SS)]


def fill_poly(buf, pts):
    """Scanline fill, coordinates in FINAL pixel space."""
    p = [(x * SS, y * SS) for (x, y) in pts]
    ys = [y for _, y in p]
    for y in range(max(0, int(min(ys))), min(N * SS, int(max(ys)) + 1)):
        xs = []
        for i in range(len(p)):
            x1, y1 = p[i]
            x2, y2 = p[(i + 1) % len(p)]
            if (y1 <= y < y2) or (y2 <= y < y1):
                t = (y - y1) / (y2 - y1)
                xs.append(x1 + t * (x2 - x1))
        xs.sort()
        for i in range(0, len(xs) - 1, 2):
            for x in range(max(0, int(xs[i])), min(N * SS, int(xs[i + 1]) + 1)):
                buf[y][x] = 1.0


def fill_circle(buf, cx, cy, r, inner=0.0):
    cx, cy, r, inner = cx * SS, cy * SS, r * SS, inner * SS
    for y in range(N * SS):
        for x in range(N * SS):
            d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
            if d <= r and d >= inner:
                buf[y][x] = 1.0


def downsample(buf):
    out = [[0.0] * N for _ in range(N)]
    for y in range(N):
        for x in range(N):
            total = 0.0
            for sy in range(SS):
                row = buf[y * SS + sy]
                for sx in range(SS):
                    total += row[x * SS + sx]
            out[y][x] = total / (SS * SS)
    return out


def write_tga(path, alpha):
    header = bytes([
        0, 0, 2, 0, 0, 0, 0, 0,
        0, 0, 0, 0,
        N & 0xFF, N >> 8,
        N & 0xFF, N >> 8,
        32,
        0x28,           # 8 alpha bits, top-down origin
    ])
    body = bytearray()
    for y in range(N):
        for x in range(N):
            a = int(round(max(0.0, min(1.0, alpha[y][x])) * 255))
            body += bytes((255, 255, 255, a))   # B, G, R, A -- white
    with open(path, 'wb') as f:
        f.write(header)
        f.write(bytes(body))


def rot(pts, turns):
    """Rotate points about the texture centre in quarter turns."""
    c = N / 2.0
    out = []
    for x, y in pts:
        dx, dy = x - c, y - c
        for _ in range(turns % 4):
            dx, dy = -dy, dx
        out.append((c + dx, c + dy))
    return out


os.makedirs(OUT, exist_ok=True)

# A solid triangle, pointing right, with a little breathing room at the tip.
TRI = [(6, 3), (27, 16), (6, 29)]

# A chevron: the triangle with a wedge taken out of its back.
CHEV_OUT = [(7, 2), (28, 16), (7, 30)]
CHEV_IN = [(7, 11), (17, 16), (7, 21)]

names = {}
for turns, side in ((0, 'right'), (1, 'down'), (2, 'left'), (3, 'up')):
    buf = blank()
    fill_poly(buf, rot(TRI, turns))
    names['arrow-%s' % side] = downsample(buf)

    buf = blank()
    fill_poly(buf, rot(CHEV_OUT, turns))
    hole = blank()
    fill_poly(hole, rot(CHEV_IN, turns))
    for y in range(N * SS):
        for x in range(N * SS):
            if hole[y][x]:
                buf[y][x] = 0.0
    names['chevron-%s' % side] = downsample(buf)

buf = blank(); fill_circle(buf, 16, 16, 12); names['circle'] = downsample(buf)
buf = blank(); fill_circle(buf, 16, 16, 13, 8.5); names['ring'] = downsample(buf)
buf = blank(); fill_poly(buf, [(16, 3), (29, 16), (16, 29), (3, 16)])
names['diamond'] = downsample(buf)
buf = blank(); fill_poly(buf, [(16, 2), (20, 12), (30, 16), (20, 20), (16, 30),
                               (12, 20), (2, 16), (12, 12)])
names['spark'] = downsample(buf)

for name, alpha in names.items():
    write_tga(os.path.join(OUT, name + '.tga'), alpha)
    print('wrote', name + '.tga')
