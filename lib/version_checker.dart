/*
 * Copyright 2024-2026 Julian Hofmann (+ Crossonic contributors).
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';

import 'package:crossonic/system_integration.dart';
import 'package:crossonic/ui/common/adaptive_dialog_action.dart';
import 'package:crossonic/ui/common/toast.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_system_integration/flutter_system_integration.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

enum VersionDialogChoice { ignore, remind, view, install }

class VersionChecker extends StatelessWidget {
  final Widget child;

  const VersionChecker({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer<VersionCheckerViewModel>(
      builder: (context, viewModel, _) {
        if (viewModel.showUpdateSuccessful) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            viewModel.showUpdateSuccessful = false;
            Toast.show(
              context,
              "Successfully updated to v${viewModel.current}!",
            );
          });
        }
        if (viewModel.newVersionAvailable && !viewModel.isOpen) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            final canAutoUpdate = AutoUpdateRepository.autoUpdatesSupported(
              systemIntegrationConfig,
            );
            final actions = [
              AdaptiveDialogAction(
                onPressed: () =>
                    Navigator.pop(context, VersionDialogChoice.ignore),
                child: const Text("Ignore"),
              ),
              AdaptiveDialogAction(
                onPressed: () =>
                    Navigator.pop(context, VersionDialogChoice.remind),
                child: const Text("Later"),
              ),
              if (canAutoUpdate)
                AdaptiveDialogAction(
                  onPressed: () =>
                      Navigator.pop(context, VersionDialogChoice.install),
                  child: const Text("Update & Restart"),
                )
              else
                AdaptiveDialogAction(
                  onPressed: () =>
                      Navigator.pop(context, VersionDialogChoice.view),
                  child: const Text("View Release"),
                ),
            ];
            viewModel.isOpen = true;
            showAdaptiveDialog<VersionDialogChoice>(
              context: context,
              barrierDismissible: true,
              builder: (context) {
                return AlertDialog.adaptive(
                  title: const Text("Update Available"),
                  content: Text(
                    "Crossonic v${viewModel.latest} is available (currently v${viewModel.current}).",
                  ),
                  actions: actions,
                );
              },
            ).then((choice) async {
              if (!context.mounted) return;
              switch (choice) {
                case VersionDialogChoice.ignore:
                  await viewModel.ignoreVersion();
                  if (context.mounted) {
                    Toast.show(
                      context,
                      "You won't be reminded about this version again",
                    );
                  }
                  break;
                case VersionDialogChoice.view:
                  launchUrl(systemIntegrationConfig.releasesUrl);
                  break;
                case null:
                case VersionDialogChoice.remind:
                  // default behavior
                  break;
                case VersionDialogChoice.install:
                  await viewModel.displayedVersionDialog();
                  if (context.mounted) {
                    final autoUpdateRepo = context.read<AutoUpdateRepository>();
                    showAdaptiveDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (dialogCtx) => _UpdateProgressDialog(
                        repository: autoUpdateRepo,
                        targetVersion: viewModel.latest!,
                      ),
                    );
                  }
                  return;
              }
              await viewModel.displayedVersionDialog();
            });
          });
        }
        return child;
      },
    );
  }
}

class _UpdateProgressDialog extends StatefulWidget {
  final AutoUpdateRepository repository;
  final Version targetVersion;

  const _UpdateProgressDialog({
    required this.repository,
    required this.targetVersion,
  });

  @override
  State<_UpdateProgressDialog> createState() => _UpdateProgressDialogState();
}

class _UpdateProgressDialogState extends State<_UpdateProgressDialog> {
  Timer? _restartTimer;

  @override
  void initState() {
    super.initState();
    widget.repository.addListener(_onRepositoryChanged);
    _startUpdate();
  }

  @override
  void dispose() {
    _restartTimer?.cancel();
    widget.repository.removeListener(_onRepositoryChanged);
    super.dispose();
  }

  void _onRepositoryChanged() {
    if (mounted) setState(() {});
    if (widget.repository.status == AutoUpdateStatus.success &&
        _restartTimer == null) {
      if (Restart.supported) {
        _restartTimer = Timer(const Duration(milliseconds: 1000), () {
          Restart.restart();
        });
      }
    }
  }

  Future<void> _startUpdate() async {
    final repo = widget.repository;
    if (repo.status == AutoUpdateStatus.downloading ||
        repo.status == AutoUpdateStatus.installing) {
      return;
    }
    final pending = await repo.prepareUpdate();
    if (pending != null && mounted) {
      await repo.update(pending);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.repository.status;
    return AlertDialog.adaptive(
      title: Text(switch (status) {
        AutoUpdateStatus.success => "Update Installed",
        AutoUpdateStatus.failure => "Update Failed",
        _ => "Updating Crossonic...",
      }),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(switch (status) {
            AutoUpdateStatus.initial ||
            AutoUpdateStatus.checkingVersion =>
              "Checking version...",
            AutoUpdateStatus.downloading =>
              "Downloading Crossonic v${widget.targetVersion}...",
            AutoUpdateStatus.installing => "Installing update...",
            AutoUpdateStatus.success => Restart.supported
                ? "Update complete! Restarting Crossonic..."
                : "Update complete! Please restart Crossonic.",
            AutoUpdateStatus.failure => "Failed to download or install update.",
          }),
          const SizedBox(height: 16),
          if (status == AutoUpdateStatus.downloading)
            StreamBuilder<double>(
              stream: widget.repository.downloadProgress,
              builder: (context, snapshot) {
                final progress = snapshot.data ?? 0.0;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(
                      value: progress > 0 ? progress : null,
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        "${(progress * 100).toInt()}%",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                );
              },
            )
          else if (status == AutoUpdateStatus.checkingVersion ||
              status == AutoUpdateStatus.installing ||
              status == AutoUpdateStatus.initial)
            const LinearProgressIndicator()
          else if (status == AutoUpdateStatus.success)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(8.0),
                child: Icon(
                  Icons.check_circle_outline,
                  size: 48,
                  color: Colors.green,
                ),
              ),
            )
          else if (status == AutoUpdateStatus.failure)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(8.0),
                child: Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Colors.red,
                ),
              ),
            ),
        ],
      ),
      actions: [
        if (status == AutoUpdateStatus.failure) ...[
          AdaptiveDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text("Dismiss"),
          ),
          AdaptiveDialogAction(
            onPressed: _startUpdate,
            child: const Text("Retry"),
          ),
        ] else if (status != AutoUpdateStatus.success) ...[
          AdaptiveDialogAction(
            onPressed: () {
              Navigator.pop(context);
              Toast.show(context, "Updating Crossonic in background...");
            },
            child: const Text("Background"),
          ),
        ] else if (!Restart.supported) ...[
          AdaptiveDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ],
    );
  }
}
