# Source code availability

The Mozilla Translations model files and inference implementation are provided under the Mozilla Public License, version 2.0. A full copy is in `MPL-2.0.txt` in this directory. The bundled model, shortlist and tokenizer files are the unmodified published binary model resources; their exact source URLs and SHA-256 values are in `../manifest.json`.

The complete corresponding inference source is supplied as **`EchoLingo-offline-engine-source.zip` on the same [EchoLingo release page](https://github.com/Blueeeecho/EchoLingo/releases) as the installer**. That archive contains the pinned Mozilla inference source, the dependencies used to build it, EchoLingo's process wrapper and CMake/build scripts, licenses, build instructions and a per-file SHA-256 source inventory. It excludes model weights and generated binaries. The archive must be published alongside a binary release; an unpublished local candidate is not a public source offer.

Upstream Mozilla Translations revision: [`69455acaecbe8650cdba988dbcf7c10ca20e7c48`](https://github.com/mozilla/translations/tree/69455acaecbe8650cdba988dbcf7c10ca20e7c48). The exact dependency revisions and archive hashes are recorded by `scripts/offline-engine/build.py` in the source archive. Its `SOURCE-MANIFEST.json` identifies the actual files supplied, including any build compatibility changes.

You may obtain and modify these covered sources under their respective licenses. No additional restriction in EchoLingo's application terms limits rights granted for third-party covered files. Mozilla and the upstream authors do not endorse EchoLingo. Source availability is supplied without a separate fee.
