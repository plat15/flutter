// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:args/command_runner.dart';
import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/commands/build.dart';
import 'package:flutter_tools/src/commands/build_web.dart';
import 'package:flutter_tools/src/features.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';

import '../../src/common.dart';
import '../../src/context.dart';
import '../../src/fakes.dart';
import '../../src/test_build_system.dart';
import '../../src/test_flutter_command_runner.dart';

void main() {
  late FileSystem fileSystem;
  final Platform fakePlatform = FakePlatform(
    environment: <String, String>{
      'FLUTTER_ROOT': '/',
    },
  );

  setUpAll(() {
    Cache.flutterRoot = '';
    Cache.disableLocking();
  });

  setUp(() {
    fileSystem = MemoryFileSystem.test();
    fileSystem.file('pubspec.yaml')
      ..createSync()
      ..writeAsStringSync('name: foo\n');
    fileSystem.file('.packages').createSync();
    fileSystem.file(fileSystem.path.join('web', 'index.html')).createSync(recursive: true);
    fileSystem.file(fileSystem.path.join('lib', 'main.dart')).createSync(recursive: true);
  });

  testUsingContext('Refuses to build for web when missing index.html', () async {
    fileSystem.file(fileSystem.path.join('web', 'index.html')).deleteSync();
    final CommandRunner<void> runner = createTestCommandRunner(BuildCommand());

    expect(
      () => runner.run(<String>['build', 'web', '--no-pub']),
      throwsToolExit(message: 'Missing index.html.')
    );
  }, overrides: <Type, Generator>{
    Platform: () => fakePlatform,
    FileSystem: () => fileSystem,
    FeatureFlags: () => TestFeatureFlags(isWebEnabled: true),
    ProcessManager: () => FakeProcessManager.any(),
  });

  testUsingContext('Refuses to build a debug build for web', () async {
    final CommandRunner<void> runner = createTestCommandRunner(BuildCommand());

    expect(() => runner.run(<String>['build', 'web', '--debug', '--no-pub']),
      throwsA(isA<UsageException>()));
  }, overrides: <Type, Generator>{
    Platform: () => fakePlatform,
    FileSystem: () => fileSystem,
    FeatureFlags: () => TestFeatureFlags(isWebEnabled: true),
    ProcessManager: () => FakeProcessManager.any(),
  });

  testUsingContext('Refuses to build for web when feature is disabled', () async {
    final CommandRunner<void> runner = createTestCommandRunner(BuildCommand());

    expect(
      () => runner.run(<String>['build', 'web', '--no-pub']),
      throwsToolExit(message: '"build web" is not currently supported. To enable, run "flutter config --enable-web".')
    );
  }, overrides: <Type, Generator>{
    Platform: () => fakePlatform,
    FileSystem: () => fileSystem,
    FeatureFlags: () => TestFeatureFlags(),
    ProcessManager: () => FakeProcessManager.any(),
  });

  testUsingContext('Setup for a web build with default output directory', () async {
    final BuildCommand buildCommand = BuildCommand();
    final CommandRunner<void> runner = createTestCommandRunner(buildCommand);
    setupFileSystemForEndToEndTest(fileSystem);
    await runner.run(<String>['build', 'web', '--no-pub', '--dart-define=foo=a', '--dart2js-optimization=O3']);

    final Directory buildDir = fileSystem.directory(fileSystem.path.join('build', 'web'));

    expect(buildDir.existsSync(), true);
  }, overrides: <Type, Generator>{
    Platform: () => fakePlatform,
    FileSystem: () => fileSystem,
    FeatureFlags: () => TestFeatureFlags(isWebEnabled: true),
    ProcessManager: () => FakeProcessManager.any(),
    BuildSystem: () => TestBuildSystem.all(BuildResult(success: true), (Target target, Environment environment) {
      expect(environment.defines, <String, String>{
        'TargetFile': 'lib/main.dart',
        'HasWebPlugins': 'true',
        'cspMode': 'false',
        'SourceMaps': 'false',
        'NativeNullAssertions': 'true',
        'ServiceWorkerStrategy': 'offline-first',
        'Dart2jsOptimization': 'O3',
        'BuildMode': 'release',
        'DartDefines': 'Zm9vPWE=,RkxVVFRFUl9XRUJfQVVUT19ERVRFQ1Q9dHJ1ZQ==',
        'DartObfuscation': 'false',
        'TrackWidgetCreation': 'false',
        'TreeShakeIcons': 'false',
      });
    }),
  });

  testUsingContext('Setup for a web build with a user specified output directory',
      () async {
    final BuildCommand buildCommand = BuildCommand();
    final CommandRunner<void> runner = createTestCommandRunner(buildCommand);

    setupFileSystemForEndToEndTest(fileSystem);

    const String newBuildDir = 'new_dir';
    final Directory buildDir = fileSystem.directory(fileSystem.path.join(newBuildDir));

    expect(buildDir.existsSync(), false);

    await runner.run(<String>[
      'build',
      'web',
      '--no-pub',
      '--output=$newBuildDir'
    ]);

    expect(buildDir.existsSync(), true);
  }, overrides: <Type, Generator>{
    Platform: () => fakePlatform,
    FileSystem: () => fileSystem,
    FeatureFlags: () => TestFeatureFlags(isWebEnabled: true),
    ProcessManager: () => FakeProcessManager.any(),
    BuildSystem: () => TestBuildSystem.all(BuildResult(success: true), (Target target, Environment environment) {
      expect(environment.defines, <String, String>{
        'TargetFile': 'lib/main.dart',
        'HasWebPlugins': 'true',
        'cspMode': 'false',
        'SourceMaps': 'false',
        'NativeNullAssertions': 'true',
        'ServiceWorkerStrategy': 'offline-first',
        'BuildMode': 'release',
        'DartDefines': 'RkxVVFRFUl9XRUJfQVVUT19ERVRFQ1Q9dHJ1ZQ==',
        'DartObfuscation': 'false',
        'TrackWidgetCreation': 'false',
        'TreeShakeIcons': 'false',
      });
    }),
  });

  testUsingContext('hidden if feature flag is not enabled', () async {
    expect(BuildWebCommand(verboseHelp: false).hidden, true);
  }, overrides: <Type, Generator>{
    Platform: () => fakePlatform,
    FileSystem: () => fileSystem,
    FeatureFlags: () => TestFeatureFlags(),
    ProcessManager: () => FakeProcessManager.any(),
  });

  testUsingContext('not hidden if feature flag is enabled', () async {
    expect(BuildWebCommand(verboseHelp: false).hidden, false);
  }, overrides: <Type, Generator>{
    Platform: () => fakePlatform,
    FileSystem: () => fileSystem,
    FeatureFlags: () => TestFeatureFlags(isWebEnabled: true),
    ProcessManager: () => FakeProcessManager.any(),
  });

  testUsingContext('Defaults to web renderer auto mode when no option is specified', () async {
    final TestWebBuildCommand buildCommand = TestWebBuildCommand();
    final CommandRunner<void> runner = createTestCommandRunner(buildCommand);
    setupFileSystemForEndToEndTest(fileSystem);
    await runner.run(<String>['build', 'web', '--no-pub']);
    final BuildInfo buildInfo =
        await buildCommand.webCommand.getBuildInfo(forcedBuildMode: BuildMode.debug);
    expect(buildInfo.dartDefines, contains('FLUTTER_WEB_AUTO_DETECT=true'));
  }, overrides: <Type, Generator>{
    Platform: () => fakePlatform,
    FileSystem: () => fileSystem,
    FeatureFlags: () => TestFeatureFlags(isWebEnabled: true),
    ProcessManager: () => FakeProcessManager.any(),
    BuildSystem: () => TestBuildSystem.all(BuildResult(success: true)),
  });

  testUsingContext('Web build supports build-name and build-number', () async {
    final TestWebBuildCommand buildCommand = TestWebBuildCommand();
    final CommandRunner<void> runner = createTestCommandRunner(buildCommand);
    setupFileSystemForEndToEndTest(fileSystem);

    await runner.run(<String>[
      'build',
      'web',
      '--no-pub',
      '--build-name=1.2.3',
      '--build-number=42',
    ]);

    final BuildInfo buildInfo = await buildCommand.webCommand
        .getBuildInfo(forcedBuildMode: BuildMode.debug);
    expect(buildInfo.buildNumber, '42');
    expect(buildInfo.buildName, '1.2.3');
  }, overrides: <Type, Generator>{
    Platform: () => fakePlatform,
    FileSystem: () => fileSystem,
    FeatureFlags: () => TestFeatureFlags(isWebEnabled: true),
    ProcessManager: () => FakeProcessManager.any(),
    BuildSystem: () => TestBuildSystem.all(BuildResult(success: true)),
  });
}

