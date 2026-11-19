import 'dart:io';

import 'package:promptguard/src/core/suite.dart';
import 'package:test/test.dart';

void main() {
  test('parses a suite with all expectation types', () {
    final file = File('/tmp/pg_suite_test.yaml');
    file.writeAsStringSync('''
judge:
  model: openai:gpt-4o-mini
tests:
  - id: t1
    system: sys
    user: hello
    model: openai:gpt-4o-mini
    expect:
      - contains: world
      - not_contains: TODO
      - matches: '^[A-Z]'
      - equals: exact text
      - judged: Is a good answer.
''');
    final suite = Suite.load(file.path);
    expect(suite.tests, hasLength(1));
    final test = suite.tests.first;
    expect(test.id, 't1');
    expect(test.expectations, hasLength(5));
    expect(suite.judgeModel, 'openai:gpt-4o-mini');
  });

  test('expectation checks behave correctly', () {
    expect(ContainsExpectation('World').check('hello WORLD!'), isTrue);
    expect(ContainsExpectation('World').check('hello there'), isFalse);
    expect(NotContainsExpectation('error').check('all good'), isTrue);
    expect(MatchesExpectation(r'^[A-Z][a-z]+[.]$').check('Hello.'), isTrue);
    expect(MatchesExpectation(r'^[A-Z][a-z]+[.]$').check('hello.'), isFalse);
    expect(EqualsExpectation('  Hi  ').check('Hi'), isTrue);
    expect(EqualsExpectation('hi', ignoreCase: true).check('HI'), isTrue);
  });

  test('throws on missing tests section', () {
    final file = File('/tmp/pg_bad.yaml');
    file.writeAsStringSync('providers: {}\n');
    expect(() => Suite.load(file.path), throwsStateError);
  });
}
