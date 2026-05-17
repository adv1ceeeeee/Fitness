# Sportify Legal

Public legal pages for the Sportify mobile app. Hosted via **GitHub Pages**.

## How to publish

1. **Replace placeholders** in all `.md` files:
   - `{{PUBLISHER_NAME}}` — your registered entity (ООО / ИП / самозанятый ФИО).
   - `{{PUBLISHER_TAX_ID}}` — ИНН.
   - `{{CONTACT_EMAIL}}` — email for data-subject requests (GDPR / 152-ФЗ).
   - `{{GITHUB_PAGES_DOMAIN}}` — your Pages host, e.g. `adv1ceeeeee.github.io/Fitness`.

   Bulk substitute (PowerShell, from repo root):
   ```powershell
   Get-ChildItem legal\*.md | ForEach-Object {
     (Get-Content $_.FullName) `
       -replace '\{\{PUBLISHER_NAME\}\}', 'ООО «Спортифай»' `
       -replace '\{\{PUBLISHER_TAX_ID\}\}', '1234567890' `
       -replace '\{\{CONTACT_EMAIL\}\}', 'support@sportify.app' `
       -replace '\{\{GITHUB_PAGES_DOMAIN\}\}', 'adv1ceeeeee.github.io/Fitness' `
       | Set-Content $_.FullName
   }
   ```

2. **Enable GitHub Pages**:
   - Repository → Settings → Pages
   - Source: "Deploy from a branch"
   - Branch: `main`, folder: `/(root)`
   - Save. After a minute Pages publishes the site.

3. **Public URLs** that App Store / Google Play / RuStore reviewers can hit:
   - `https://<your-gh-username>.github.io/Fitness/legal/privacy/`
   - `https://<your-gh-username>.github.io/Fitness/legal/terms/`
   - English equivalents: `/legal/privacy-en/`, `/legal/terms-en/`

4. **Wire into the App**:
   - Add the privacy URL to App Store Connect → App Information → Privacy Policy URL.
   - Add the same to Google Play Console → Policy → App content.
   - Add a "Документы" section in Profile → Settings linking out to both URLs.

## Updating

When you change the Policy materially, bump the `Версия:` and `Действует с:`
lines at the top of each file, and notify users in-app + via email at least
30 days before the new version takes effect (as promised in the Policy).
