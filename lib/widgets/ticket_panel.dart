import 'dart:io';
import '../l10n/app_localizations.dart';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:trans/services/supabase_service.dart';
import 'package:trans/config/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image/image.dart' as img;
import 'package:zxing_lib/zxing.dart' as zxing;
import 'package:zxing_lib/common.dart' as zxing;
import 'package:trans/widgets/manual_crop_wrapper.dart';

class TicketPanel extends StatefulWidget {
  const TicketPanel({super.key});

  @override
  State<TicketPanel> createState() => _TicketPanelState();
}

class _TicketPanelState extends State<TicketPanel> {
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  File? _mobileFile;
  Uint8List? _webBytes;
  bool _showGeneratedQr = true;
  Uint8List? _styledQrBytes;
  int? _styledQrColorArgb;
  bool _isGeneratingStyledQr = false;
  Rect? _detectedQrBox;

  List<dynamic> _history = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initTicket();
  }

  void _toggleSheet() {
    if (_sheetController.size < 0.2) {
      _sheetController.animateTo(0.85,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      _sheetController.animateTo(0.1,
          duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
    }
  }

  Future<void> _initTicket() async {
    await _refreshHistory();
    _syncFromCloud();
  }

  Future<void> _refreshHistory() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final savedData = prefs.getString('saved_ticket_base64');
      if (savedData != null) {
        setState(() {
          _webBytes = base64Decode(savedData);
          _styledQrBytes = null;
          _styledQrColorArgb = null;
          _isGeneratingStyledQr = false;
          _detectedQrBox = null;
        });
      }
    } else {
      // MOBILE ONLY
      try {
        final directory = await getApplicationDocumentsDirectory();
        final files = directory
            .listSync()
            .whereType<File>()
            .where((f) => f.path.contains('ticket_') && f.path.endsWith('.jpg'))
            .toList();
        files.sort(
            (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

        if (mounted) {
          setState(() {
            _history = files;
            if (files.isNotEmpty) _mobileFile = files.first;
            _styledQrBytes = null;
            _styledQrColorArgb = null;
            _isGeneratingStyledQr = false;
            _detectedQrBox = null;
          });
        }
      } catch (e) {
        debugPrint("Local Storage Error: $e");
      }
    }
  }

  Future<void> _syncFromCloud() async {
    try {
      final url = await SupabaseService.getTicketUrl();
      if (url != null && url.isNotEmpty) {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          if (kIsWeb) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(
                'saved_ticket_base64', base64Encode(response.bodyBytes));
            setState(() {
              _webBytes = response.bodyBytes;
              _styledQrBytes = null;
              _styledQrColorArgb = null;
              _isGeneratingStyledQr = false;
              _detectedQrBox = null;
            });
          } else {
            final directory = await getApplicationDocumentsDirectory();
            final backupFile =
                File('${directory.path}/ticket_cloud_backup.jpg');
            await backupFile.writeAsBytes(response.bodyBytes);
            await _refreshHistory();
          }
        }
      }
    } catch (e) {
      debugPrint("Cloud sync failed: $e");
    }
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    // Use constraints defensively ONLY on Web when running on a mobile device to prevent OOM
    // on iOS Safari and to significantly reduce synchronous JS execution time when parsing millions
    // of pixels into a Dart List<int>. We keep high res for native mobile and desktop where memory
    // and processing power allow.
    final bool isMobileWeb = kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);

    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: isMobileWeb ? 800 : null,
      maxHeight: isMobileWeb ? 800 : null,
      imageQuality: isMobileWeb ? 85 : 100,
    );

    if (image == null) return;

    if (kIsWeb) {
      final bytes = await image.readAsBytes();
      await _processPick(bytes, isWeb: true, xFile: image);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final bytes = await File(image.path).readAsBytes();
      await _processPick(bytes, isWeb: false, path: image.path);
    } catch (e) {
      _handleError(e);
    }
  }

  Future<void> _processPick(Uint8List bytes,
      {required bool isWeb, String? path, XFile? xFile}) async {
    setState(() => _isLoading = true);

    try {
      File? originalFile = !isWeb && path != null ? File(path) : null;
      File? processedFile;
      Uint8List? processedBytes;
      final detection = await _detectQrInBytes(
        bytes,
        sourcePath: path,
        allowMlKit: !isWeb,
      );
      final qrBox = detection.$1;

      // Auto-crop if found
      if (qrBox != null) {
        if (isWeb) {
          processedBytes = await _autoCropImageBytes(bytes, qrBox);
        } else if (originalFile != null) {
          processedFile = await _autoCropImage(originalFile, qrBox);
        }
      }

      if (mounted) setState(() => _isLoading = false);

      if (processedFile != null || processedBytes != null) {
        // 2. Auto-Crop Successful -> Confirm
        final confirmed = await _showCropConfirmation(
            file: processedFile, bytes: processedBytes, isAutoCrop: true);

        if (confirmed == true) {
          await _processAndUpload(processedFile ?? File(''),
              isWebFile: xFile,
              directBytes: processedBytes,
              detectedQrBox: null);
        } else if (confirmed == false) {
          await _triggerManualCrop(originalFile, bytes: bytes);
        }
      } else {
        // 3. No QR Found -> Confirm Original
        final confirmed = await _showCropConfirmation(
            file: originalFile, bytes: bytes, isAutoCrop: false);

        if (confirmed == true) {
          await _processAndUpload(originalFile ?? File(''),
              isWebFile: xFile,
              directBytes: isWeb ? bytes : null,
              detectedQrBox: qrBox);
        } else if (confirmed == false) {
          await _triggerManualCrop(originalFile, bytes: bytes);
        }
      }
    } catch (e) {
      _handleError(e);
    }
  }

  Future<void> _triggerManualCrop(File? imageFile, {Uint8List? bytes}) async {
    // Desktop, Web, or Android Manual Crop
    if (kIsWeb ||
        Platform.isAndroid ||
        !(Platform.isAndroid || Platform.isIOS)) {
      final result = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(
            builder: (_) =>
                ManualCropWrapper(imageFile: imageFile, imageBytes: bytes)),
      );

      if (result != null) {
        await _processAndUpload(imageFile ?? File(''), directBytes: result);
      } else {
        setState(() => _isLoading = false);
      }
      return;
    }

    // Mobile Manual Crop
    if (imageFile == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: imageFile.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: AppLocalizations.of(context)!.cropTicket,
            toolbarColor: TransColors.of(context).navBarBg,
            toolbarWidgetColor: TransColors.of(context).textPrimary,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
          ),
          IOSUiSettings(
            title: AppLocalizations.of(context)!.cropTicket,
          ),
        ],
      );

      if (croppedFile != null) {
        await _processAndUpload(File(croppedFile.path));
      } else {
        setState(() => _isLoading = false); // Cancelled
      }
    } catch (e) {
      _handleError(e);
    }
  }

  Future<Uint8List?> _autoCropImageBytes(Uint8List bytes, Rect box) async {
    try {
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      // Add some padding
      const padding = 20;
      int x = (box.left - padding).toInt().clamp(0, image.width);
      int y = (box.top - padding).toInt().clamp(0, image.height);
      int w = (box.width + (padding * 2)).toInt();
      int h = (box.height + (padding * 2)).toInt();

      if (x + w > image.width) w = image.width - x;
      if (y + h > image.height) h = image.height - y;

      final cropped = img.copyCrop(image, x: x, y: y, width: w, height: h);
      return Uint8List.fromList(img.encodeJpg(cropped));
    } catch (e) {
      debugPrint("Auto-crop bytes error: $e");
      return null;
    }
  }

  Future<File?> _autoCropImage(File file, Rect box) async {
    try {
      final bytes = await file.readAsBytes();
      final jpg = await _autoCropImageBytes(bytes, box);
      if (jpg == null) return null;

      final dir = await getTemporaryDirectory();
      final targetPath =
          '${dir.path}/auto_crop_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final targetFile = File(targetPath);
      await targetFile.writeAsBytes(jpg);

      return targetFile;
    } catch (e) {
      debugPrint("Auto-crop error: $e");
      return null;
    }
  }

  Future<bool?> _showCropConfirmation(
      {File? file, Uint8List? bytes, required bool isAutoCrop}) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(isAutoCrop
            ? AppLocalizations.of(context)!.qrCodeDetected
            : AppLocalizations.of(context)!.confirmTicket),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(isAutoCrop
                ? AppLocalizations.of(context)!.detectedQrUseCrop
                : AppLocalizations.of(context)!.noQrUseImage),
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: bytes != null
                  ? Image.memory(bytes)
                  : (file != null ? Image.file(file) : const SizedBox.shrink()),
            )
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false), // No -> Manual Crop
            child: Text(isAutoCrop
                ? AppLocalizations.of(context)!.editCrop
                : AppLocalizations.of(context)!.cropEdit),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true), // Yes -> Use it
            child: Text(AppLocalizations.of(context)!.useImage),
          ),
        ],
      ),
    );
  }

  Future<void> _processAndUpload(File file,
      {XFile? isWebFile, Uint8List? directBytes, Rect? detectedQrBox}) async {
    setState(() => _isLoading = true);
    try {
      Uint8List bytes;
      if (directBytes != null) {
        bytes = directBytes;
      } else if (kIsWeb && isWebFile != null) {
        bytes = await isWebFile.readAsBytes();
      } else {
        // Compress if on Mobile/Mac
        Uint8List? compressed;
        if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
          try {
            compressed = await FlutterImageCompress.compressWithFile(
              file.path,
              minWidth: 800,
              minHeight: 800,
              quality: 85,
              format: CompressFormat.jpeg,
            );
          } catch (_) {}
        }
        bytes = compressed ?? await file.readAsBytes();
      }

      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_ticket_base64', base64Encode(bytes));
        setState(() {
          _webBytes = bytes;
          _styledQrBytes = null;
          _styledQrColorArgb = null;
          _isGeneratingStyledQr = false;
          _detectedQrBox = detectedQrBox;
        });
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final localPath = '${directory.path}/ticket_$timestamp.jpg';
        final localFile = File(localPath);
        await localFile.writeAsBytes(bytes);

        await _refreshHistory();
        setState(() {
          _mobileFile = localFile;
          _styledQrBytes = null;
          _styledQrColorArgb = null;
          _isGeneratingStyledQr = false;
          _detectedQrBox = detectedQrBox;
        });
      }

      await SupabaseService.uploadTicketBytes(bytes, 'jpg');

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      _handleError(e);
    }
  }

  void _handleError(dynamic e) {
    if (mounted) {
      setState(() => _isLoading = false);
      String msg = e.toString();
      if (msg.contains("Bucket")) {
        msg = AppLocalizations.of(context)!.savedLocallyCloudUploadFailed;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _openFullScreen(ImageProvider imageProvider) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          color: Colors.black.withValues(alpha: 0.9),
          child: Center(
            child: Image(
              image: imageProvider,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        ),
      ),
    );
  }

  // --- Mobile Management ---
  void _renameFile(File file) async {
    final controller = TextEditingController();
    final newName = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(AppLocalizations.of(context)!.renameTicket),
              content: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                      hintText: AppLocalizations.of(context)!.enterLabel)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(AppLocalizations.of(context)!.cancel)),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, controller.text),
                    child: Text(AppLocalizations.of(context)!.save)),
              ],
            ));

    if (newName != null && newName.isNotEmpty) {
      final dir = file.parent.path;
      final newPath = '$dir/ticket_${newName.replaceAll(" ", "_")}.jpg';
      await file.rename(newPath);
      _refreshHistory();
      if (mounted) Navigator.pop(context);
    }
  }

  void _deleteFile(File file) async {
    await file.delete();
    await _refreshHistory();
    // If deleted the active one, refresh active
    if (_mobileFile?.path == file.path) {
      setState(() => _mobileFile = _history.isNotEmpty ? _history.first : null);
    }
    if (mounted) Navigator.pop(context);
  }

  void _showHistorySheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        height: 400,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(context)!.ticketHistory,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Expanded(
              child: _history.isEmpty
                  ? Center(
                      child: Text(AppLocalizations.of(context)!.noHistoryFound))
                  : ListView.separated(
                      itemCount: _history.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (ctx, idx) {
                        final file = _history[idx] as File;
                        String name = file.path
                            .split('/')
                            .last
                            .replaceAll('ticket_', '')
                            .replaceAll('.jpg', '');
                        if (int.tryParse(name) != null) {
                          final date = DateTime.fromMillisecondsSinceEpoch(
                              int.parse(name));
                          name =
                              DateFormat('MMM dd, yyyy - HH:mm').format(date);
                        } else {
                          name = name.replaceAll('_', ' ');
                        }

                        return ListTile(
                          leading: Image.file(file,
                              width: 40, height: 40, fit: BoxFit.cover),
                          title: Text(name),
                          onTap: () {
                            setState(() {
                              _mobileFile = file;
                              _styledQrBytes = null;
                              _styledQrColorArgb = null;
                              _isGeneratingStyledQr = false;
                              _detectedQrBox = null;
                            });
                            Navigator.pop(ctx);
                          },
                          trailing: PopupMenuButton(
                            onSelected: (value) {
                              if (value == 'rename') _renameFile(file);
                              if (value == 'delete') _deleteFile(file);
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                  value: 'rename',
                                  child: Text(
                                      AppLocalizations.of(context)!.rename)),
                              PopupMenuItem(
                                  value: 'delete',
                                  child: Text(
                                      AppLocalizations.of(context)!.delete,
                                      style:
                                          const TextStyle(color: Colors.red))),
                            ],
                          ),
                        );
                      },
                    ),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);

    ImageProvider? imageToShow;
    if (kIsWeb && _webBytes != null) {
      imageToShow = MemoryImage(_webBytes!);
    } else if (!kIsWeb && _mobileFile != null) {
      imageToShow = FileImage(_mobileFile!);
    }

    final bool showGeneratedQr =
        imageToShow != null && _showGeneratedQr && _styledQrBytes != null;

    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.1,
      minChildSize: 0.1,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.ticketSheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, -4))
            ],
          ),
          child: ListView(
            controller: scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            children: [
              GestureDetector(
                onTap: _toggleSheet,
                behavior: HitTestBehavior.opaque,
                child: Column(
                  children: [
                    Center(
                        child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                                color: colors.modalHandle,
                                borderRadius: BorderRadius.circular(2)))),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.confirmation_number_outlined,
                            color: colors.ticketHeader),
                        const SizedBox(width: 8),
                        Text(AppLocalizations.of(context)!.myTicket,
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: colors.ticketHeader)),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              if (_isLoading)
                Container(
                    height: 300,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator())
              else if (imageToShow != null)
                Column(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        if (showGeneratedQr)
                          _buildStyledQr(colors)
                        else
                          GestureDetector(
                            onTap: () => _openFullScreen(imageToShow!),
                            onLongPress: kIsWeb ? null : _showHistorySheet,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image(
                                image: imageToShow,
                                fit: BoxFit.contain,
                                errorBuilder: (c, e, s) => Container(
                                    height: 200,
                                    alignment: Alignment.center,
                                    child: Text(AppLocalizations.of(context)!
                                        .errorLoadingTicket)),
                              ),
                            ),
                          ),
                        if (_isGeneratingStyledQr)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 12),
                                    Text(AppLocalizations.of(context)!
                                        .generatingStyledQr,
                                        style: TextStyle(color: Colors.white)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                        showGeneratedQr
                            ? AppLocalizations.of(context)!
                                .styledFromOriginalTicketQrPattern
                            : (kIsWeb
                                ? AppLocalizations.of(context)!.tapForFullscreen
                                : AppLocalizations.of(context)!
                                    .tapForFullscreenHoldForHistory),
                        style:
                            const TextStyle(fontSize: 10, color: Colors.grey)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: colors.textPrimary,
                            side: BorderSide(color: colors.divider),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12))),
                        onPressed: _isGeneratingStyledQr
                            ? null
                            : () async {
                                if (showGeneratedQr) {
                                  if (mounted) {
                                    setState(() => _showGeneratedQr = false);
                                  }
                                  return;
                                }

                                if (mounted) {
                                  setState(() => _isGeneratingStyledQr = true);
                                }
                                await Future<void>.delayed(
                                    const Duration(milliseconds: 16));

                                bool available = false;
                                try {
                                  available =
                                      await _ensureStyledQrForCurrentTicket(
                                    colors.effectiveSeed,
                                  );
                                } finally {
                                  if (mounted) {
                                    setState(
                                        () => _isGeneratingStyledQr = false);
                                  }
                                }
                                if (!available) return;

                                if (mounted) {
                                  setState(() => _showGeneratedQr = true);
                                }
                              },
                        icon: Icon(showGeneratedQr
                            ? Icons.image_outlined
                            : Icons.qr_code_2_outlined),
                        label: Text(showGeneratedQr
                            ? AppLocalizations.of(context)!.showOriginalTicket
                            : AppLocalizations.of(context)!.showStyledQr),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: colors.textPrimary,
                            side: BorderSide(color: colors.divider),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12))),
                        onPressed: _pickAndUploadImage,
                        icon: const Icon(Icons.edit),
                        label: Text(AppLocalizations.of(context)!.changeTicket),
                      ),
                    )
                  ],
                )
              else
                GestureDetector(
                  onTap: _pickAndUploadImage,
                  child: Container(
                    height: 220,
                    decoration: BoxDecoration(
                      color:
                          colors.isDark ? Colors.white10 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: colors.ticketBorder, width: 2),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                                color: colors.scaffoldBg,
                                shape: BoxShape.circle),
                            child: Icon(Icons.add_a_photo_rounded,
                                size: 32, color: colors.textSecondary)),
                        const SizedBox(height: 16),
                        Text(AppLocalizations.of(context)!.addTicket,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: colors.textPrimary)),
                        const SizedBox(height: 4),
                        Text(
                            AppLocalizations.of(context)!
                                .selectImageFromGallery,
                            style: TextStyle(
                                fontSize: 12, color: colors.textSecondary)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStyledQr(TransColors colors) {
    final styled = _styledQrBytes;
    if (styled == null) return const SizedBox.shrink();
    final qrBg = colors.isDark ? const Color(0xFF0F1115) : Colors.white;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: qrBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.divider),
      ),
      child: AspectRatio(
        aspectRatio: 1,
        child: Center(
          child: Image.memory(
            styled,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.none,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }

  Future<bool> _ensureStyledQrForCurrentTicket(Color themeColor) async {
    final themeArgb = themeColor.toARGB32();
    if (_styledQrBytes != null && _styledQrColorArgb == themeArgb) {
      return true;
    }

    Uint8List? bytes;
    String? path;

    if (kIsWeb) {
      bytes = _webBytes;
    } else if (_mobileFile != null) {
      path = _mobileFile!.path;
      bytes = await _mobileFile!.readAsBytes();
    }

    if (bytes == null) return false;

    Rect? qrBox = _detectedQrBox;
    if (qrBox == null && !kIsWeb) {
      final detection = await _detectQrInBytes(
        bytes,
        sourcePath: path,
        allowMlKit: !kIsWeb,
      );
      qrBox = detection.$1;
      if (mounted && qrBox != null) {
        setState(() => _detectedQrBox = qrBox);
      }
    }

    if (qrBox == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(AppLocalizations.of(context)!.couldNotIsolateQrBounds)));
    }

    final styled = await _styleQrBytesInBackground(bytes, qrBox, themeArgb);

    if (mounted) {
      setState(() {
        _styledQrBytes = styled;
        _styledQrColorArgb = themeArgb;
      });
    }

    if (styled == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!.couldNotRecolorQrCode)));
      }
      return false;
    }

    return true;
  }

  Future<Uint8List?> _styleQrBytesInBackground(
      Uint8List sourceBytes, Rect? box, int themeArgb) async {
    try {
      if (kIsWeb) {
        return await _styleQrBytesChunkedWeb(sourceBytes, box, themeArgb);
      }
      return await compute(_styleQrBytesIsolate, <String, dynamic>{
        'bytes': sourceBytes,
        'left': box?.left,
        'top': box?.top,
        'width': box?.width,
        'height': box?.height,
        'themeArgb': themeArgb,
      });
    } catch (e) {
      debugPrint("QR recolor isolate failed: $e");
      return null;
    }
  }

  Future<Uint8List?> _styleQrBytesChunkedWeb(
      Uint8List sourceBytes, Rect? box, int themeArgb) async {
    try {
      var image = img.decodeImage(sourceBytes);
      if (image == null) return null;
      image = img.bakeOrientation(image);

      if (box != null) {
        const padding = 6;
        int x = (box.left - padding).floor();
        int y = (box.top - padding).floor();
        int w = (box.width + (padding * 2)).ceil();
        int h = (box.height + (padding * 2)).ceil();

        x = x.clamp(0, image.width - 1).toInt();
        y = y.clamp(0, image.height - 1).toInt();
        if (x + w > image.width) w = image.width - x;
        if (y + h > image.height) h = image.height - y;
        if (w >= 32 && h >= 32) {
          image = img.copyCrop(image, x: x, y: y, width: w, height: h);
        }
      }
      if (image.numChannels != 4) {
        image = image.convert(numChannels: 4);
      }

      final rT = (themeArgb >> 16) & 0xFF;
      final gT = (themeArgb >> 8) & 0xFF;
      final bT = themeArgb & 0xFF;
      const threshold = 150;

      for (int py = 0; py < image.height; py++) {
        for (int px = 0; px < image.width; px++) {
          final p = image.getPixel(px, py);
          final a = p.a.toInt();
          if (a < 20) {
            image.setPixelRgba(px, py, 0, 0, 0, 0);
            continue;
          }

          final r = p.r.toInt();
          final g = p.g.toInt();
          final b = p.b.toInt();
          final luminance = ((299 * r) + (587 * g) + (114 * b)) ~/ 1000;

          if (luminance < threshold) {
            image.setPixelRgba(px, py, rT, gT, bT, 255);
          } else {
            image.setPixelRgba(px, py, 0, 0, 0, 0);
          }
        }
        if (py % 16 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      final squared = await _trimAndSquareQrImageChunked(image);
      return Uint8List.fromList(img.encodePng(squared, level: 3));
    } catch (e) {
      debugPrint("QR recolor web failed: $e");
      return null;
    }
  }

  Future<img.Image> _trimAndSquareQrImageChunked(img.Image image) async {
    int minX = image.width;
    int minY = image.height;
    int maxX = -1;
    int maxY = -1;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final a = image.getPixel(x, y).a.toInt();
        if (a > 20) {
          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
        }
      }
      if (y % 24 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    if (maxX < minX || maxY < minY) return image;

    final contentW = maxX - minX + 1;
    final contentH = maxY - minY + 1;
    int side = math.max(contentW, contentH);

    final cx = (minX + maxX) / 2.0;
    final cy = (minY + maxY) / 2.0;

    int x = (cx - side / 2).floor();
    int y = (cy - side / 2).floor();

    if (side > image.width) side = image.width;
    if (side > image.height) side = image.height;

    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if (x + side > image.width) x = image.width - side;
    if (y + side > image.height) y = image.height - side;

    x = x.clamp(0, image.width - 1).toInt();
    y = y.clamp(0, image.height - 1).toInt();

    return img.copyCrop(image, x: x, y: y, width: side, height: side);
  }

  Future<(Rect?, String?)> _detectQrInBytes(
    Uint8List bytes, {
    String? sourcePath,
    required bool allowMlKit,
  }) async {
    Rect? qrBox;
    String? qrPayload;

    // Try ML Kit first on mobile platforms.
    if (allowMlKit &&
        sourcePath != null &&
        !kIsWeb &&
        (Platform.isAndroid || Platform.isIOS)) {
      try {
        final inputImage = InputImage.fromFilePath(sourcePath);
        final barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);
        final barcodes = await barcodeScanner.processImage(inputImage);
        debugPrint("ML Kit found ${barcodes.length} barcodes");

        if (barcodes.isNotEmpty) {
          // Prefer the largest QR in frame (ticket images can include extra tiny codes).
          final best = barcodes.reduce((a, b) {
            final aArea = (a.boundingBox.width * a.boundingBox.height).abs();
            final bArea = (b.boundingBox.width * b.boundingBox.height).abs();
            return aArea >= bArea ? a : b;
          });
          qrBox = best.boundingBox;
          qrPayload = best.rawValue ?? best.displayValue;
          debugPrint("ML Kit payload found: ${qrPayload != null}");
        }
        barcodeScanner.close();
      } catch (e) {
        debugPrint("ML Kit scan failed, falling back to ZXing: $e");
      }
    }

    // ZXing fallback for web/desktop or missing data.
    if (qrBox == null || qrPayload == null || qrPayload.isEmpty) {
      try {
        var image = img.decodeImage(bytes);
        if (image == null) {
          debugPrint(
              "ZXing: failed to decode image bytes (${bytes.length} bytes)");
          return (qrBox, qrPayload);
        }

        // Bake EXIF orientation into actual pixels.
        image = img.bakeOrientation(image);

        // Ensure image is 4-channel RGBA.
        if (image.numChannels != 4) {
          image = image.convert(numChannels: 4);
        }

        debugPrint(
            "ZXing: decoded image ${image.width}x${image.height} (channels: ${image.numChannels})");

        final rawPixels = image.data?.buffer.asUint32List();
        if (rawPixels == null) return (qrBox, qrPayload);

        // Convert RGBA -> ARGB expected by RGBLuminanceSource.
        final argbPixels = List<int>.generate(rawPixels.length, (i) {
          final rgba = rawPixels[i];
          final r = rgba & 0xFF;
          final g = (rgba >> 8) & 0xFF;
          final b = (rgba >> 16) & 0xFF;
          final a = (rgba >> 24) & 0xFF;
          return (a << 24) | (r << 16) | (g << 8) | b;
        });

        final luminance =
            zxing.RGBLuminanceSource(image.width, image.height, argbPixels);

        const hints = zxing.DecodeHint(
          tryHarder: true,
          alsoInverted: true,
        );

        zxing.Result? result;
        try {
          final binarizer = zxing.HybridBinarizer(luminance);
          final bitmap = zxing.BinaryBitmap(binarizer);
          result = zxing.MultiFormatReader().decode(bitmap, hints);
        } catch (_) {
          try {
            final binarizer2 = zxing.GlobalHistogramBinarizer(luminance);
            final bitmap2 = zxing.BinaryBitmap(binarizer2);
            result = zxing.MultiFormatReader().decode(bitmap2, hints);
          } catch (_) {}
        }

        if (result == null) {
          debugPrint("ZXing: no barcode found after trying both binarizers");
          return (qrBox, qrPayload);
        }

        qrPayload = result.text;
        debugPrint("ZXing: found barcode payload (${qrPayload.length} chars)");

        final points = result.resultPoints;
        if (points != null && points.isNotEmpty) {
          double minX = double.infinity, minY = double.infinity;
          double maxX = 0, maxY = 0;

          for (var p in points) {
            if ((p?.x ?? 0) < minX) minX = p!.x;
            if ((p?.y ?? 0) < minY) minY = p!.y;
            if ((p?.x ?? 0) > maxX) maxX = p!.x;
            if ((p?.y ?? 0) > maxY) maxY = p!.y;
          }
          qrBox = Rect.fromLTRB(minX, minY, maxX, maxY);
        }
      } catch (e) {
        debugPrint("ZXing scan failed: $e");
      }
    }

    return (qrBox, qrPayload);
  }
}

