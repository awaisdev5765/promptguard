// Core models: the test suite definition and results.

import 'dart:io';

import 'package:yaml/yaml.dart';

/// A single prompt test: one input, one provider call, one expectation set.
class PromptTest {
  final String id;
  final String system;
  final String user;
  final String model;
  final List<Expectation> expectations;
  final Map<String, String> variables;

  PromptTest({
    required this.id,
    required this.system,
    required this.user,
    required this.model,
    required this.expectations,
    this.variables = const {},
  });
}

/// How a test judges the model output.
sealed class Expectation {
  final String raw;

  Expectation(this.raw);

  /// Human label used in reports.
  String get describe;

  /// Whether [output] satisfies this expectation.
  bool check(String output);
}

/// Output must contain the given text (case-insensitive).
class ContainsExpectation extends Expectation {
  ContainsExpectation(super.raw);

  @override
  String get describe => 'contains "${_trim(raw)}"';

  @override
  bool check(String output) => output.toLowerCase().contains(raw.toLowerCase());
}

/// Output must match the given regular expression.
class MatchesExpectation extends Expectation {
  final RegExp regex;

  MatchesExpectation(super.pattern) : regex = RegExp(pattern, dotAll: true);

  @override
  String get describe => 'matches /${_trim(raw)}/';

  @override
  bool check(String output) => regex.hasMatch(output);
}

/// Output must NOT contain the given text.
class NotContainsExpectation extends Expectation {
  NotContainsExpectation(super.raw);

  @override
  String get describe => 'does not contain "${_trim(raw)}"';

  @override
  bool check(String output) => !output.toLowerCase().contains(raw.toLowerCase());
}

/// Output must equal a golden snapshot (exact or trimmed).
class EqualsExpectation extends Expectation {
  final bool ignoreCase;

  EqualsExpectation(super.raw, {this.ignoreCase = false});

  @override
  String get describe => 'equals ${ignoreCase ? '(case-insensitive) ' : ''}"${_trim(raw)}"';

  @override
  bool check(String output) {
    final a = output.trim();
    final b = raw.trim();
    return ignoreCase
        ? a.toLowerCase() == b.toLowerCase()
        : a == b;
  }
}

/// Output must be judged acceptable by an LLM judge against a rubric.
class JudgedExpectation extends Expectation {
  final String rubric;
  final String judgeModel;

  JudgedExpectation(this.rubric, this.judgeModel) : super(rubric);

  @override
  String get describe => 'LLM judge: "${_trim(rubric)}"';

  @override
  bool check(String output) {
    // LLM judging is asynchronous; the synchronous contract is satisfied by
    // the runner pre-evaluating and replacing this expectation's rubric with
    // an equality check against 'PASS'. See PromptGuardRunner._judge.
    return output.trim().toUpperCase() == 'PASS';
  }
}

String _trim(String text) =>
    text.length > 40 ? '${text.substring(0, 40)}…' : text;

/// Parses a `promptguard.yaml` file into tests.
class Suite {
  final List<PromptTest> tests;
  final Map<String, String> providers;
  final String judgeModel;

  Suite({required this.tests, required this.providers, required this.judgeModel});

  static Suite load(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError('promptguard config not found: $path');
    }
    final doc = loadYaml(file.readAsStringSync()) as YamlMap;

    final providers = <String, String>{};
    final providersNode = doc['providers'];
    if (providersNode is YamlMap) {
      providersNode.forEach((key, value) {
        providers[key.toString()] = value.toString();
      });
    }

    var judgeModel = 'openai:gpt-4o-mini';
    if (doc['judge'] is YamlMap && doc['judge']['model'] != null) {
      judgeModel = doc['judge']['model'].toString();
    }

    final tests = <PromptTest>[];
    final testsNode = doc['tests'];
    if (testsNode is! YamlList) {
      throw StateError('promptguard config must contain a "tests:" list');
    }
    for (final entry in testsNode) {
      final map = entry as YamlMap;
      tests.add(_parseTest(map));
    }
    return Suite(tests: tests, providers: providers, judgeModel: judgeModel);
  }

  static PromptTest _parseTest(YamlMap map) {
    final id = map['id']?.toString() ?? 'test-${map.hashCode.abs() % 10000}';

    final expectations = <Expectation>[];
    final expectNode = map['expect'];
    if (expectNode is YamlList) {
      for (final entry in expectNode) {
        expectations.add(_parseExpectation(entry as YamlMap));
      }
    } else if (expectNode is YamlMap) {
      expectations.add(_parseExpectation(expectNode));
    }
    if (expectations.isEmpty) {
      throw StateError('test "$id" has no expectations');
    }

    return PromptTest(
      id: id,
      system: map['system']?.toString() ?? '',
      user: map['user']?.toString() ?? '',
      model: map['model']?.toString() ?? 'openai:gpt-4o-mini',
      expectations: expectations,
    );
  }

  static Expectation _parseExpectation(YamlMap map) {
    if (map['contains'] != null) {
      return ContainsExpectation(map['contains'].toString());
    }
    if (map['matches'] != null) {
      return MatchesExpectation(map['matches'].toString());
    }
    if (map['not_contains'] != null) {
      return NotContainsExpectation(map['not_contains'].toString());
    }
    if (map['equals'] != null) {
      return EqualsExpectation(map['equals'].toString(),
          ignoreCase: map['ignore_case'] == true);
    }
    if (map['judged'] != null) {
      return JudgedExpectation(
        map['judged'].toString(),
        map['judge_model']?.toString() ?? 'openai:gpt-4o-mini',
      );
    }
    throw StateError(
        'expectation must use contains/matches/not_contains/equals/judged');
  }
}

/// The result of one test.
class TestResult {
  final PromptTest test;
  final String output;
  final List<bool> expectationResults;
  final int durationMs;
  final String? error;

  TestResult({
    required this.test,
    required this.output,
    required this.expectationResults,
    required this.durationMs,
    this.error,
  });

  bool get passed => !expectationResults.contains(false) && error == null;
}

/// The full run result.
class RunReport {
  final List<TestResult> results;

  RunReport(this.results);

  int get total => results.length;
  int get failures => results.where((r) => !r.passed).length;

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# PromptGuard report')
      ..writeln()
      ..writeln('**$total tests — ${total - failures} passed, $failures failed**')
      ..writeln();
    for (final result in results) {
      final icon = result.passed ? '✅' : '❌';
      buffer.writeln('## $icon ${result.test.id} (${result.durationMs}ms)');
      for (var i = 0; i < result.expectationResults.length; i++) {
        final expectation = result.test.expectations[i];
        final ok = result.expectationResults[i];
        buffer.writeln('- ${ok ? '✅' : '❌'} ${expectation.describe}');
      }
      if (!result.passed) {
        buffer.writeln();
        buffer.writeln('```\n${_clip(result.output, 400)}\n```');
      }
      buffer.writeln();
    }
    return buffer.toString();
  }
}

String _clip(String text, int length) {
  text = text.trim();
  return text.length <= length ? text : '${text.substring(0, length)}…';
}
