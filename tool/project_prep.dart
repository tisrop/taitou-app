import 'dart:io';

import '_workspace_cli.dart';

const _androidKeyPropertiesPath = 'android/key.properties';

Future<void> main(List<String> args) async {
  enterWorkspaceRoot();

  final command = args.isEmpty ? 'app' : args.first;

  switch (command) {
    case 'app':
    case 'bootstrap':
      await _prepareApp();
      return;
    case 'test':
      await _prepareApp();
      return;
    case 'doctor':
      await _runDoctor();
      return;
    case 'help':
    case '--help':
    case '-h':
      stdout.writeln(_usage);
      return;
    default:
      stderr.writeln('未知 project prep 子命令: $command');
      stderr.writeln(_usage);
      exit(64);
  }
}

Future<void> _prepareApp() async {
  await ensurePubGet();
  await _generateL10n();
}

Future<void> _generateL10n() {
  return runOrExit(
    title: '生成 l10n',
    executable: Platform.resolvedExecutable,
    arguments: const ['tool/gen_l10n.dart'],
  );
}

Future<void> _runDoctor() async {
  stdout.writeln('==> 检查开发环境');
  await _printCommandStatus('Flutter', flutterExecutable, const ['--version']);
  await _printCommandStatus('Dart', Platform.resolvedExecutable, const [
    '--version',
  ]);
  await _printAndroidJavaStatus();

  stdout.writeln('==> 检查 l10n 生成状态');
  final l10nResult = await _runProcess(Platform.resolvedExecutable, const [
    'tool/gen_l10n.dart',
    '--check',
  ]);
  stdout.write(l10nResult.combinedOutput);
  stdout.writeln(
    l10nResult.exitCode == 0 ? '[OK] l10n 生成状态正常' : '[FAILED] l10n 生成状态异常',
  );

  stdout.writeln('==> 检查 Android 签名状态');
  _printAndroidSigningStatus();
}

Future<void> _printAndroidJavaStatus() async {
  final runtime = await resolveAndroidJavaRuntime();
  if (runtime == null) {
    stdout.writeln('[MISSING] Android Gradle JDK: 未找到受支持的 JDK 17+/ < 26');
    return;
  }

  stdout.writeln(
    '[OK] Android Gradle JDK: Java ${runtime.majorVersion} @ ${runtime.home} (${runtime.source})',
  );
}

void _printAndroidSigningStatus() {
  final keyPropertiesFile = File(_androidKeyPropertiesPath);
  if (!keyPropertiesFile.existsSync()) {
    stdout.writeln(
      '[FALLBACK] Android local signing: 缺少 $_androidKeyPropertiesPath，debug 使用默认 debug signing，profile/release 将回退 debug signing',
    );
    return;
  }

  final properties = _readSimpleProperties(keyPropertiesFile);
  final missingFields = <String>[
    if (_readNonBlank(properties, 'keyAlias') == null) 'keyAlias',
    if (_readNonBlank(properties, 'keyPassword') == null) 'keyPassword',
    if (_readNonBlank(properties, 'storePassword') == null) 'storePassword',
  ];

  final storeFileValue = _readNonBlank(properties, 'storeFile');
  final storeFile = _resolveAndroidStoreFile(storeFileValue);
  if (storeFileValue == null || storeFile == null || !storeFile.existsSync()) {
    missingFields.add('storeFile');
  }

  if (missingFields.isEmpty) {
    stdout.writeln(
      '[OK] Android local signing: ${storeFile!.path}（debug/profile/release）',
    );
    return;
  }

  stdout.writeln(
    '[FALLBACK] Android local signing: 配置不完整（${missingFields.join(', ')}），debug 使用默认 debug signing，profile/release 将回退 debug signing',
  );
}

Map<String, String> _readSimpleProperties(File file) {
  final properties = <String, String>{};
  for (final rawLine in file.readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('!')) {
      continue;
    }

    final equalIndex = line.indexOf('=');
    final colonIndex = line.indexOf(':');
    final separatorIndex = equalIndex == -1
        ? colonIndex
        : colonIndex == -1
        ? equalIndex
        : equalIndex < colonIndex
        ? equalIndex
        : colonIndex;
    if (separatorIndex <= 0) {
      continue;
    }

    final key = line.substring(0, separatorIndex).trim();
    final value = line.substring(separatorIndex + 1).trim();
    if (key.isNotEmpty) {
      properties[key] = value;
    }
  }
  return properties;
}

String? _readNonBlank(Map<String, String> properties, String key) {
  final value = properties[key]?.trim();
  return value == null || value.isEmpty ? null : value;
}

File? _resolveAndroidStoreFile(String? rawPath) {
  final normalized = rawPath?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }

  final directFile = File(normalized);
  if (directFile.isAbsolute) {
    return directFile;
  }

  final candidates = <String>{
    'android/app/$normalized',
    'android/$normalized',
    normalized,
  };
  for (final candidate in candidates) {
    final file = File(candidate);
    if (file.existsSync()) {
      return file;
    }
  }

  return File('android/$normalized');
}

Future<void> _printCommandStatus(
  String label,
  String executable,
  List<String> arguments,
) async {
  final result = await _runProcess(executable, arguments);
  if (result.exitCode == 0) {
    final firstLine = result.combinedOutput
        .split(RegExp(r'\r?\n'))
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');
    stdout.writeln('[OK] $label: $firstLine');
    return;
  }

  stdout.writeln('[MISSING] $label');
}

Future<_ProcessResult> _runProcess(
  String executable,
  List<String> arguments,
) async {
  try {
    final result = await Process.run(
      executable,
      arguments,
      runInShell: Platform.isWindows,
    );
    return _ProcessResult(
      exitCode: result.exitCode,
      combinedOutput: '${result.stdout}${result.stderr}',
    );
  } on ProcessException catch (error) {
    return _ProcessResult(exitCode: 1, combinedOutput: error.message);
  }
}

class _ProcessResult {
  const _ProcessResult({required this.exitCode, required this.combinedOutput});

  final int exitCode;
  final String combinedOutput;
}

const _usage = '''
用法:
  dart tool/project_prep.dart app
  dart tool/project_prep.dart test
  dart tool/project_prep.dart doctor
''';