Uint8List? _styleQrBytesIsolate(Map<String, dynamic> payload) {
  try {
    final sourceBytes = payload['bytes'] as Uint8List;
    final leftNum = payload['left'] as num?;
    final topNum = payload['top'] as num?;
    final widthNum = payload['width'] as num?;
    final heightNum = payload['height'] as num?;
    final themeArgb = payload['themeArgb'] as int;

    var image = img.decodeImage(sourceBytes);
    if (image == null) return null;
    image = img.bakeOrientation(image);

    if (leftNum != null &&
        topNum != null &&
        widthNum != null &&
        heightNum != null) {
      const padding = 6;
      int x = (leftNum.toDouble() - padding).floor();
      int y = (topNum.toDouble() - padding).floor();
      int w = (widthNum.toDouble() + (padding * 2)).ceil();
      int h = (heightNum.toDouble() + (padding * 2)).ceil();

      x = x.clamp(0, image.width - 1).toInt();
      y = y.clamp(0, image.height - 1).toInt();
      if (x + w > image.width) w = image.width - x;
      if (y + h > image.height) h = image.height - y;
      if (w >= 32 && h >= 32) {
        image = img.copyCrop(image, x: x, y: y, width: w, height: h);
      }
    }
    if (image.numChannels != 4) {
      image = image.convert(numChannels: 4);
    }

    final rT = (themeArgb >> 16) & 0xFF;
    final gT = (themeArgb >> 8) & 0xFF;
    final bT = themeArgb & 0xFF;

    const threshold = 150;
    for (int py = 0; py < image.height; py++) {
      for (int px = 0; px < image.width; px++) {
        final p = image.getPixel(px, py);
        final a = p.a.toInt();
        if (a < 20) {
          image.setPixelRgba(px, py, 0, 0, 0, 0);
          continue;
        }

        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        final luminance = ((299 * r) + (587 * g) + (114 * b)) ~/ 1000;

        if (luminance < threshold) {
          image.setPixelRgba(px, py, rT, gT, bT, 255);
        } else {
          image.setPixelRgba(px, py, 0, 0, 0, 0);
        }
      }
    }

    final squared = _trimAndSquareQrImage(image);
    return Uint8List.fromList(img.encodePng(squared, level: 3));
  } catch (_) {
    return null;
  }
}

img.Image _trimAndSquareQrImage(img.Image image) {
  int minX = image.width;
  int minY = image.height;
  int maxX = -1;
  int maxY = -1;

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final a = image.getPixel(x, y).a.toInt();
      if (a > 20) {
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
  }

  if (maxX < minX || maxY < minY) return image;

  final contentW = maxX - minX + 1;
  final contentH = maxY - minY + 1;
  int side = math.max(contentW, contentH);

  final cx = (minX + maxX) / 2.0;
  final cy = (minY + maxY) / 2.0;

  int x = (cx - side / 2).floor();
  int y = (cy - side / 2).floor();

  if (side > image.width) side = image.width;
  if (side > image.height) side = image.height;

  if (x < 0) x = 0;
  if (y < 0) y = 0;
  if (x + side > image.width) x = image.width - side;
  if (y + side > image.height) y = image.height - side;

  x = x.clamp(0, image.width - 1).toInt();
  y = y.clamp(0, image.height - 1).toInt();

  return img.copyCrop(image, x: x, y: y, width: side, height: side);
}