void setupFileSystemForEndToEndTest(FileSystem fileSystem) {
  final List<String> dependencies = <String>[
    fileSystem.path.join('packages', 'flutter_tools', 'lib', 'src', 'build_system', 'targets', 'web.dart'),
    fileSystem.path.join('bin', 'cache', 'flutter_web_sdk'),
    fileSystem.path.join('bin', 'cache', 'dart-sdk', 'bin', 'snapshots', 'dart2js.dart.snapshot'),
    fileSystem.path.join('bin', 'cache', 'dart-sdk', 'bin', 'dart'),
    fileSystem.path.join('bin', 'cache', 'dart-sdk '),
  ];
  for (final String dependency in dependencies) {
    fileSystem.file(dependency).createSync(recursive: true);
  }

  // Project files.
  fileSystem.file('.packages')
      .writeAsStringSync('''
foo:lib/
fizz:bar/lib/
''');
  fileSystem.file('pubspec.yaml')
      .writeAsStringSync('''
name: foo

dependencies:
  flutter:
    sdk: flutter
  fizz:
    path:
      bar/
''');
  fileSystem.file(fileSystem.path.join('bar', 'pubspec.yaml'))
    ..createSync(recursive: true)
    ..writeAsStringSync('''
name: bar

flutter:
  plugin:
    platforms:
      web:
        pluginClass: UrlLauncherPlugin
        fileName: url_launcher_web.dart
''');
  fileSystem.file(fileSystem.path.join('bar', 'lib', 'url_launcher_web.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync('''
class UrlLauncherPlugin {}
''');
  fileSystem.file(fileSystem.path.join('lib', 'main.dart'))
      .writeAsStringSync('void main() { }');
}

class TestWebBuildCommand extends FlutterCommand {
  TestWebBuildCommand({ bool verboseHelp = false }) :
    webCommand = BuildWebCommand(verboseHelp: verboseHelp) {
    addSubcommand(webCommand);
  }

  final BuildWebCommand webCommand;

  @override
  final String name = 'build';

  @override
  final String description = 'Build a test executable app.';

  @override
  Future<FlutterCommandResult> runCommand() async => FlutterCommandResult.fail();

  @override
  bool get shouldRunPub => false;
}
