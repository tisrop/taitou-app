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

  String? command;
  for (final arg in args) {
    if (!arg.startsWith('-')) {
      command = arg;
      break;
    }
  }
  if (command != null && _commandsRequiringAppPrep.contains(command)) {
    await _prepare('app');
  } else if (command != null && _commandsRequiringTestPrep.contains(command)) {
    await _prepare('test');
  }

  await runFlutterOrExit(
    title: '执行 flutter ${args.join(' ')}',
    arguments: args,
  );
}

Future<void> _prepare(String command) {
  return runOrExit(
    title: command == 'test' ? '执行测试预处理' : '执行项目预处理',
    executable: Platform.resolvedExecutable,
    arguments: ['tool/project_prep.dart', command],
  );
}
