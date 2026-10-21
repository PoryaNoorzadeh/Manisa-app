import 'package:flutter/material.dart';

import 'manisa_localization.dart';

/// A direct accessory action, with the confirmed state kept visible while busy.
class OutputPowerTile extends StatelessWidget {
  const OutputPowerTile({
    required this.value,
    required this.onChanged,
    required this.title,
    required this.subtitle,
    required this.powerKey,
    this.label = '',
    this.secondary,
    this.contentPadding,
    super.key,
  });

  final bool value;
  final String label;
  final ValueChanged<bool>? onChanged;
  final Widget title;
  final Widget subtitle;
  final Widget? secondary;
  final EdgeInsetsGeometry? contentPadding;
  final Key powerKey;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: contentPadding,
    minVerticalPadding: 12,
    title: title,
    subtitle: subtitle,
    leading: Semantics(
      toggled: value,
      child: IconButton.filledTonal(
        key: powerKey,
        tooltip: '${context.tr(value ? "خاموش کردن" : "روشن کردن")} $label',
        onPressed: onChanged == null ? null : () => onChanged!(!value),
        style: IconButton.styleFrom(
          minimumSize: const Size.square(52),
          backgroundColor: value
              ? const Color(0xFFFFCF70)
              : const Color(0xFFEEF0F5),
          foregroundColor: value
              ? const Color(0xFF704400)
              : const Color(0xFF626B7C),
          disabledBackgroundColor: value
              ? const Color(0xFFFFE1A9)
              : const Color(0xFFEEF0F5),
          disabledForegroundColor: const Color(0xFF788090),
        ),
        icon: const Icon(Icons.power_settings_new_rounded, size: 27),
      ),
    ),
    trailing: secondary,
  );
}
