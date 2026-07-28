import 'dart:convert';
import 'dart:io';

import '_workspace_cli.dart';

const _commandsRequiringAppPrep = {'run', 'build', 'drive'};
const _commandsRequiringTestPrep = {'test'};

Future<void> main(List<String> args) async {
  enterWorkspaceRoot();

  if (args.isEmpty) {
    stderr.writeln('用法: dart tool/flutterw.dart <flutter args...>');
    exit(64);
  }

  final command = _firstFlutterCommand(args);
  if (command != null && _commandsRequiringAppPrep.contains(command)) {
    await runOrExit(
      title: '执行项目预处理',
      executable: Platform.resolvedExecutable,
      arguments: const ['tool/project_prep.dart', 'app'],
    );
    await _prepareAndroidNativeIfNeeded(command, args);
  } else if (command != null && _commandsRequiringTestPrep.contains(command)) {
    await runOrExit(
      title: '执行测试预处理',
      executable: Platform.resolvedExecutable,
      arguments: const ['tool/project_prep.dart', 'test'],
    );
  }

  await runFlutterOrExit(
    title: '执行 flutter ${args.join(' ')}',
    arguments: args,
  );
}

Future<void> _prepareAndroidNativeIfNeeded(
  String command,
  List<String> args,
) async {
  final targetPlatform = await _detectAndroidTargetPlatform(command, args);
  if (targetPlatform == null && command != 'build') {
    return;
  }

  final nativeArgs = <String>[
    'tool/project_tasks.dart',
    'native:prepare',
    'android',
    _detectBuildMode(command, args),
  ];
  final requestedTargetPlatform =
      _extractOptionValue(args, '--target-platform', '--target-platform') ??
      targetPlatform;
  if (requestedTargetPlatform != null && requestedTargetPlatform.isNotEmpty) {
    nativeArgs.add('--target-platform=$requestedTargetPlatform');
  }

  await runOrExit(
    title: '准备 Android 原生产物',
    executable: Platform.resolvedExecutable,
    arguments: nativeArgs,
  );
}

String? _firstFlutterCommand(List<String> args) {
  for (final arg in args) {
    if (!arg.startsWith('-')) {
      return arg;
    }
  }
  return null;
}

Future<String?> _detectAndroidTargetPlatform(
  String command,
  List<String> args,
) async {
  if (command == 'build') {
    final buildTarget = _firstPositionalAfter(args, 'build');
    if (buildTarget == 'apk' ||
        buildTarget == 'appbundle' ||
        buildTarget == 'aar') {
      return null;
    }
    stderr.writeln('本仓库仅支持 Android 构建，请使用 apk、appbundle 或 aar。');
    exit(64);
  }

  if (command != 'run' && command != 'drive') {
    return null;
  }

  final deviceId = _extractOptionValue(args, '-d', '--device-id');
  if (deviceId == 'android') {
    return null;
  }

  final devices = await _loadFlutterDevices();
  final resolvedDevice = switch (deviceId) {
    null =>
      devices.where((device) => device.isAndroid).length == 1
          ? devices.where((device) => device.isAndroid).single
          : null,
    _ => devices.where((device) => device.id == deviceId).firstOrNull,
  };
  if (resolvedDevice == null) {
    return null;
  }
  if (!resolvedDevice.isAndroid) {
    stderr.writeln('本仓库仅支持 Android 设备: ${resolvedDevice.id}');
    exit(64);
  }
  return resolvedDevice.targetPlatform;
}

String _detectBuildMode(String command, List<String> args) {
  if (args.contains('--debug')) {
    return '--debug';
  }
  if (args.contains('--profile')) {
    return '--profile';
  }
  if (args.contains('--release')) {
    return '--release';
  }
  return command == 'run' ? '--debug' : '--release';
}

String? _firstPositionalAfter(List<String> args, String command) {
  final commandIndex = args.indexOf(command);
  if (commandIndex == -1) {
    return null;
  }

  for (var index = commandIndex + 1; index < args.length; index++) {
    final value = args[index];
    if (!value.startsWith('-')) {
      return value;
    }
  }
  return null;
}

String? _extractOptionValue(
  List<String> args,
  String shortOption,
  String longOption,
) {
  for (var index = 0; index < args.length; index++) {
    final value = args[index];
    if (value == shortOption || value == longOption) {
      if (index + 1 < args.length) {
        return args[index + 1];
      }
      return null;
    }
    if (value.startsWith('$longOption=')) {
      return value.substring(longOption.length + 1);
    }
  }
  return null;
}

Future<List<_FlutterDevice>> _loadFlutterDevices() async {
  try {
    final result = await Process.run(
      flutterExecutable,
      const ['devices', '--machine'],
      runInShell: Platform.isWindows,
      environment: await androidBuildEnvironment(),
      workingDirectory: workspaceRootPath,
    );
    if (result.exitCode != 0) {
      return const [];
    }

    final decoded = jsonDecode(result.stdout.toString());
    if (decoded is! List) {
      return const [];
    }

    return decoded
        .whereType<Map>()
        .map((item) => _FlutterDevice.fromJson(item.cast<String, dynamic>()))
        .whereType<_FlutterDevice>()
        .toList();
  } catch (_) {
    return const [];
  }
}

class _FlutterDevice {
  const _FlutterDevice({required this.id, required this.targetPlatform});

  final String id;
  final String targetPlatform;

  bool get isAndroid => targetPlatform.startsWith('android');

  static _FlutterDevice? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim();
    final targetPlatform = json['targetPlatform']?.toString().trim();
    if (id == null ||
        id.isEmpty ||
        targetPlatform == null ||
        targetPlatform.isEmpty) {
      return null;
    }
    return _FlutterDevice(id: id, targetPlatform: targetPlatform);
  }
}

extension on Iterable<_FlutterDevice> {
  _FlutterDevice? get firstOrNull => isEmpty ? null : first;
}
