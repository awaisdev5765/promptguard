# Changelog

## 0.1.0

- Initial release.
- `promptguard run` — execute prompt test suites with exit-code CI semantics.
- `promptguard init` — starter suite scaffold.
- 5 expectation types: contains, not_contains, matches, equals, judged (LLM rubric).
- 5 bundled providers: OpenAI, Anthropic, Gemini, Groq, OpenRouter
  (plus any self-hosted OpenAI-compatible endpoint).
- Copy-paste GitHub Actions workflow with PR commenting.
- Unit-tested with fake providers — no API keys needed for development.
