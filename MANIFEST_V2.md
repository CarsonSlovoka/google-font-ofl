# MANIFEST — v2 Tree enrich delivery

Generated: 2026-08-17

## New / modified files

| filename | purpose | generated / original | modified |
|----------|---------|----------------------|----------|
| `scripts/enrich_github_data_tree.py` | Tree API + Contents fallback enricher; detects `sources/*.glyphs` & `sources/*.glyphspackage` | generated | new |
| `scripts/enrich_github_data.py` | Original v1 enricher | original | **unmodified** |
| `site/v2/index.html` | v2 GitHub Pages UI with sources filters | generated | new |
| `site/v2/js/app.js` | v2 frontend filter/sort logic | generated | new |
| `site/v2/data.json` | Sample data with v2 fields (demo only) | generated | new |
| `site/index.html` | v1 page — added link to v2 | original | lightly modified (nav link only) |
| `README.md` | Document v2 usage & API cost | original | updated |
| `CHANGES.md` | Changelog entry for 2026-08-17 | original | updated |

## Data schema additions (v2)

```json
{
  "enrich_version": "tree-v1",
  "with_files": true,
  "tree_method_counts": { "tree": 0, "contents_fallback": 0, "none": 0 },
  "items": [
    {
      "has_glyphs": false,
      "has_glyphspackage": false,
      "glyphs_sources": [{ "name": "...", "path": "sources/...", "url": "https://..." }],
      "glyphspackage_sources": [{ "name": "...", "path": "sources/...", "url": "https://..." }],
      "tree_method": "tree | contents_fallback | none",
      "workflows": [],
      "issue_templates": []
    }
  ]
}
```

## How to run

```sh
export GH_TOKEN=ghp_...
python3 scripts/enrich_github_data_tree.py data.json -o data.v2.json
cp data.v2.json site/v2/data.json
```

## QA status

- `python3 -m py_compile scripts/enrich_github_data_tree.py` → OK
- Original `enrich_github_data.py` not modified
- v1 page remains functional; v2 is additive

## Notes

- CI workflow still uses v1 by default (no breaking change).
- To enable v2 in CI, add a step that runs `enrich_github_data_tree.py` and copies output to `site/v2/data.json`.
