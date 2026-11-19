# Changelog

## 0.2.0

- **Output snapshots** — golden files for LLM output: `--snapshots <dir>` compares,
  `--update-snapshots` accepts new outputs. Catches subtle drift in generation.
- **Parallel execution** — `--parallel` runs the suite concurrently.
- **`promptguard watch`** — re-runs the suite on every save while you tune prompts.
- **Token & cost report** — every run prints tokens in/out and estimated USD cost
  (known model prices built in; override per model in the config `pricing:` section).
- **GitHub Action Marketplace entry** — `action.yml` composite action: use
  `uses: awaisdev5765/promptguard@v0` instead of copy-pasting workflow YAML.

## 0.1.0

- Initial release.
- `promptguard run` — execute prompt test suites with exit-code CI semantics.
- `promptguard init` — starter suite scaffold.
- 5 expectation types: contains, not_contains, matches, equals, judged (LLM rubric).
- 5 bundled providers: OpenAI, Anthropic, Gemini, Groq, OpenRouter
  (plus any self-hosted OpenAI-compatible endpoint).
- Copy-paste GitHub Actions workflow with PR commenting.
- Unit-tested with fake providers — no API keys needed for development.
