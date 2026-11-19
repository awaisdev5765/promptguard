// `promptguard run` — execute the suite.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../core/runner.dart';
import '../core/suite.dart';
import '../providers/http_providers.dart';
import '../utils/writer.dart';

Command<int> buildRunCommand() => RunCommand();

class RunCommand extends Command<int> {
  RunCommand() {
    argParser
      ..addOption(
        'config',
        abbr: 'c',
        defaultsTo: 'promptguard.yaml',
        help: 'Path to the promptguard.yaml suite file.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit the report as JSON instead of text.',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Write the report to this file (Markdown).',
      )
      ..addOption(
        'env-lookup',
        help: 'Override environment lookup (for tests).',
        hide: true,
      )
      ..addFlag(
        'parallel',
        abbr: 'p',
        negatable: false,
        help: 'Run tests concurrently.',
      )
      ..addOption(
        'snapshots',
        help: 'Directory for output snapshots (golden files). Enables snapshot checks.',
      )
      ..addFlag(
        'update-snapshots',
        negatable: false,
        help: 'Write current outputs as the new snapshots.',
      );
  }

  @override
  String get name => 'run';

  @override
  String get description =>
      'Run every prompt test and report pass/fail with diffs.';

  @override
  Future<int> run() async {
    final configPath = p.normalize(p.join(
      Directory.current.path,
      argResults!['config'] as String,
    ));

    final Suite suite;
    try {
      suite = Suite.load(configPath);
    } on StateError catch (error) {
      stdout.writeln('Error: ${error.message}');
      return 66;
    }

    String Function(String) envLookup;
    final envOverride = argResults?['env-lookup'] as String?;
    if (envOverride != null) {
      // Format: "KEY1=value1,KEY2=value2" — used by tests.
      final map = <String, String>{};
      for (final pair in envOverride.split(',')) {
        final index = pair.indexOf('=');
        if (index > 0) map[pair.substring(0, index)] = pair.substring(index + 1);
      }
      envLookup = (name) => map[name] ?? '';
    } else {
      envLookup = (name) => Platform.environment[name] ?? '';
    }

    final registry = defaultRegistry(envLookup);
    final runner = PromptGuardRunner(registry);

    final parallel = argResults!['parallel'] == true;
    stdout.writeln(
        'Running ${suite.tests.length} prompt tests${parallel ? ' (parallel)' : ''}…');
    final report = await runner.runSuite(
      suite,
      parallel: parallel,
      snapshotDir: argResults?['snapshots'] as String?,
      updateSnapshots: argResults!['update-snapshots'] == true,
    );

    if (argResults!['json'] == true) {
      stdout.writeln(_toJson(report));
    } else {
      _printHuman(report);
    }

    final output = argResults?['output'] as String?;
    if (output != null) {
      final outputPath = p.normalize(p.join(Directory.current.path, output));
      writeTextFile(outputPath, report.toMarkdown());
      stdout.writeln('Report written to $output');
    }

    return report.failures == 0 ? 0 : 1;
  }

  void _printHuman(RunReport report) {
    for (final result in report.results) {
      final icon = result.passed ? '✅' : '❌';
      stdout.writeln('$icon ${result.test.id} (${result.durationMs}ms)');
      for (var i = 0; i < result.expectationResults.length; i++) {
        final expectation = result.test.expectations[i];
        final ok = result.expectationResults[i];
        stdout.writeln('   ${ok ? '✅' : '❌'} ${expectation.describe}');
      }
      if (!result.passed) {
        final snippet = _clip(result.output, 200);
        if (snippet.isNotEmpty) {
          stdout.writeln('   output: $snippet');
        }
        if (result.error != null) {
          stdout.writeln('   error: ${_clip(result.error!, 200)}');
        }
      }
    }
    final total = report.total;
    final failed = report.failures;
    final usage = report.totalUsage;
    if (usage.totalTokens > 0) {
      final cost = report.totalCostUsd;
      final costText = cost > 0 && cost < 0.01
          ? cost.toStringAsFixed(4)
          : cost.toStringAsFixed(2);
      stdout.writeln(
          'Tokens: ${usage.promptTokens} in / ${usage.completionTokens} out (est. \$$costText)');
    }
    stdout.writeln();
    if (failed == 0) {
      stdout.writeln('All $total prompt tests passed.');
    } else {
      stdout.writeln('$failed of $total prompt tests FAILED.');
    }
  }

  String _toJson(RunReport report) {
    final buffer = StringBuffer('{"tests":[');
    for (var i = 0; i < report.results.length; i++) {
      final r = report.results[i];
      if (i > 0) buffer.write(',');
      buffer.write(
          '{"id":"${_escape(r.test.id)}","passed":${r.passed},"duration_ms":${r.durationMs},'
          '"output":${_jsonString(r.output)}');
      if (r.error != null) {
        buffer.write(',"error":${_jsonString(r.error!)}');
      }
      buffer.write('}');
    }
    buffer.write('],"total":${report.total},"failures":${report.failures}}');
    return buffer.toString();
  }

  String _jsonString(String text) => '"${_escape(text.replaceAll('"', '\\"'))}"';

  String _escape(String text) =>
      text.replaceAll('\n', '\\n').replaceAll('\r', '').replaceAll('\t', '\\t');
}

String _clip(String text, int length) {
  text = text.trim();
  return text.length <= length ? text : '${text.substring(0, length)}…';
}
