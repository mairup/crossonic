/*
 * Copyright 2024-2026 Julian Hofmann (+ Crossonic contributors).
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:crossonic/data/repositories/settings/settings_repository.dart';
import 'package:crossonic/system_integration.dart';
import 'package:crossonic/ui/common/toast.dart';
import 'package:flutter_system_integration/flutter_system_integration.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

@RoutePage()
class UpdatesPage extends StatefulWidget {
  final bool autoStart;

  const UpdatesPage({super.key, this.autoStart = false});

  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  AutoUpdateRepository? _autoUpdateRepo;
  VersionRepository? _versionRepo;
  SettingsRepository? _settingsRepo;

  Version? _currentVersion;
  Version? _latestVersion;
  PendingUpdate? _pendingUpdate;

  bool _checking = false;
  Timer? _restartTimer;

  AppImageRepository? _appImageRepo;
  bool? _integrated;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _restartTimer?.cancel();
    _autoUpdateRepo?.removeListener(_onRepoChanged);
    super.dispose();
  }

  void _onRepoChanged() {
    if (mounted) setState(() {});
    if (_autoUpdateRepo?.status == AutoUpdateStatus.success &&
        _restartTimer == null &&
        Restart.supported) {
      _restartTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) Restart.restart();
      });
    }
  }

  Future<void> _init() async {
    if (!mounted) return;
    _versionRepo = context.read<VersionRepository>();
    _settingsRepo = context.read<SettingsRepository>();

    if (AutoUpdateRepository.autoUpdatesSupported(systemIntegrationConfig)) {
      _autoUpdateRepo = context.read<AutoUpdateRepository>();
      _autoUpdateRepo?.addListener(_onRepoChanged);
    }

    if (AppImageRepository.isAppImage) {
      _appImageRepo = context.read<AppImageRepository>();
      _appImageRepo!.isIntegrated().then((v) {
        if (mounted) setState(() => _integrated = v);
      });
    }

    _currentVersion = await VersionRepository.getCurrentVersion();
    
    if (widget.autoStart) {
      await _checkAndInstall();
    } else {
      await _check(silent: true);
    }
  }

  Future<void> _checkAndInstall() async {
    await _check(silent: true);
    if (_pendingUpdate != null && mounted) {
      await _install();
    }
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking || !mounted) return;
    setState(() => _checking = true);
    try {
      if (_autoUpdateRepo != null) {
        final pending = await _autoUpdateRepo!.prepareUpdate();
        if (mounted) {
          _pendingUpdate = pending;
          if (pending != null) {
            _latestVersion = Version.parse(pending.tag);
          } else {
            _latestVersion = await _versionRepo?.getLatestVersion(force: true);
          }
        }
      } else {
        _latestVersion = await _versionRepo?.getLatestVersion(force: true);
      }

      if (!silent && mounted) {
        if (_latestVersion != null &&
            _currentVersion != null &&
            _latestVersion! <= _currentVersion!) {
          Toast.show(context, "Crossonic is up to date (v$_currentVersion)!");
        }
      }
    } catch (e) {
      if (!silent && mounted) {
        Toast.show(context, "Failed to check for updates: $e");
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _install() async {
    final repo = _autoUpdateRepo;
    var pending = _pendingUpdate;
    if (repo == null) return;

    if (pending == null) {
      pending = await repo.prepareUpdate();
      _pendingUpdate = pending;
    }
    if (pending == null) {
      if (mounted) {
        Toast.show(context, "Already running the latest version!");
      }
      return;
    }

    if (await repo.needsInstallPermission()) {
      if (!await repo.requestInstallPermission()) {
        if (mounted) {
          Toast.show(context, "Permission not granted to install updates.");
        }
        return;
      }
    }

    await repo.update(pending);
  }

  Future<void> _integrate() async {
    try {
      await _appImageRepo!.integrate();
    } on Exception {
      if (mounted) Toast.show(context, "Failed to integrate AppImage!");
      return;
    }
    Restart.restart();
  }

  @override
  Widget build(BuildContext context) {
    final status = _autoUpdateRepo?.status ?? AutoUpdateStatus.initial;
    final isUpdating = status == AutoUpdateStatus.checkingVersion ||
        status == AutoUpdateStatus.downloading ||
        status == AutoUpdateStatus.installing;
    final hasUpdate = _latestVersion != null &&
        _currentVersion != null &&
        _latestVersion! > _currentVersion!;
    final canAutoUpdate =
        AutoUpdateRepository.autoUpdatesSupported(systemIntegrationConfig);

    return Scaffold(
      appBar: AppBar(title: const Text("Updates")),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          status == AutoUpdateStatus.success
                              ? Icons.check_circle
                              : status == AutoUpdateStatus.failure
                                  ? Icons.error_outline
                                  : hasUpdate
                                      ? Icons.system_update
                                      : Icons.verified_outlined,
                          size: 32,
                          color: status == AutoUpdateStatus.success
                              ? Colors.green
                              : status == AutoUpdateStatus.failure
                                  ? Colors.red
                                  : hasUpdate
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.secondary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Crossonic",
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                _currentVersion != null
                                    ? "Installed: v$_currentVersion"
                                    : "Loading version...",
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      switch (status) {
                        AutoUpdateStatus.downloading =>
                          "Downloading v${_latestVersion ?? _pendingUpdate?.tag ?? ''}...",
                        AutoUpdateStatus.installing => "Installing update...",
                        AutoUpdateStatus.success => Restart.supported
                            ? "Update installed! Restarting Crossonic..."
                            : "Update installed! Please restart the app.",
                        AutoUpdateStatus.failure =>
                          "Update failed. Check connection and retry.",
                        _ => _checking
                            ? "Checking for new versions..."
                            : hasUpdate
                                ? "New version available: v$_latestVersion"
                                : "You have the latest version.",
                      },
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    if (status == AutoUpdateStatus.downloading) ...[
                      const SizedBox(height: 12),
                      StreamBuilder<double>(
                        stream: _autoUpdateRepo?.downloadProgress,
                        builder: (context, snapshot) {
                          final progress = snapshot.data ?? 0.0;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              LinearProgressIndicator(
                                value: progress > 0 ? progress : null,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "${(progress * 100).toInt()}%",
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          );
                        },
                      ),
                    ] else if (isUpdating || _checking) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (status == AutoUpdateStatus.success)
                          FilledButton.icon(
                            onPressed: () {
                              if (Restart.supported) {
                                Restart.restart();
                              } else {
                                Toast.show(context, "Please restart Crossonic");
                              }
                            },
                            icon: const Icon(Icons.restart_alt),
                            label: Text(
                              Restart.supported ? "Restart now" : "Restart",
                            ),
                          )
                        else if (status == AutoUpdateStatus.failure)
                          FilledButton.icon(
                            onPressed: _install,
                            icon: const Icon(Icons.refresh),
                            label: const Text("Retry"),
                          )
                        else if (hasUpdate && canAutoUpdate)
                          FilledButton.icon(
                            onPressed: isUpdating ? null : _install,
                            icon: const Icon(Icons.download),
                            label: Text(
                              Restart.supported
                                  ? "Update & Restart"
                                  : "Install Update",
                            ),
                          )
                        else if (!isUpdating)
                          FilledButton.tonalIcon(
                            onPressed: _checking ? null : () => _check(silent: false),
                            icon: const Icon(Icons.refresh),
                            label: const Text("Check for updates"),
                          ),
                        if (hasUpdate || !canAutoUpdate)
                          TextButton.icon(
                            onPressed: () => launchUrl(
                              systemIntegrationConfig.releasesUrl,
                            ),
                            icon: const Icon(Icons.open_in_new),
                            label: const Text("View on Forgejo"),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "Settings",
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  if (_settingsRepo != null)
                    ListenableBuilder(
                      listenable: _settingsRepo!.versionChecking,
                      builder: (context, _) {
                        return SwitchListTile(
                          title: const Text("Check automatically"),
                          subtitle: const Text(
                            "Periodically check for new releases on startup",
                          ),
                          value: _settingsRepo!.versionChecking.enabled,
                          onChanged: (val) {
                            _settingsRepo!.versionChecking.enabled = val;
                          },
                        );
                      },
                    ),
                  if (_appImageRepo != null) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.install_desktop),
                      title: Text(
                        _integrated == null
                            ? "Desktop integration: checking..."
                            : _integrated!
                                ? "Desktop integration: installed"
                                : "Desktop integration: not installed",
                      ),
                      subtitle: Text(
                        "Moves the AppImage to ~/.local/bin and adds a launcher entry and window icon.\n"
                        "${AppImageRepository.appImageFile.path}",
                      ),
                      isThreeLine: true,
                      trailing: _integrated == true
                          ? OutlinedButton(
                              onPressed: _integrate,
                              child: const Text("Re-integrate"),
                            )
                          : FilledButton(
                              onPressed: _integrated == null ? null : _integrate,
                              child: const Text("Integrate"),
                            ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
