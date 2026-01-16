import 'dart:io';
import 'dart:typed_data';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:trans/config/app_theme.dart';

class DesktopCropWrapper extends StatefulWidget {
  final File imageFile;

  const DesktopCropWrapper({
    super.key,
    required this.imageFile,
  });

  @override
  State<DesktopCropWrapper> createState() => _DesktopCropWrapperState();
}

class _DesktopCropWrapperState extends State<DesktopCropWrapper> {
  final _cropController = CropController();
  bool _isCropping = false;
  Uint8List? _imageData;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final bytes = await widget.imageFile.readAsBytes();
    setState(() {
      _imageData = bytes;
    });
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
        title: const Text("Crop Ticket"),
        backgroundColor: colors.navBarBg,
        foregroundColor: colors.textPrimary,
        actions: [
          IconButton(
            onPressed: _isCropping ? null : _onCrop,
            icon: _isCropping 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
              : const Icon(Icons.check),
            tooltip: "Apply Crop",
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
                onCropped: (image) {
                  // image is Uint8List (PNG/JPEG)
                  Navigator.pop(context, image);
                },
                aspectRatio: null, // Free crop
                baseColor: colors.scaffoldBg,
                maskColor: Colors.black.withOpacity(0.5),
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
