import 'dart:io';
import '../l10n/app_localizations.dart';
import 'dart:typed_data';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:trans/config/app_theme.dart';

class ManualCropWrapper extends StatefulWidget {
  final File? imageFile;
  final Uint8List? imageBytes;

  const ManualCropWrapper({
    super.key,
    this.imageFile,
    this.imageBytes,
  });

  @override
  State<ManualCropWrapper> createState() => _ManualCropWrapperState();
}

class _ManualCropWrapperState extends State<ManualCropWrapper> {
  final _cropController = CropController();
  bool _isCropping = false;
  Uint8List? _imageData;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    if (widget.imageBytes != null) {
      setState(() {
        _imageData = widget.imageBytes;
      });
      return;
    }

    if (widget.imageFile != null) {
      final bytes = await widget.imageFile!.readAsBytes();
      setState(() {
        _imageData = bytes;
      });
    }
  }

  void _onCrop() {
    setState(() => _isCropping = true);
    _cropController.crop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);

    return Scaffold(
      backgroundColor: colors.scaffoldBg,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.cropTicket),
        backgroundColor: colors.navBarBg,
        foregroundColor: colors.textPrimary,
        actions: [
          IconButton(
            onPressed: _isCropping ? null : _onCrop,
            icon: _isCropping
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            tooltip: AppLocalizations.of(context)!.applyCrop,
          ),
        ],
      ),
      body: _imageData == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20.0),
              child: Crop(
                image: _imageData!,
                controller: _cropController,
                onCropped: (result) {
                  switch (result) {
                    case CropSuccess(:final croppedImage):
                      Navigator.pop(context, croppedImage);
                    case CropFailure(:final cause):
                      debugPrint("Crop failed: $cause");
                      Navigator.pop(context);
                  }
                },
                aspectRatio: null, // Free crop
                baseColor: colors.scaffoldBg,
                maskColor: Colors.black.withValues(alpha: 0.5),
                radius: 0,
                cornerDotBuilder: (size, edgeAlignment) =>
                    const DotControl(color: Colors.blueAccent),
                interactive: true,
                fixCropRect: false,
              ),
            ),
    );
  }
}
