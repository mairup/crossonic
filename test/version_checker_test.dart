/*
 * Copyright 2024-2026 Julian Hofmann (+ Crossonic contributors).
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:crossonic/version_checker.dart';
import 'package:flutter_system_integration/flutter_system_integration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockVersionCheckerViewModel extends Mock
    implements VersionCheckerViewModel {}

void main() {
  late MockVersionCheckerViewModel vm;

  setUp(() {
    vm = MockVersionCheckerViewModel();
    when(() => vm.showUpdateSuccessful).thenReturn(false);
    when(() => vm.newVersionAvailable).thenReturn(false);
    when(() => vm.isOpen).thenReturn(false);
    when(() => vm.addListener(any())).thenReturn(null);
    when(() => vm.removeListener(any())).thenReturn(null);
  });

  Widget buildWidget({Widget child = const Text("Child App")}) {
    return ChangeNotifierProvider<VersionCheckerViewModel>.value(
      value: vm,
      child: MaterialApp(home: Scaffold(body: VersionChecker(child: child))),
    );
  }

  testWidgets('renders child when no update available', (tester) async {
    await tester.pumpWidget(buildWidget());
    expect(find.text("Child App"), findsOneWidget);
    expect(find.text("Update Available"), findsNothing);
  });

  testWidgets('shows streamlined dialog with Later or View Release',
      (tester) async {
    when(() => vm.newVersionAvailable).thenReturn(true);
    when(() => vm.isOpen).thenReturn(false);
    when(() => vm.current).thenReturn(const Version(major: 0, minor: 5, patch: 2));
    when(() => vm.latest).thenReturn(const Version(major: 0, minor: 5, patch: 4));
    when(() => vm.displayedVersionDialog()).thenAnswer((_) async {});

    await tester.pumpWidget(buildWidget());
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text("Update Available"), findsOneWidget);
    expect(find.text("Later"), findsOneWidget);
    expect(find.text("Ignore"), findsOneWidget);
    expect(find.text("View Release"), findsOneWidget);

    await tester.tap(find.text("Later"));
    await tester.pumpAndSettle();

    verify(() => vm.displayedVersionDialog()).called(1);
  });

  testWidgets('Ignore choice calls ignoreVersion and displayedVersionDialog',
      (tester) async {
    when(() => vm.newVersionAvailable).thenReturn(true);
    when(() => vm.isOpen).thenReturn(false);
    when(() => vm.current).thenReturn(const Version(major: 0, minor: 5, patch: 2));
    when(() => vm.latest).thenReturn(const Version(major: 0, minor: 5, patch: 4));
    when(() => vm.ignoreVersion()).thenAnswer((_) async {});
    when(() => vm.displayedVersionDialog()).thenAnswer((_) async {});

    await tester.pumpWidget(buildWidget());
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text("Ignore"));
    await tester.pumpAndSettle();

    verify(() => vm.ignoreVersion()).called(1);
    verify(() => vm.displayedVersionDialog()).called(1);
  });
}
