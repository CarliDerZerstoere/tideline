# docs-public/

Public-facing site published via GitHub Pages. **Not** the internal design
corpus — that lives in `/docs/` (research notes, design decisions,
roadmaps) and stays private.

This folder contains the three pages Apple requires URLs for:

- `index.md` — landing page, brief app description, links to the other two
- `privacy.md` — full privacy policy (DE primary, EN secondary)
- `support.md` — FAQ + contact email

Plus the publishing config:

- `_config.yml` — Jekyll/Pages config, theme, lang
- `README.md` — this file

## How to publish

1. Commit + push these files to `main`.
2. GitHub repo → Settings → Pages.
3. Source: **Deploy from a branch**.
4. Branch: `main`, folder: `/docs-public`.
5. Save. GitHub builds the site (5–10 min for first publish).
6. The URL appears at the top of the Pages settings page once built.

Apple App Store Connect expects this URL on the App Information form:

- **Privacy Policy URL**: `https://<your-user>.github.io/<repo>/privacy`
- **Support URL**: `https://<your-user>.github.io/<repo>/support`
- **Marketing URL** (optional): `https://<your-user>.github.io/<repo>/`

## How to update

Edit the markdown, push, wait ~5 min. GitHub rebuilds.

If `_config.yml` changes, the rebuild can take longer.

## Don't add

- No tracking scripts.
- No third-party analytics (Plausible, Fathom, GA — nothing).
- No images that include user-identifiable content.

The site's purpose is satisfying Apple's policy URL requirement
honestly, not capturing visitor data — that would directly contradict
Pillar 1 of the project (`/CLAUDE.md` §3).
