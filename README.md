# EchoLingo website

The static product website for [EchoLingo · 回声译](https://blueeeecho.github.io/EchoLingo/).

This branch contains HTML, CSS, JavaScript and public image assets. GitHub Pages publishes from the branch root without a build step.

The homepage is available in Chinese and English. The 中文 / English control follows the browser’s preferred language on the first visit, then stores the choice in `localStorage` under `echolingo-locale`. Nothing is sent to a server.

## Preview locally

From this branch checkout, run:

```sh
python3 -m http.server 4173 --bind 127.0.0.1
```

Open `http://127.0.0.1:4173/`. The workflow illustration uses sample text and does not call a translation service. The site has no API-key inputs, analytics, download counters or third-party scripts. Download links are static and do not require GitHub API requests.

Application source and licensing are maintained on [main](https://github.com/Blueeeecho/EchoLingo). Download installers from [Releases](https://github.com/Blueeeecho/EchoLingo/releases).

## Release download updates

The homepage version labels and download links are static. Publishing an application release or updating the `main` branch does not update this `gh-pages` branch.

After a release is public (not a draft):

1. Confirm the exact tag, prerelease status, publication date, package filenames, `SHA256SUMS.txt` and `RELEASE-MANIFEST.json` on GitHub Releases. Prereleases do not use GitHub's stable `Latest` endpoint.
2. Update both languages in `index.html`: hero labels, platform cards, direct downloads, release summary/date, checksums/manifest, validation limits and previous-preview link. Preserve the prerelease and signing warnings. Keep screenshots as a supplemental feature.
3. Update `README.md` and `README.en.md` on `main` separately. Do not change released tags or application binaries just to update download documentation.
4. Run `python3 scripts/check-release.py --version 0.2.17 --previous 0.2.16` and `python3 -m unittest discover -s tests`. Update the expected versions in the regression tests for the next release. Preview this branch locally. Check Chinese and English on desktop and mobile, and confirm the direct download links also work without JavaScript.
5. Publish the website changes to `gh-pages`, then verify the Pages deployment and the public homepage's version and links. A successful `main` merge alone is not a website deployment. GitHub Pages/CDN caches may briefly retain the previous HTML.
