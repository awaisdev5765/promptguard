// `promptguard example` — print a complete worked example project.

import 'package:args/command_runner.dart';

Command<int> buildExampleCommand() => ExampleCommand();

class ExampleCommand extends Command<int> {
  @override
  String get name => 'example';

  @override
  String get description => 'Print a complete worked example (suite + CI).';

  @override
  Future<int> run() async {
    // ignore: avoid_print
    print(_example);
    return 0;
  }
}

const _example = '''
=======================================================================
promptguard worked example — classify + summarize + judge
=======================================================================

promptguard.yaml
-----------------
providers: {}
judge:
  model: openai:gpt-4o-mini
tests:
  - id: summarize-tone
    system: You summarize articles in one sentence.
    user: <paste a paragraph>
    model: openai:gpt-4o-mini
    expect:
      - contains: install
      - judged: The summary is one sentence under 40 words.

distribution/github-action.md (see docs/ for the full file)
-----------------
name: Prompt tests
on:
  pull_request:
    paths: ["promptguard.yaml", "prompts/**", ".github/workflows/prompt.yml"]
jobs:
  promptguard:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
        with: { sdk: stable }
      - run: dart pub global activate promptguard
      - run: promptguard run --output report.md
        env:
          OPENAI_API_KEY: \${{ secrets.OPENAI_API_KEY }}
      - uses: actions/upload-artifact@v4
        if: always()
        with: { name: promptguard-report, path: report.md }

Run it:
  dart pub global activate promptguard
  promptguard init
  export OPENAI_API_KEY=sk-...
  promptguard run
=======================================================================
''';
