// `promptguard init` — scaffold a promptguard.yaml in the current project.

import 'dart:io';

import 'package:args/command_runner.dart';

Command<int> buildInitCommand() => InitCommand();

class InitCommand extends Command<int> {
  InitCommand() {
    argParser.addFlag(
      'force',
      negatable: false,
      help: 'Overwrite an existing promptguard.yaml.',
    );
  }

  @override
  String get name => 'init';

  @override
  String get description => 'Create a starter promptguard.yaml in this project.';

  @override
  Future<int> run() async {
    final target = File('${Directory.current.path}/promptguard.yaml');
    if (target.existsSync() && argResults!['force'] != true) {
      stdout.writeln('promptguard.yaml already exists. Use --force to overwrite.');
      return 65;
    }

    target.writeAsStringSync(_starter);
    stdout.writeln('Created promptguard.yaml');
    stdout.writeln('''
Next steps:
  1. Set an API key:  export OPENAI_API_KEY=sk-...   (or GROQ_API_KEY, etc.)
  2. Edit the tests in promptguard.yaml to match your app's prompts.
  3. Run:             promptguard run
  4. Wire the GitHub Action (see distribution/github-action.md) so every
     PR that touches prompts or models gets tested automatically.
''');
    return 0;
  }
}

const _starter = '''
# promptguard — regression tests for your app's AI features.
#
# Each test sends one prompt to one model and checks the output.
# Providers: openai, anthropic, gemini, groq, openrouter
#            (set OPENAI_API_KEY / ANTHROPIC_API_KEY / GEMINI_API_KEY /
#             GROQ_API_KEY / OPENROUTER_API_KEY in your environment)

providers:
  # Base URLs are built in; add overrides here only for self-hosted
  # OpenAI-compatible endpoints:
  # my-local: http://localhost:8080/v1

judge:
  model: openai:gpt-4o-mini   # model used for `judged:` expectations

tests:
  - id: summarize-tone
    system: You are a helpful assistant that summarizes articles in one sentence.
    user: The Quick Start guide explains installation, first-run setup, and troubleshooting. Installation takes under five minutes on macOS, Windows, and Linux. First-run setup walks through account creation and theme selection. Troubleshooting covers the ten most common issues.
    model: openai:gpt-4o-mini
    expect:
      - contains: install
      - not_contains: TODO
      - judged: The summary is a single sentence under 40 words that captures the main topics.

  - id: support-classifier
    system: |
      Classify support messages into exactly one category:
      BUG, QUESTION, FEATURE_REQUEST, or BILLING.
      Reply with only the category word.
    user: I was charged twice this month, can you check my account?
    model: openai:gpt-4o-mini
    expect:
      - equals: BILLING
''';
