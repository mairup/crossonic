/*
 * Copyright 2024-2026 Julian Hofmann (+ Crossonic contributors).
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:crossonic/system_integration.dart';
import 'package:flutter_system_integration/flutter_system_integration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // guards the vendored flutter_system_integration patches: the fork counts
  // its releases in the +build part (0.5.3+19 = upstream 0.5.3 + fork build
  // 19) and the vendored Version must compare it as a revision
  test("Version parses and orders the fork's +build revisions", () {
    final v = Version.parse("v0.5.3+19");
    expect(v.major, 0);
    expect(v.minor, 5);
    expect(v.patch, 3);
    expect(v.revision, 19);
    expect(v.isFullVersion, isTrue);
    expect(v.toString(), "0.5.3+19");

    expect(Version.parse("0.5.3+19"), greaterThan(Version.parse("0.5.3+18")));
    expect(Version.parse("0.5.3+18"), greaterThan(Version.parse("0.5.3")));
    expect(Version.parse("0.5.3"), greaterThan(Version.parse("v0.5.2")));
    // an upstream release always beats any fork build of the older version
    expect(Version.parse("0.5.4"), greaterThan(Version.parse("0.5.3+99")));
    // pub forbids a 4th numeric component, so this must stay invalid
    expect(() => Version.parse("0.5.3.1"), throwsA(isA<InvalidVersion>()));
    // prereleases are still not full versions and get skipped by tag scans
    expect(Version.parse("0.5.3-fork.1").isFullVersion, isFalse);
    // non-numeric build metadata is ignored
    expect(Version.parse("0.5.3+abc").revision, 0);
  });

  test("version checking and auto updates target the fork forge", () {
    expect(systemIntegrationConfig.githubOwner, "mai");
    expect(systemIntegrationConfig.githubRepo, "crossonic");
    expect(systemIntegrationConfig.githubApiBaseUri.host, "git.mairup.space");
    expect(
      systemIntegrationConfig.githubApiBaseUri.path,
      "/api/v1/",
    );
    expect(systemIntegrationConfig.githubWebBaseUri.host, "git.mairup.space");
    expect(
      systemIntegrationConfig.releasesUrl.toString(),
      "https://git.mairup.space/mai/crossonic/releases",
    );
  });
}
