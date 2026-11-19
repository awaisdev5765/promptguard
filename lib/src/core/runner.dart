// The runner: executes tests (parallel option), snapshots, judging, costs.

import 'dart:async';
import 'dart:io';

import '../providers/provider.dart';
import 'pricing.dart';
import 'suite.dart';

class PromptGuardRunner {
  final ProviderRegistry registry;

  PromptGuardRunner(this.registry);

  /// Runs [suite]. Tests execute in parallel when [parallel] is true.
  Future<RunReport> runSuite(
    Suite suite, {
    bool parallel = false,
    String? snapshotDir,
    bool updateSnapshots = false,
  }) async {
    List<TestResult> results;
    if (parallel && suite.tests.length > 1) {
      results = await Future.wait(
        suite.tests.map((test) => runTest(test, suite)),
      );
    } else {
      results = <TestResult>[];
      for (final test in suite.tests) {
        results.add(await runTest(test, suite));
      }
    }

    // Snapshot handling: compare against golden files or update them.
    if (snapshotDir != null) {
      results = [
        for (final result in results)
          await _applySnapshot(
            result,
            snapshotDir,
            update: updateSnapshots,
          ),
      ];
    }

    // Attach costs from usage + suite pricing.
    final priced = [
      for (final result in results)
        _withCost(result, suite),
    ];
    return RunReport(priced, pricing: suite.pricing);
  }

  Future<TestResult> runTest(PromptTest test, Suite suite) async {
    final stopwatch = Stopwatch()..start();
    try {
      final (provider, model) = registry.resolve(test.model);
      final completion = await provider.complete(
        model: model,
        system: test.system,
        user: test.user,
      );
      final output = completion.text;

      // Pre-evaluate judged expectations with the judge model.
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
        usage: completion.usage,
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
    return verdict.text.trim().toUpperCase().startsWith('PASS');
  }

  /// Compares or updates the golden snapshot for [result].
  Future<TestResult> _applySnapshot(
    TestResult result,
    String snapshotDir,
    {required bool update}
  ) async {
    final dir = Directory(snapshotDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File('${dir.path}/${result.test.id}.snap');

    if (update || !file.existsSync()) {
      file.writeAsStringSync(result.output);
      // First run establishes the baseline; treat as passed for the
      // snapshot dimension (other expectations still gate the result).
      return result;
    }

    final golden = file.readAsStringSync();
    if (result.output.trim() == golden.trim()) {
      return result;
    }
    // Mismatch: fail the result with a diff-shaped error.
    return TestResult(
      test: result.test,
      output: result.output,
      expectationResults: [
        ...result.expectationResults,
        false,
      ],
      durationMs: result.durationMs,
      usage: result.usage,
      costUsd: result.costUsd,
      error: 'snapshot mismatch — output differs from ${file.path}. '
          'Run with --update-snapshots to accept the new output.',
    );
  }

  TestResult _withCost(TestResult result, Suite suite) {
    final usage = result.usage;
    if (usage == null) return result;
    final bareModel = _bareModel(result.test.model);
    final pricing = suite.pricingFor(bareModel);
    final judged = result.test.expectations
        .whereType<JudgedExpectation>()
        .isNotEmpty;
    // Judge call cost is folded in approximately: judge model price + 1 call.
    var cost = pricing?.cost(usage) ?? 0.0;
    if (judged) {
      final judgePricing = suite.pricingFor(_bareModel(suite.judgeModel));
      if (judgePricing != null) {
        // Estimate ~500 judge tokens per judged expectation.
        cost += judgePricing.cost(TokenUsage(
          promptTokens: 300,
          completionTokens: 5,
        ));
      }
    }
    return TestResult(
      test: result.test,
      output: result.output,
      expectationResults: result.expectationResults,
      durationMs: result.durationMs,
      usage: usage,
      costUsd: cost,
      error: result.error,
    );
  }
}

String _bareModel(String modelRef) {
  final index = modelRef.indexOf(':');
  return index <= 0 ? modelRef : modelRef.substring(index + 1);
}
