import 'package:promptguard/src/core/runner.dart';
import 'package:promptguard/src/core/suite.dart';
import 'package:promptguard/src/providers/provider.dart';
import 'package:test/test.dart';

class FakeProvider implements Provider {
  final String response;
  FakeProvider(this.response);

  @override
  Future<String> complete({
    required String model,
    required String system,
    required String user,
  }) async => response;
}

PromptTest _test(List<Expectation> expectations) => PromptTest(
      id: 't',
      system: '',
      user: 'u',
      model: 'fake:m',
      expectations: expectations,
    );

void main() {
  test('passing run', () async {
    final registry = ProviderRegistry(envLookup: (_) => 'key');
    registry.register('fake', FakeProvider('Hello world.'));
    final runner = PromptGuardRunner(registry);
    final report = await runner.runSuite(Suite(tests: [
      _test([ContainsExpectation('world'), NotContainsExpectation('error')]),
    ], providers: const {}, judgeModel: 'fake:m'));
    expect(report.failures, 0);
  });

  test('failing run reports which expectations failed', () async {
    final registry = ProviderRegistry(envLookup: (_) => 'key');
    registry.register('fake', FakeProvider('Totally off-topic output'));
    final runner = PromptGuardRunner(registry);
    final report = await runner.runSuite(Suite(tests: [
      _test([ContainsExpectation('world')]),
    ], providers: const {}, judgeModel: 'fake:m'));
    expect(report.failures, 1);
    expect(report.results.first.expectationResults.first, isFalse);
  });

  test('judged expectation routes through judge', () async {
    final registry = ProviderRegistry(envLookup: (_) => 'key');
    registry.register('fake', FakeProvider('Some answer'));
    registry.register('judge', FakeProvider('PASS'));
    final runner = PromptGuardRunner(registry);
    final report = await runner.runSuite(Suite(tests: [
      _test([JudgedExpectation('Is fine.', 'judge:m')]),
    ], providers: const {}, judgeModel: 'judge:m'));
    expect(report.failures, 0);
  });

  test('model ref parsing', () {
    final registry = ProviderRegistry(envLookup: (_) => 'key');
    registry.register('fake', FakeProvider('x'));
    final (provider, model) = registry.resolve('fake:gpt-x');
    expect(model, 'gpt-x');
    expect(() => registry.resolve('missing:model'), throwsStateError);
  });
}
