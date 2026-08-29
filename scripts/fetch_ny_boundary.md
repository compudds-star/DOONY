# The bundled NY boundary — measurement, and how to replace it

**You probably do not need to replace it.** This file used to say the bundled
outline was "medium-fidelity" and should be swapped for TIGER/Line before audit
use. That was an untested assumption, and measuring it on **2026-08-29** did not
support it.

## What the measurement found

The bundled `ny_state_boundary.geojson` (894 points, 7 polygons) was compared
against the Census cartographic boundary `cb_2023_us_state_500k`, sampling the
bundled outline every 250 m (9566 sample points) and taking the distance from
each to the nearest reference segment:

| | deviation |
|---|---|
| median | 29 m |
| p90 | 307 m |
| p99 | 1183 m |
| **worst case** | **1951 m** (Thousand Islands, ~-76.14, 44.27) |
| share exceeding the 2 km near-border buffer | **0.0%** |

The worst case matters most: at 1951 m it sits just inside the 2 km
`borderBufferMeters` in `LocationManager.swift`. So anywhere the polygon is
wrong enough to flip a day's in/out classification, the day is *also* flagged
`nearBorder` and escalated to high-accuracy GPS. Boundary error cannot silently
produce a confident wrong answer. **This is why that buffer must not drop below
2 km** — the constant is load-bearing, not just a battery tradeoff.

Sixteen real locations were spot-checked and all classified correctly, including
Port Jervis NY (427 m from the line) against Matamoras PA (520 m) across the
Delaware, and Manhattan against Hoboken and Fort Lee across the Hudson.

## The one case where a different file behaves differently

Compared against **TIGER** instead, deviations reach 45 km. That looks alarming
and isn't: every large offset lies between latitude 43.2–43.5, longitude -76 to
-79 — Lake Ontario, then Lake Erie. TIGER carries New York's *legal* boundary
out across the lakes to the Canadian line, while both the bundled file and the
cartographic file stop at the shoreline. The same applies to the mid-channel
lines in the Hudson and Long Island Sound.

This only changes a classification for a position **on open water**. If days
spent boating on Lake Ontario or in the Sound need to count as NY days, use
TIGER (Option B) — and re-run the deviation measurement afterward, because a
shoreline-to-legal-line switch will move the boundary by far more than the 2 km
buffer in exactly those areas.

## If you do replace it

`GeoBoundary.swift` accepts a GeoJSON **Feature**, **FeatureCollection**, or raw
geometry whose type is `Polygon` or `MultiPolygon` (with holes). Just keep the
filename `ny_state_boundary.geojson`.

### Option A — Census Cartographic Boundary (recommended)

1. Download the states cartographic boundary shapefile (1:500k is a good balance;
   1:20m is coarser, 1:5m finer) from:
   `https://www.census.gov/geographies/mapping-files/time-series/geo/cartographic-boundary.html`
   e.g. `cb_YYYY_us_state_500k.zip`.
2. Convert to GeoJSON and extract NY (`STUSPS == 'NY'`) with GDAL:
   ```bash
   ogr2ogr -f GeoJSON -where "STUSPS='NY'" ny_state_boundary.geojson cb_2023_us_state_500k.shp
   ```
3. (Optional) Reduce size while preserving topology with mapshaper:
   ```bash
   npm i -g mapshaper
   mapshaper ny_state_boundary.geojson -simplify 20% keep-shapes -o force ny_state_boundary.geojson
   ```
4. Copy to `DOONY/Resources/ny_state_boundary.geojson`.

### Option B — TIGER/Line (highest fidelity, largest)

Use `tl_YYYY_us_state.zip` from the TIGER/Line page and the same `ogr2ogr`
extract. TIGER follows legal boundaries closely (best for the border), at the
cost of file size — simplify with mapshaper if the bundle gets large.

### Notes on the water border

State lines in rivers/lakes/bays (e.g. the Hudson, Lake Ontario, Long Island
Sound, the NY/NJ line in the harbor) matter for near-border days. Cartographic
boundary files clip to shoreline; TIGER includes water boundaries. Whichever you
choose, sanity-check with the app's per-day raw samples near those areas, and use
the manual override when a day is genuinely ambiguous.

### Verify after replacing
Run the tests — known NY cities must still classify inside and out-of-state
cities outside:
```bash
xcodebuild test -scheme DOONY -destination 'platform=iOS Simulator,name=iPhone 15'
```
