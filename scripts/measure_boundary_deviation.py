#!/usr/bin/env python3
"""Measure how far DOONY's bundled NY boundary strays from the authoritative one.

Downloads a US Census state boundary file, extracts New York, and reports the
distance from the bundled polygon to the reference along its whole length.

Why this exists: `borderBufferMeters` in LocationManager.swift is only a valid
safety net while the boundary's worst-case error stays inside it. Re-run this
after replacing ny_state_boundary.geojson, or before lowering that buffer.

    python3 scripts/measure_boundary_deviation.py            # vs cartographic (default)
    python3 scripts/measure_boundary_deviation.py --tiger    # vs TIGER legal boundary

No third-party packages: the shapefile reader below is deliberately minimal so
this runs on a stock Python 3. Results as of 2026-08-29 are in
scripts/fetch_ny_boundary.md.
"""
import argparse, json, math, os, struct, sys, tempfile, urllib.request, zipfile
from collections import defaultdict

CB    = ('https://www2.census.gov/geo/tiger/GENZ2023/shp/cb_2023_us_state_500k.zip', 'cb_2023_us_state_500k')
TIGER = ('https://www2.census.gov/geo/tiger/TIGER2023/STATE/tl_2023_us_state.zip',   'tl_2023_us_state')
BUNDLED = os.path.join(os.path.dirname(__file__), '..', 'DOONY', 'Resources', 'ny_state_boundary.geojson')
BUFFER_M = 2000.0   # keep in sync with borderBufferMeters in LocationManager.swift
CELL = 0.1

def read_dbf_field(path, field):
    with open(path,'rb') as f: b=f.read()
    nrec, hlen, rlen = struct.unpack('<I', b[4:8])[0], struct.unpack('<H', b[8:10])[0], struct.unpack('<H', b[10:12])[0]
    fields, off = [], 32
    while b[off] != 0x0D:
        nm = b[off:off+11].split(b'\0')[0].decode('latin-1')
        ln = b[off+16]
        fields.append((nm, ln)); off += 32
    idx = {n:i for i,(n,_) in enumerate(fields)}
    assert field in idx, list(idx)
    out=[]
    for r in range(nrec):
        base = hlen + r*rlen + 1
        pos = base
        for i,(nm,ln) in enumerate(fields):
            if i == idx[field]:
                out.append(b[pos:pos+ln].decode('latin-1').strip()); break
            pos += ln
    return out

def read_shp_polygons(path):
    """Returns list of records; each record is a list of rings (list of (lon,lat))."""
    with open(path,'rb') as f: b=f.read()
    total = struct.unpack('>I', b[24:28])[0]*2
    off, recs = 100, []
    while off < total:
        clen = struct.unpack('>I', b[off+4:off+8])[0]*2
        c = off+8
        stype = struct.unpack('<i', b[c:c+4])[0]
        if stype != 5:
            recs.append([]); off = c+clen; continue
        nparts, npts = struct.unpack('<ii', b[c+36:c+44])[0:2]
        parts = list(struct.unpack('<%di'%nparts, b[c+44:c+44+4*nparts]))
        pbase = c+44+4*nparts
        pts = struct.unpack('<%dd'%(2*npts), b[pbase:pbase+16*npts])
        rings=[]
        for i,s in enumerate(parts):
            e = parts[i+1] if i+1 < nparts else npts
            rings.append([(pts[2*j], pts[2*j+1]) for j in range(s,e)])
        recs.append(rings)
        off = c+clen
    return recs

def load_bundled(p):
    d=json.load(open(p)); f=d['features'][0] if 'features' in d else d
    g=f.get('geometry',f)
    return [r for poly in g['coordinates'] for r in poly] if g['type']=='MultiPolygon' else list(g['coordinates'])

def load_ref(base):
    codes=read_dbf_field(base+'.dbf','STUSPS'); recs=read_shp_polygons(base+'.shp')
    return recs[codes.index('NY')]

def segments(rings):
    return [(r[i], r[i+1]) for r in rings for i in range(len(r)-1)]

def index(segs):
    g=defaultdict(list)
    for s in segs:
        (x1,y1),(x2,y2)=s
        for cx in range(int(math.floor(min(x1,x2)/CELL)), int(math.floor(max(x1,x2)/CELL))+1):
            for cy in range(int(math.floor(min(y1,y2)/CELL)), int(math.floor(max(y1,y2)/CELL))+1):
                g[(cx,cy)].append(s)
    return g

