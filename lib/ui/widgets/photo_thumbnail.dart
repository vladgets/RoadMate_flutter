import 'dart:io';
import 'package:flutter/material.dart';

/// A reusable thumbnail widget for displaying photos
class PhotoThumbnail extends Widget {
  final String path;
  final VoidCallback? onTap;
  final double size;

  const PhotoThumbnail({
    super.key,
    required this.path,
    this.onTap,
    this.size = 120,
  });

  @override
  Element createElement() => _PhotoThumbnailElement(this);
}

class _PhotoThumbnailElement extends ComponentElement {
  _PhotoThumbnailElement(PhotoThumbnail super.widget);

  @override
  PhotoThumbnail get widget => super.widget as PhotoThumbnail;

  @override
  Widget build() {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: widget.size,
        height: widget.size,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey[300],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: _buildImage(),
        ),
      ),
    );
  }

  Widget _buildImage() {
    final file = File(widget.path);

    if (!file.existsSync()) {
      return const Center(
        child: Icon(Icons.broken_image, color: Colors.grey),
      );
    }

    return Image.file(
      file,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return const Center(
          child: Icon(Icons.broken_image, color: Colors.grey),
        );
      },
    );
  }
}
