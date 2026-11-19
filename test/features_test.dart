import 'dart:io';

import 'package:promptguard/src/core/pricing.dart';
import 'package:promptguard/src/core/runner.dart';
import 'package:promptguard/src/core/suite.dart';
import 'package:promptguard/src/providers/provider.dart';
import 'package:test/test.dart';

class FakeProvider implements Provider {
  FakeProvider(this.response);

  final String response;

  @override
  Future<CompletionResult> complete({
    required String model,
    required String system,
    required String user,
  }) async => CompletionResult(
        text: response,
        usage: TokenUsage(promptTokens: 10, completionTokens: 5),
      );
}

PromptTest _test(String id) => PromptTest(
      id: id,
      system: '',
      user: 'u',
      model: 'fake:m',
      expectations: [ContainsExpectation('hello')],
    );

void main() {
  test('parallel execution runs all tests', () async {
    final registry = ProviderRegistry(envLookup: (_) => 'key');
    registry.register('fake', FakeProvider('hello world'));
    final runner = PromptGuardRunner(registry);
    final report = await runner.runSuite(
      Suite(
        tests: [_test('a'), _test('b'), _test('c')],
        providers: const {},
        judgeModel: 'fake:m',
      ),
      parallel: true,
    );
    expect(report.total, 3);
    expect(report.failures, 0);
  });

  test('snapshots: first run writes baseline, changed output fails', () async {
    final temp = Directory.systemTemp.createTempSync('pg_snap');
    addTearDown(() => temp.deleteSync(recursive: true));

    final registry = ProviderRegistry(envLookup: (_) => 'key');
    registry.register('fake', FakeProvider('hello one'));
    final runner = PromptGuardRunner(registry);
    final suite = Suite(
      tests: [_test('snap-test')],
      providers: const {},
      judgeModel: 'fake:m',
    );

    // First run: establishes baseline (no failure).
    final first = await runner.runSuite(
      suite,
      snapshotDir: temp.path,
      updateSnapshots: false,
    );
    expect(first.failures, 0);
    expect(File('${temp.path}/snap-test.snap').existsSync(), isTrue);

    // Second run with identical output: passes.
    final second = await runner.runSuite(
      suite,
      snapshotDir: temp.path,
      updateSnapshots: false,
    );
    expect(second.failures, 0);

    // Third run with changed output: snapshot mismatch failure.
    registry.register('fake', FakeProvider('hello TWO - changed!'));
    final third = await runner.runSuite(
      suite,
      snapshotDir: temp.path,
      updateSnapshots: false,
    );
    expect(third.failures, 1);
    expect(third.results.first.error, contains('snapshot mismatch'));
  });

  test('updateSnapshots accepts the new output', () async {
    final temp = Directory.systemTemp.createTempSync('pg_snap2');
    addTearDown(() => temp.deleteSync(recursive: true));

    final registry = ProviderRegistry(envLookup: (_) => 'key');
    registry.register('fake', FakeProvider('hello one'));
    final runner = PromptGuardRunner(registry);
    final suite = Suite(
      tests: [_test('snap2')],
      providers: const {},
      judgeModel: 'fake:m',
    );

    await runner.runSuite(suite, snapshotDir: temp.path);
    registry.register('fake', FakeProvider('hello two'));
    final updated = await runner.runSuite(
      suite,
      snapshotDir: temp.path,
      updateSnapshots: true,
    );
    expect(updated.failures, 0);
    expect(File('${temp.path}/snap2.snap').readAsStringSync(), 'hello two');
  });

  test('cost estimation from usage + known pricing', () async {
    final registry = ProviderRegistry(envLookup: (_) => 'key');
    registry.register('fake', FakeProvider('hello world'));
    final runner = PromptGuardRunner(registry);
    final suite = Suite(
      tests: [_test('cost-test')],
      providers: const {},
      judgeModel: 'fake:m',
    );
    final report = await runner.runSuite(suite);
    expect(report.totalUsage.totalTokens, 15);
    // fake:m is unknown → cost 0, but usage is recorded.
    expect(report.totalUsage.promptTokens, 10);
    expect(report.results.first.usage, isNotNull);
  });

  test('pricing override from suite is honored', () {
    final suite = Suite(
      tests: const [],
      providers: const {},
      judgeModel: 'fake:m',
      pricing: {
        'fake-m': const ModelPricing(
          inputPerMillion: 1.0,
          outputPerMillion: 3.0,
        ),
      },
    );
    final pricing = suite.pricingFor('fake-m');
    expect(pricing!.cost(TokenUsage(promptTokens: 1000000, completionTokens: 1000000)), 4.0);
  });

  test('known pricing table matches gpt-4o-mini prefix', () {
    final suite = Suite(tests: const [], providers: const {}, judgeModel: '');
    expect(suite.pricingFor('gpt-4o-mini'), isNotNull);
    expect(suite.pricingFor('gpt-4o-mini-2024-07-18'), isNotNull);
    expect(suite.pricingFor('claude-3-5-haiku-latest'), isNotNull);
  });
}
