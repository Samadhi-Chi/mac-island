# Mac Island GitHub Pages

The buildless `site/` directory is the complete public website payload. It uses
checked-in HTML, CSS and real native-window screenshots using synthetic sessions.
No package install, API, analytics, cookies or third-party font/CDN is required.
The screenshot fixture does not read live clients or persistent user settings.
Simplified Chinese pages are at the root; matching English pages are in `en/`.
Every page links to its language counterpart. There is no generated UI rendering.
Capture details are recorded in [screenshot provenance](website-screenshots.md).

Pages are home, guide/compatibility, privacy, support, licenses and 404. The
website distinguishes development source from a signed binary; there is no
fabricated download, support email, certification or testimonial.

## Local review

```sh
python3 scripts/check-site.py
python3 -m http.server 8765 --bind 127.0.0.1 --directory site
```

Review desktop and narrow layouts, keyboard focus, both languages, reduced
motion and navigation. The custom 404 uses `/mac-island/`-anchored assets because
GitHub can serve it at an arbitrary missing path. Check that behavior on the
actual project Pages URL after publishing.

## First publication

The project URL is
`https://samadhi-chi.github.io/mac-island/`. No custom domain is needed.

1. Complete the source-disclosure/security/history review and latest-head CI.
   Keep the repository private while any disclosure blocker remains.
2. Create the independent reviewed baseline, or merge later changes through the
   maintainer's GitHub Desktop workflow, and verify the resulting `main` check.
3. Perform the separately reviewed visibility change, enable private vulnerability
   reporting and verify the private report entry. Review branch protection,
   Dependabot/secret-scanning availability and pre-existing Actions artifacts.
4. Set **Settings → Pages → Build and deployment → GitHub Actions**.
5. Run **Mac Island Pages** on `main`. The workflow requires the intended public
   repository and deploys only `site/`, never the checkout, docs, logs or builds.
6. Verify the deployment URL, HTTPS, all pages, nested-path 404, and external
   support links. Record the published commit and deployment run.

Subsequent site releases remain explicit workflow dispatches. Upload/Pages action
revisions are pinned; Dependabot proposes action updates for review. Workflow
deployment permissions are limited to the deploy job.

After deployment is verified, the website home, `privacy.html` and `support.html`
can supply the real HTTPS URLs in the ignored distribution configuration. Do not
fill release configuration with URLs that have not been published and checked.

GitHub records visitor IP addresses for hosting security; the website privacy
page discloses this independently of the local application's data policy. See
[GitHub Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages)
and [publication sources](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site).
