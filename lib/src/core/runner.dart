// The runner: executes tests, evaluates expectations (incl. LLM judging).

import '../providers/provider.dart';
import 'suite.dart';

class PromptGuardRunner {
  final ProviderRegistry registry;

  PromptGuardRunner(this.registry);

  /// Runs [suite], returning a [RunReport].
  Future<RunReport> runSuite(Suite suite) async {
    final results = <TestResult>[];
    for (final test in suite.tests) {
      results.add(await runTest(test, suite));
    }
    return RunReport(results);
  }

  Future<TestResult> runTest(PromptTest test, Suite suite) async {
    final stopwatch = Stopwatch()..start();
    try {
      final (provider, model) = registry.resolve(test.model);
      var output = await provider.complete(
        model: model,
        system: test.system,
        user: test.user,
      );

      // Pre-evaluate judged expectations with the judge model, replacing the
      // JudgedExpectation check (which expects a literal PASS) by running a
      // separate judge call and converting the verdict into the output
      // stream for that expectation only.
      final judgedIndexes = <int, bool>{};
      for (var i = 0; i < test.expectations.length; i++) {
        final expectation = test.expectations[i];
        if (expectation is JudgedExpectation) {
          judgedIndexes[i] = await _judge(expectation, output, suite);
        }
      }

      final expectationResults = <bool>[];
      for (var i = 0; i < test.expectations.length; i++) {
        final expectation = test.expectations[i];
        if (judgedIndexes.containsKey(i)) {
          expectationResults.add(judgedIndexes[i]!);
        } else {
          expectationResults.add(expectation.check(output));
        }
      }

      stopwatch.stop();
      return TestResult(
        test: test,
        output: output,
        expectationResults: expectationResults,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    } catch (error) {
      stopwatch.stop();
      return TestResult(
        test: test,
        output: '',
        expectationResults: test.expectations.map((_) => false).toList(),
        durationMs: stopwatch.elapsedMilliseconds,
        error: error.toString(),
      );
    }
  }

  /// Asks the judge model whether [output] satisfies [expectation].
  Future<bool> _judge(
    JudgedExpectation expectation,
    String output,
    Suite suite,
  ) async {
    final (judgeProvider, judgeModel) = registry.resolve(expectation.judgeModel);
    final verdict = await judgeProvider.complete(
      model: judgeModel,
      system: 'You are a strict QA judge. Answer with exactly one word: '
          'PASS or FAIL. Nothing else.',
      user: 'Rubric: ${expectation.rubric}\n\nOutput to judge:\n$output',
    );
    return verdict.trim().toUpperCase().startsWith('PASS');
  }
}
