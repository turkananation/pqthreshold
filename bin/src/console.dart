/// Presentation layer for the pqthreshold CLI (ANSI styling, banner, status lines).
library;

import 'dart:io';

import 'version.g.dart';

Console get console => Console.instance;

/// SGR escape-code wrapper.
class Ansi {
  const Ansi(this.enabled);

  final bool enabled;

  String _sgr(String code, String text) =>
      enabled ? '\x1B[${code}m$text\x1B[0m' : text;

  String bold(String text) => _sgr('1', text);
  String dim(String text) => _sgr('2', text);
  String underline(String text) => _sgr('4', text);
  String green(String text) => _sgr('32', text);
  String yellow(String text) => _sgr('33', text);
  String cyan(String text) => _sgr('36', text);
  String gray(String text) => _sgr('90', text);
  String brightCyan(String text) => _sgr('96', text);
  String brightGreen(String text) => _sgr('92', text);
  String brightRed(String text) => _sgr('91', text);
  String raw(String code, String text) => _sgr(code, text);
}

/// Styled writer for stdout/stderr.
class Console {
  Console(this.ansi, {IOSink? out, IOSink? err})
    : _out = out ?? stdout,
      _err = err ?? stderr;

  final Ansi ansi;
  final IOSink _out;
  final IOSink _err;

  static Console instance = Console(Ansi(_autoColor()));

  static void configure({required bool color}) =>
      instance = Console(Ansi(color));

  bool get color => ansi.enabled;

  int get width {
    if (!stdout.hasTerminal) return 80;
    final columns = stdout.terminalColumns;
    return columns > 0 ? columns : 80;
  }

  void success(String message) =>
      _out.writeln('${ansi.brightGreen('✓')} $message');

  void created(String path) =>
      _out.writeln('  ${ansi.green('created')}  ${ansi.bold(path)}');

  void detail(String label, String value, {int pad = 14}) =>
      _out.writeln('  ${ansi.dim(label.padRight(pad))}  $value');

  void section(String title) =>
      _out.writeln('\n${ansi.bold(ansi.underline(title))}');

  void info(String message) => _out.writeln(message);

  void hint(String message) => _out.writeln(ansi.gray(message));

  void warn(String message) =>
      _err.writeln('${ansi.yellow('⚠')} ${ansi.yellow('warning:')} $message');

  void failure(String message) =>
      _err.writeln('${ansi.brightRed('✗')} $message');

  String banner() {
    if (ansi.enabled && width >= 52) return _blockBanner();
    return _compactBanner();
  }

  String _compactBanner() {
    final mark = ansi.bold(ansi.brightCyan('pqthreshold'));
    final tag = ansi.dim('· threshold crypto CLI · v$pqthresholdCliVersion');
    return '$mark $tag';
  }

  String _blockBanner() {
    const palette = ['96', '96', '36', '36', '34', '34'];
    final rows = _assembleWordmark('PQTH');
    final painted = <String>[];
    for (var i = 0; i < rows.length; i++) {
      painted.add('  ${ansi.raw(palette[i], rows[i])}');
    }
    final subtitle = ansi.dim(
      '  FROST Ed25519 · Feldman VSS · Gennaro DKG · complements pqforge',
    );
    return '${painted.join('\n')}\n$subtitle';
  }
}

String usageExamples(Iterable<String> lines) {
  final ansi = Console.instance.ansi;
  final body = lines
      .map((line) => line.startsWith('#') ? '  ${ansi.gray(line)}' : '  $line')
      .join('\n');
  return '\n${ansi.bold('Examples')}\n$body';
}

bool _autoColor() {
  final env = Platform.environment;
  if (env.containsKey('NO_COLOR')) return false;
  final force = env['CLICOLOR_FORCE'];
  if (force != null && force.isNotEmpty && force != '0') return true;
  if (env['TERM'] == 'dumb') return false;
  return stdout.hasTerminal;
}

bool resolveColor(List<String> rawArgs) {
  if (rawArgs.contains('--no-color')) return false;
  return _autoColor();
}

List<String> _assembleWordmark(String word) {
  const height = 6;
  final rows = List.filled(height, '');
  for (var i = 0; i < word.length; i++) {
    final glyph = _glyphs[word[i]];
    if (glyph == null) continue;
    final separator = i == 0 ? '' : ' ';
    for (var r = 0; r < height; r++) {
      rows[r] = '${rows[r]}$separator${glyph[r]}';
    }
  }
  return rows;
}

const Map<String, List<String>> _glyphs = {
  'P': ['██████╗ ', '██╔══██╗', '██████╔╝', '██╔═══╝ ', '██║     ', '╚═╝     '],
  'Q': [
    ' ██████╗ ',
    '██╔═══██╗',
    '██║   ██║',
    '██║▄▄ ██║',
    '╚██████╔╝',
    ' ╚══▀▀═╝ ',
  ],
  'T': ['███████╗', '╚══███╔╝', '  ███╔╝ ', '  ███╔╝ ', '  ███╔╝ ', '  ╚══╝  '],
  'H': ['██╗  ██╗', '██║  ██║', '███████║', '██╔══██║', '██║  ██║', '╚═╝  ╚═╝'],
};
