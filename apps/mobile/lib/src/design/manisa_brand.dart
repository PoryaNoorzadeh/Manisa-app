import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'manisa_theme.dart';

/// The approved ribbon artwork, drawn from the original brand asset.
/// The company name is native text: never the misspelled raster wordmark.
class ManisaBrand extends StatelessWidget {
  const ManisaBrand({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Manisa · مانیسا',
    image: true,
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _RibbonMark(),
          const SizedBox(width: 8),
          Text(
            Localizations.maybeLocaleOf(context)?.languageCode == 'en'
                ? 'MANISA'
                : 'مانیسا',
            style: const TextStyle(
              fontFamily: 'Vazirmatn',
              fontSize: 22,
              height: 1.5,
              fontWeight: FontWeight.w700,
              color: ManisaColors.ink,
            ),
          ),
        ],
      ),
    ),
  );
}

class _RibbonMark extends StatefulWidget {
  const _RibbonMark();
  @override
  State<_RibbonMark> createState() => _RibbonMarkState();
}

class _RibbonMarkState extends State<_RibbonMark> {
  ImageStream? _stream;
  ImageInfo? _info;
  late final ImageStreamListener _listener = ImageStreamListener((image, _) {
    if (mounted)
      setState(() {
        _info?.dispose();
        _info = image;
      });
    else {
      image.dispose();
    }
  });
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = const AssetImage('assets/brand/manisa-brand-source.png')
        .resolve(createLocalImageConfiguration(context));
    if (_stream?.key != next.key) {
      _stream?.removeListener(_listener);
      _stream = next;
      next.addListener(_listener);
    }
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _info?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 52,
    height: 26,
    child: _info == null
        ? const SizedBox()
        : CustomPaint(painter: _RibbonPainter(_info!.image)),
  );
}

class _RibbonPainter extends CustomPainter {
  _RibbonPainter(this.image);
  final ui.Image image;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.saveLayer(rect, Paint()..blendMode = BlendMode.multiply);
    canvas.drawImageRect(
      image,
      const Rect.fromLTWH(191, 184, 1074, 448),
      rect,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RibbonPainter oldDelegate) => oldDelegate.image != image;
}

/// Touch switch, illuminated touch ring, and light spill. No decorative star.
class SwitchBacklightIcon extends StatelessWidget {
  const SwitchBacklightIcon({
    this.size = 26,
    this.color = ManisaColors.teal,
    super.key,
  });
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _BacklightPainter(color)),
  );
}

class _BacklightPainter extends CustomPainter {
  const _BacklightPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(6, 4, 12, 16),
        const Radius.circular(3),
      ),
      pen,
    );
    canvas.drawCircle(
      const Offset(12, 12),
      3,
      Paint()..color = color.withValues(alpha: .12),
    );
    canvas.drawCircle(const Offset(12, 12), 3, pen);
    for (final ray in const [
      (Offset(12, 1), Offset(12, 2)),
      (Offset(12, 22), Offset(12, 23)),
      (Offset(1, 12), Offset(3, 12)),
      (Offset(21, 12), Offset(23, 12)),
      (Offset(3, 5), Offset(4, 6)),
      (Offset(20, 18), Offset(21, 19)),
      (Offset(3, 19), Offset(4, 18)),
      (Offset(20, 6), Offset(21, 5)),
    ]) {
      canvas.drawLine(ray.$1, ray.$2, pen);
    }
  }

  @override
  bool shouldRepaint(_BacklightPainter oldDelegate) =>
      oldDelegate.color != color;
}
