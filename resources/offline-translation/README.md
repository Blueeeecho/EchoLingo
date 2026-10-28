# EchoLingo offline English–Chinese resources

These files describe the exact Mozilla Translations `base-memory` model pair selected for EchoLingo. They are independent directional models, presented as one local translation service. They are not a dictionary and do not call a cloud service.

- Registry snapshot: `mozilla-model-registry-20261026.json`, generated `2026-10-26T00:44:07Z`.
- Selected records: `selected-models.json`.
- Pinned resources and SHA-256: `manifest.json`.
- Model and inference license: `licenses/MPL-2.0.txt`; see `licenses/THIRD_PARTY_NOTICES.md` and `licenses/SOURCE-OFFER.md`.
- Build-time model fetch: `python3 scripts/prepare-offline-models.py`.
- Verify the staged resources without networking or writes: `python3 scripts/prepare-offline-models.py --verify-only`.

The seven unchanged model/shortlist/tokenizer files download as **75,033,319 compressed bytes** and occupy **104,470,603 unpacked bytes**. These totals exclude the inference executable, notices and application. An installer may use a different compression ratio. The public registry labels English→Chinese `Release` and Chinese→English `Release Android`; these upstream labels do not constitute EchoLingo desktop acceptance.

The generated `models/` and `bin/` directories are intentionally excluded from Git. Fixed model bytes are staged at build time and bundled in the installer. The runtime does not download models, read API credentials or upload source text for this service. A missing or modified model must fail visibly rather than selecting an Internet provider.
