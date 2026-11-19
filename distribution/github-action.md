# Add prompt tests to every pull request

## 1. Create the workflow file

Save this as `.github/workflows/prompt.yml` in your app's repo:

```yaml
name: Prompt tests
on:
  pull_request:
    paths:
      - "promptguard.yaml"
      - "prompts/**"
jobs:
  promptguard:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: dart-lang/setup-dart@v1
        with:
          sdk: stable

      - run: dart pub global activate promptguard

      - name: Run prompt tests
        run: promptguard run --output report.md
        env:
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
          # ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
          # GEMINI_API_KEY: ${{ secrets.GEMINI_API_KEY }}

      - name: Comment results on the PR
        if: always()
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const report = fs.readFileSync('report.md', 'utf8');
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: '## 🛡️ PromptGuard report\n\n' + report
            });

      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: promptguard-report
          path: report.md
```

## 2. Add your API key as a secret

In your repo: **Settings → Secrets and variables → Actions → New secret**
→ name it `OPENAI_API_KEY` (or the provider you use).

## 3. Open a PR that changes a prompt

Change any `system:`/`user:` text or a `model:` ref in `promptguard.yaml`
→ CI runs the suite → the PR gets a comment:

```
## 🛡️ PromptGuard report
**6 tests — 4 passed, 2 failed**
## ❌ support-classifier (812ms)
- ❌ equals "BILLING"
```

Now nobody can silently degrade your AI features.
