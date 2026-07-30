import 'dart:io';

import '_workspace_cli.dart';

Future<void> main(List<String> args) async {
  enterWorkspaceRoot();

  if (args.isEmpty) {
    stderr.writeln(_usage);
    exit(64);
  }

  switch (args.first) {
    case 'app:clean':
      await _appClean();
      return;
    case 'app:rebuild':
      await _appRebuild(args.sublist(1));
      return;
    case 'test:all':
      await _testAll(args.sublist(1));
      return;
    case 'run:prepare':
      await _runProjectPrep('app');
      return;
    case 'release:prepare':
      await _releasePrepare(args.sublist(1));
      return;
    case 'help':
    case '--help':
    case '-h':
      stdout.writeln(_usage);
      return;
    default:
      stderr.writeln('未知项目任务: ${args.first}');
      stderr.writeln(_usage);
      exit(64);
  }
}

Future<void> _appClean() async {
  await runFlutterOrExit(title: '执行 flutter clean', arguments: const ['clean']);
  resetPubGetStamp();
}

Future<void> _appRebuild(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      '用法: dart tool/project_tasks.dart app:rebuild <flutter build args...>',
    );
    exit(64);
  }

  await _appClean();
  await runOrExit(
    title: '执行 flutter build ${args.join(' ')}',
    executable: Platform.resolvedExecutable,
    arguments: ['tool/flutterw.dart', 'build', ...args],
  );
}

Future<void> _testAll(List<String> args, {bool includePrep = true}) async {
  if (includePrep) {
    await _runProjectPrep('test');
  }

  for (final task in _buildWorkspaceTestTasks(args)) {
    await runFlutterOrExit(
      title: '执行 ${task.label} flutter test',
      arguments: task.arguments,
      workingDirectory: task.workingDirectory,
    );
  }
}

Future<void> _releasePrepare(List<String> args) async {
  final strictAnalyze = args.contains('--strict-analyze');
  final skipAnalyze = args.contains('--skip-analyze');
  final skipTest = args.contains('--skip-test');

  await _runProjectPrep('app');

  if (!skipAnalyze) {
    await runFlutterOrExit(
      title: strictAnalyze ? '执行 flutter analyze' : '执行 flutter analyze（非严格模式）',
      arguments: [
        'analyze',
        if (!strictAnalyze) ...const [
          '--no-fatal-infos',
          '--no-fatal-warnings',
        ],
      ],
    );
  }

  if (!skipTest) {
    await _testAll(const [], includePrep: false);
  }
}

List<_FlutterTestTask> _buildWorkspaceTestTasks(List<String> args) {
  final testPackages = _workspaceTestPackages();
  final targetPackages = <String, List<String>>{};
  final passthroughArgs = <String>[];

  for (var index = 0; index < args.length; index++) {
    final arg = args[index];
    if (_flutterTestOptionConsumesNextValue(arg)) {
      passthroughArgs.add(arg);
      if (index + 1 < args.length) {
        passthroughArgs.add(args[index + 1]);
        index++;
      }
      continue;
    }

    final resolvedTarget = _resolveExplicitTestTarget(arg, testPackages);
    if (resolvedTarget == null) {
      passthroughArgs.add(arg);
      continue;
    }

    targetPackages
        .putIfAbsent(resolvedTarget.packagePath, () => <String>[])
        .add(resolvedTarget.relativeTarget);
  }

  if (targetPackages.isEmpty) {
    return testPackages
        .map(
          (testPackage) => _FlutterTestTask(
            label: testPackage.label,
            arguments: ['test', ...passthroughArgs],
            workingDirectory: testPackage.workingDirectory,
          ),
        )
        .toList(growable: false);
  }

  return testPackages
      .where(
        (testPackage) => targetPackages.containsKey(testPackage.packagePath),
      )
      .map(
        (testPackage) => _FlutterTestTask(
          label: testPackage.label,
          arguments: [
            'test',
            ...passthroughArgs,
            ...targetPackages[testPackage.packagePath]!,
          ],
          workingDirectory: testPackage.workingDirectory,
        ),
      )
      .toList(growable: false);
}

