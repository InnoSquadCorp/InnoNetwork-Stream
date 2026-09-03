# Public API snapshots

The four allowlists record every public declaration owned by an InnoStream
module. `Scripts/check_public_api_contract.sh` regenerates Swift symbol graphs,
compares them exactly, and enforces the ceilings in `budgets.tsv`.

| Module | Public declarations |
| --- | ---: |
| `InnoNetworkHLS` | 797 |
| `InnoNetworkHLSLive` | 300 |
| `InnoNetworkHLSAVFoundation` | 705 |
| `InnoNetworkHLSAudio` | 65 |
| **Total** | **1,867** |

When a public API change is intentional, update the owning allowlist, budget,
`API_STABILITY.md`, and `CHANGELOG.md` together. A budget increase is an API
governance decision, not an automatic response to a failing check.
