# EchoLingo official website

Public URL: https://blueeeecho.github.io/EchoLingo/

This is the independent static desktop product website. It uses buildless HTML/CSS/JavaScript, system fonts and the owner's approved app icon. It does not load the desktop app, collect credentials or call translation services.

## Local preview

Run from the EchoLingo project root:

```sh
python3 -m http.server 4173 --bind 127.0.0.1 --directory website
```

The site has no installation or build step. The product is desktop-only. Validate ordinary desktop windows and browser zoom; narrower CSS widths may stack content for desktop accessibility without implying a mobile app.

## Publishing

The public repository's dedicated `gh-pages` branch stores these static files at its root. GitHub Pages publishes from that branch `/`, using `.nojekyll` to skip Jekyll. Main application branches, binaries, credentials, local app signing and release workflows are independent of this website deployment.

Commit only this directory's deployable files to the website branch. Verify the actual public HTML/assets after publishing and record the deployment commit in `docs/validation/official-website-20261028.json`. Do not overwrite a changed remote branch or publish unrelated local app modifications.

## Updating product content

- Keep the three primary selling points: unobtrusive translation, lightweight design and configurable services.
- The workflow illustration uses labeled fixed samples. It is not a live translation service or a screenshot of acceptance testing.
- The current app is a preview under verification. The public Releases page currently has no public installers. Do not fabricate a download URL, publish a draft release, claim stable availability or imply all-app compatibility.
- Update `index.html` platform/release status, FAQ and visible verification date when real downloads are available. Update `sitemap.xml` after substantive page changes.
- `privacy.html` distinguishes local OCR, cloud text/images, OS credentials, local history and GitHub hosting access logs.
- No external fonts/scripts, analytics, account UI, API-key fields or network requests belong in the browser demo.
