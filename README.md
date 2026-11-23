# Showcase tools (AD Group)

Public code for AD Group's Showcase display suites, one folder per tool. **Public: code and documents only, never
data or secrets** (no webhooks, no Showcase URLs with keys, no incident data).

| Folder | What |
|---|---|
| `fleet/` | Showcase Fleet: the signed packages and installer every Showcase NUC uses. Published by `publish_release.ps1`; don't edit by hand. |

`catalogue.json`, `catalogue.json.sig` and `install.ps1` at the top level are temporary pointers from before Fleet
moved into `fleet/` (23 Nov 2026), removed once every NUC and install link has moved (by 30 Nov 2026).
