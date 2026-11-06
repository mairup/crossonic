/*
 * Copyright 2024-2026 Julian Hofmann (+ Crossonic contributors).
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:crossonic/system_integration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
