// CLI entry point: wires up the command registry.

import 'package:args/command_runner.dart';

import 'commands/example.dart';
import 'commands/watch.dart';
import 'commands/init.dart';
import 'commands/run.dart';

const version = '0.1.0';

/// Runs promptguard with the given arguments. Exposed for tests.
Future<int> run(List<String> arguments) async {
  final runner = CommandRunner<int>(
    'promptguard',
    'Regression testing for every AI feature in your app.',
  )
    ..addCommand(buildRunCommand())
    ..addCommand(buildInitCommand())
    ..addCommand(buildExampleCommand())
    ..addCommand(buildWatchCommand());

  try {
    return await runner.run(arguments) ?? 0;
  } on UsageException catch (error) {
    print('Error: ${error.message}');
    return 64;
  }
}
