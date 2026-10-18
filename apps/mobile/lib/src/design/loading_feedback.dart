import 'package:flutter/material.dart';

import 'manisa_localization.dart';

/// Explain what is loading; do not invent a percentage or replace saved data.
final class LoadingNotice extends StatelessWidget {
  const LoadingNotice({required this.label, super.key});
  final String label;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Semantics(
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(),
            ),
            const SizedBox(height: 16),
            AppText(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}

/// A stable refresh action: feedback never hides or blocks existing controls.
final class RefreshAction extends StatelessWidget {
  const RefreshAction({
    required this.refreshing,
    required this.onRefresh,
    required this.progressKey,
    super.key,
  });
  final bool refreshing;
  final Future<void> Function()? onRefresh;
  final Key progressKey;
  @override
  Widget build(BuildContext context) => Semantics(
    value: refreshing ? context.tr('در حال تازه‌سازی') : null,
    liveRegion: refreshing,
    child: IconButton(
      tooltip: context.tr('بررسی وضعیت'),
      onPressed: refreshing || onRefresh == null
          ? null
          : () {
              onRefresh!();
            },
      icon: refreshing
          ? Icon(Icons.sync_rounded, key: progressKey)
          : const Icon(Icons.refresh),
    ),
  );
}