def densify(rings, step_m=250.0):
    out=[]
    for r in rings:
        for i in range(len(r)-1):
            (x1,y1),(x2,y2)=r[i],r[i+1]
            sx=111320.0*math.cos(math.radians((y1+y2)/2)); sy=110540.0
            d=math.hypot((x2-x1)*sx,(y2-y1)*sy)
            n=max(1,int(d//step_m))
            for k in range(n):
                t=k/n; out.append((x1+(x2-x1)*t, y1+(y2-y1)*t))
    return out

def dist_to_seg(px,py,ax,ay,bx,by,sx,sy):
    ax,ay=(ax-px)*sx,(ay-py)*sy; bx,by=(bx-px)*sx,(by-py)*sy
    dx,dy=bx-ax,by-ay; L=dx*dx+dy*dy
    if L==0: return math.hypot(ax,ay)
    t=max(0.0,min(1.0,-(ax*dx+ay*dy)/L))
    return math.hypot(ax+t*dx, ay+t*dy)

def nearest(pt, grid):
    px,py=pt; sx=111320.0*math.cos(math.radians(py)); sy=110540.0
    cx,cy=int(math.floor(px/CELL)),int(math.floor(py/CELL))
    best=float('inf'); rad=1
    while rad<=60:
        cand=[]
        for i in range(cx-rad,cx+rad+1):
            for j in range(cy-rad,cy+rad+1):
                if max(abs(i-cx),abs(j-cy))==rad or rad==1: cand+=grid.get((i,j),())
        for (a,b) in cand:
            d=dist_to_seg(px,py,a[0],a[1],b[0],b[1],sx,sy)
            if d<best: best=d
        # safe once the searched box half-width exceeds best
        if best < (rad*CELL*110540.0*0.9): return best
        rad+=1
    return best

def pct(v,p): 
    v=sorted(v); return v[min(len(v)-1,int(len(v)*p))]

def report(name, samples, grid):
    ds=[(nearest(p,grid),p) for p in samples]
    vals=[d for d,_ in ds]
    worst=max(ds)
    print('  %-26s n=%d  median %6.0f m   p90 %7.0f m   p99 %8.0f m   MAX %9.0f m' %
          (name,len(vals),pct(vals,.5),pct(vals,.9),pct(vals,.99),worst[0]))
    over=lambda t: 100.0*sum(1 for v in vals if v>t)/len(vals)
    print('  %-26s %%>500m: %5.1f    %%>2km (buffer): %5.1f' % ('',over(500),over(2000)))
    return ds


def inside(lon, lat, rings):
    c = False
    for r in rings:
        for i in range(len(r)-1):
            x1,y1 = r[i]; x2,y2 = r[i+1]
            if (y1 > lat) != (y2 > lat):
                if lon < x1 + (lat-y1)*(x2-x1)/(y2-y1): c = not c
    return c

SPOTCHECK = [
    ("Manhattan (Midtown)",    -73.9840, 40.7549, True),
    ("Great Neck, LI",         -73.7285, 40.7868, True),
    ("Rye, on the CT line",    -73.6837, 40.9807, True),
    ("Buffalo",                -78.8784, 42.8864, True),
    ("Port Jervis NY",         -74.6927, 41.3751, True),
    ("Matamoras PA",           -74.7013, 41.3695, False),
    ("Greenwich CT",           -73.6284, 41.0262, False),
    ("Hoboken NJ",             -74.0323, 40.7439, False),
    ("Fort Lee NJ",            -73.9701, 40.8509, False),
    ("Palm Beach FL",          -80.0364, 26.7056, False),
]

def fetch(url, stem, workdir):
    z = os.path.join(workdir, stem + '.zip')
    print('downloading %s ...' % url, file=sys.stderr)
    urllib.request.urlretrieve(url, z)
    with zipfile.ZipFile(z) as f: f.extractall(workdir)
    return os.path.join(workdir, stem)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--tiger', action='store_true',
                    help='compare against TIGER (legal boundary, runs across open water) '
                         'instead of the shoreline-clipped cartographic file')
    a = ap.parse_args()
    url, stem = TIGER if a.tiger else CB

    rings = load_bundled(BUNDLED)
    print('bundled: %d rings, %d points' % (len(rings), sum(len(r) for r in rings)))

    with tempfile.TemporaryDirectory() as wd:
        base = fetch(url, stem, wd)
        grid = index(segments(load_ref(base)))
        samples = densify(rings)
        ds = sorted((nearest(p, grid), p) for p in samples)
        vals = [d for d, _ in ds]

    print('\nbundled -> %s, %d samples every 250 m' % (stem, len(vals)))
    for label, q in (('median', .5), ('p90', .9), ('p99', .99)):
        print('  %-8s %8.0f m' % (label, pct(vals, q)))
    print('  %-8s %8.0f m  at %.4f, %.4f' % ('MAX', ds[-1][0], ds[-1][1][0], ds[-1][1][1]))
    over = 100.0*sum(1 for v in vals if v > BUFFER_M)/len(vals)
    print('  share beyond the %.0f m near-border buffer: %.1f%%' % (BUFFER_M, over))
    if ds[-1][0] < BUFFER_M:
        print('  OK: worst deviation is inside the buffer, so boundary error always')
        print('      raises the nearBorder flag rather than a silent misclassification.')
    else:
        print('  WARNING: deviation exceeds the buffer. Days can be confidently')
        print('           misclassified without being flagged. Raise borderBufferMeters')
        print('           or use a closer-fitting boundary file.')

    print('\nspot checks')
    bad = 0
    for name, lon, lat, expect in SPOTCHECK:
        got = inside(lon, lat, rings)
        ok = got == expect
        bad += not ok
        print('  %-22s %-6s %s' % (name, 'IN NY' if got else 'out', 'ok' if ok else '** WRONG **'))
    return 1 if bad else 0

if __name__ == '__main__':
    sys.exit(main())
