# STAC Browser patch (temporary)

Vendored from [pantierra/stac-browser@f4347c24a](https://github.com/pantierra/stac-browser/commit/f4347c24a) (`fix/dynamic-pathprefix`), adapted for `radiantearth/stac-browser` v4.0.1 (the version in `charts/eoapi/values.yaml`).

Adds runtime `SB_pathPrefix` support in the Docker image so eoapi can serve the browser under `/browser/` without baking the prefix at build time.

**Remove when upstream merges this:** delete `patches/stac-browser/` and the "Apply dynamic pathPrefix patch" step in `.github/workflows/stac-browser.yml`.
