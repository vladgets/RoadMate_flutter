import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import '../../models/collage_composition.dart';
import '../../services/collage_composer.dart';

class CollagePainter extends StatefulWidget {
  final CollageComposition composition;

  const CollagePainter({
    super.key,
    required this.composition,
  });

  @override
  State<CollagePainter> createState() => _CollagePainterState();
}

class _CollagePainterState extends State<CollagePainter> {
  ui.Image? _backgroundImage;
  List<ui.Image?> _photoImages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  Future<void> _loadImages() async {
    try {
      // Load background
      final bg = await CollageComposer.instance.loadBackgroundFromUrl(
        widget.composition.backgroundUrl,
      );

      // Load photos
      final photos = <ui.Image?>[];
      for (final photo in widget.composition.photos) {
        final img = await CollageComposer.instance.loadPhotoFromAsset(photo.id);
        photos.add(img);
      }

      setState(() {
        _backgroundImage = bg;
        _photoImages = photos;
        _isLoading = false;
      });
    } catch (e) {
      // Handle error
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return CustomPaint(
      painter: _CollagePainterImpl(
        backgroundImage: _backgroundImage,
        photoImages: _photoImages,
        composition: widget.composition,
      ),
      child: Container(),
    );
  }
}

class _CollagePainterImpl extends CustomPainter {
  final ui.Image? backgroundImage;
  final List<ui.Image?> photoImages;
  final CollageComposition composition;

  _CollagePainterImpl({
    required this.backgroundImage,
    required this.photoImages,
    required this.composition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw background
    if (backgroundImage != null) {
      paintImage(
        canvas: canvas,
        rect: Rect.fromLTWH(0, 0, size.width, size.height),
        image: backgroundImage!,
        fit: BoxFit.cover,
      );
    }

    // Draw photos
    for (int i = 0; i < photoImages.length && i < composition.photoSlots.length; i++) {
      final photo = photoImages[i];
      final slot = composition.photoSlots[i];

      if (photo == null) continue;

      canvas.save();

      // Calculate actual position and size
      final x = slot.position.dx * size.width;
      final y = slot.position.dy * size.height;
      final w = slot.size.width * size.width;
      final h = slot.size.height * size.height;

      // Translate to center of photo
      canvas.translate(x + w / 2, y + h / 2);

      // Rotate
      canvas.rotate(slot.rotation);

      // Draw photo (centered)
      final rect = Rect.fromLTWH(-w / 2, -h / 2, w, h);

      // Draw shadow
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );

      // Draw photo
      paintImage(
        canvas: canvas,
        rect: rect,
        image: photo,
        fit: BoxFit.cover,
      );

      canvas.restore();
    }

    // Draw text overlays
    for (int i = 0; i < composition.memories.length && i < composition.textSlots.length; i++) {
      final memory = composition.memories[i];
      final slot = composition.textSlots[i];

      final textPainter = TextPainter(
        text: TextSpan(
          text: memory.transcription.length > 100
              ? '${memory.transcription.substring(0, 100)}...'
              : memory.transcription,
          style: TextStyle(
            color: slot.color,
            fontSize: slot.fontSize,
            fontFamily: slot.style == 'handwritten' ? 'Courier' : 'Arial',
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.5),
                offset: const Offset(1, 1),
                blurRadius: 2,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 3,
      );

      textPainter.layout(maxWidth: slot.maxWidth * size.width);
      textPainter.paint(
        canvas,
        Offset(slot.position.dx * size.width, slot.position.dy * size.height),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
