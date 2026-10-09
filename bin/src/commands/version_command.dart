/// `version` subcommand.
library;

import 'package:args/command_runner.dart';

import '../console.dart';
import '../version.g.dart';

/// Prints the CLI version (same as `--version`).
final class VersionCommand extends Command<void> {
  @override
  String get name => 'version';

  @override
  String get description => 'Print the pqthreshold version and exit.';

  @override
  Future<void> run() async =>
      console.info('pqthreshold $pqthresholdCliVersion');
}
