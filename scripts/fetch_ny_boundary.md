# Replacing the bundled NY boundary with an authoritative one

The app ships with a **medium-fidelity** public-domain NY outline so it works out
of the box. For **audit-grade** border classification, replace it with the U.S.
Census Bureau **TIGER/Line** (or Cartographic Boundary) state polygon, which is
the authoritative source.

`GeoBoundary.swift` accepts a GeoJSON **Feature**, **FeatureCollection**, or raw
geometry whose type is `Polygon` or `MultiPolygon` (with holes). Just keep the
filename `ny_state_boundary.geojson`.

## Option A — Census Cartographic Boundary (recommended)

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

## Option B — TIGER/Line (highest fidelity, largest)

Use `tl_YYYY_us_state.zip` from the TIGER/Line page and the same `ogr2ogr`
extract. TIGER follows legal boundaries closely (best for the border), at the
cost of file size — simplify with mapshaper if the bundle gets large.

## Notes on the water border

State lines in rivers/lakes/bays (e.g. the Hudson, Lake Ontario, Long Island
Sound, the NY/NJ line in the harbor) matter for near-border days. Cartographic
boundary files clip to shoreline; TIGER includes water boundaries. Whichever you
choose, sanity-check with the app's per-day raw samples near those areas, and use
the manual override when a day is genuinely ambiguous.

## Verify after replacing
Run the tests — known NY cities must still classify inside and out-of-state
cities outside:
```bash
xcodebuild test -scheme DOONY -destination 'platform=iOS Simulator,name=iPhone 15'
```
