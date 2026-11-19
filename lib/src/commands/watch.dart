// `promptguard watch` — re-run the suite on config changes.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../core/runner.dart';
import '../core/suite.dart';
import '../providers/http_providers.dart';

Command<int> buildWatchCommand() => WatchCommand();

class WatchCommand extends Command<int> {
  WatchCommand() {
    argParser
      ..addOption(
        'config',
        abbr: 'c',
        defaultsTo: 'promptguard.yaml',
        help: 'Path to the promptguard.yaml suite file.',
      )
      ..addOption('interval',
          defaultsTo: '2',
          help: 'Poll interval in seconds (file polling is portable).');
  }

  @override
  String get name => 'watch';

  @override
  String get description =>
      'Re-run prompt tests whenever the suite file changes (tune-and-verify loop).';

  @override
  Future<int> run() async {
    final configPath = p.normalize(
      p.join(Directory.current.path, argResults!['config'] as String),
    );
    final interval =
        int.tryParse(argResults!['interval'] as String) ?? 2;

    if (!File(configPath).existsSync()) {
      stdout.writeln('No $configPath here — run `promptguard init` first.');
      return 66;
    }

    stdout.writeln(
        'Watching $configPath — edit it and results re-run automatically. Ctrl-C to stop.');

    var lastModified = File(configPath).lastModifiedSync();
    while (true) {
      await Future<void>.delayed(Duration(seconds: interval));
      final modified = File(configPath).lastModifiedSync();
      if (!modified.isAfter(lastModified)) continue;
      lastModified = modified;

      stdout.writeln();
      stdout.writeln('↻ change detected — re-running…');
      try {
        final suite = Suite.load(configPath);
        final registry = defaultRegistry(
          (name) => Platform.environment[name] ?? '',
        );
        final report =
            await PromptGuardRunner(registry).runSuite(suite, parallel: true);
        final failed = report.failures;
        stdout.writeln(
            '${failed == 0 ? '✅ all passed' : '❌ $failed of ${report.total} failed'} '
            '(${report.total} tests)');
      } catch (error) {
        stdout.writeln('⚠ config error: $error');
      }
    }
  }
}