List<_WorkspaceTestPackage> _workspaceTestPackages() {
  final packages = <_WorkspaceTestPackage>[];

  if (Directory('test').existsSync()) {
    packages.add(
      const _WorkspaceTestPackage(
        label: '主应用',
        packagePath: '.',
        workingDirectory: null,
      ),
    );
  }

  final packagesRoot = Directory('packages');
  if (packagesRoot.existsSync()) {
    final packageDirs =
        packagesRoot
            .listSync(followLinks: false)
            .whereType<Directory>()
            .where(
              (directory) => Directory('${directory.path}/test').existsSync(),
            )
            .toList(growable: false)
          ..sort((a, b) => a.path.compareTo(b.path));

    for (final directory in packageDirs) {
      packages.add(
        _WorkspaceTestPackage(
          label: _packageNameFromPath(directory.path),
          packagePath: directory.path,
          workingDirectory: directory.path,
        ),
      );
    }
  }

  return packages;
}

_ExplicitTestTarget? _resolveExplicitTestTarget(
  String arg,
  List<_WorkspaceTestPackage> testPackages,
) {
  if (arg.startsWith('-')) {
    return null;
  }

  final entityType = FileSystemEntity.typeSync(arg, followLinks: true);
  if (entityType == FileSystemEntityType.notFound) {
    return null;
  }

  final absolutePath = _normalizeTestPath(File(arg).absolute.path);
  for (final testPackage in testPackages) {
    final packageRootPath = _normalizeTestPath(
      testPackage.workingDirectory == null
          ? workspaceRootPath
          : Directory(testPackage.workingDirectory!).absolute.path,
    );
    final testRootPath = _normalizeTestPath('$packageRootPath/test');
    final isTestRoot = absolutePath == testRootPath;
    final isUnderTestRoot = absolutePath.startsWith(
      '$testRootPath${Platform.pathSeparator}',
    );
    if (!isTestRoot && !isUnderTestRoot) {
      continue;
    }

    final relativeTarget = absolutePath == testRootPath
        ? 'test'
        : 'test/${absolutePath.substring(testRootPath.length + 1)}';
    return _ExplicitTestTarget(
      packagePath: testPackage.packagePath,
      relativeTarget: relativeTarget,
    );
  }

  return null;
}

Future<void> _runProjectPrep(String command) {
  return runOrExit(
    title: '执行项目预处理 $command',
    executable: Platform.resolvedExecutable,
    arguments: ['tool/project_prep.dart', command],
  );
}

String _packageNameFromPath(String path) {
  final segments = path.replaceAll('\\', '/').split('/');
  return segments.isEmpty ? path : segments.last;
}

bool _flutterTestOptionConsumesNextValue(String arg) =>
    _flutterTestOptionsWithValue.contains(arg);

String _normalizeTestPath(String path) {
  final normalized = path
      .replaceAll('/', Platform.pathSeparator)
      .replaceAll('\\', Platform.pathSeparator);
  final trimmed = normalized.replaceAll(RegExp(r'[\\\/]+$'), '');
  return Platform.isWindows ? trimmed.toLowerCase() : trimmed;
}

const _usage = '''
用法:
  dart tool/project_tasks.dart app:clean
  dart tool/project_tasks.dart app:rebuild <flutter build args...>
  dart tool/project_tasks.dart test:all [flutter test args...]
  dart tool/project_tasks.dart run:prepare
  dart tool/project_tasks.dart release:prepare [--skip-analyze] [--skip-test] [--strict-analyze]
''';

const _flutterTestOptionsWithValue = <String>{
  '-n',
  '--name',
  '-N',
  '--plain-name',
  '-t',
  '--tags',
  '-x',
  '--exclude-tags',
  '-p',
  '--platform',
  '-j',
  '--concurrency',
  '-r',
  '--reporter',
  '--file-reporter',
  '--timeout',
  '--total-shards',
  '--shard-index',
  '--dart-define',
  '--dart-define-from-file',
  '--coverage-path',
  '--test-randomize-ordering-seed',
};

class _WorkspaceTestPackage {
  const _WorkspaceTestPackage({
    required this.label,
    required this.packagePath,
    required this.workingDirectory,
  });

  final String label;
  final String packagePath;
  final String? workingDirectory;
}

class _FlutterTestTask {
  const _FlutterTestTask({
    required this.label,
    required this.arguments,
    required this.workingDirectory,
  });

  final String label;
  final List<String> arguments;
  final String? workingDirectory;
}

class _ExplicitTestTarget {
  const _ExplicitTestTarget({
    required this.packagePath,
    required this.relativeTarget,
  });

  final String packagePath;
  final String relativeTarget;
}
