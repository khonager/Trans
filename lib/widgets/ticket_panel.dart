import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:trans/services/supabase_service.dart';
import 'package:trans/config/app_theme.dart';
import 'package:intl/intl.dart';

class TicketPanel extends StatefulWidget {
  const TicketPanel({super.key});

  @override
  State<TicketPanel> createState() => _TicketPanelState();
}

class _TicketPanelState extends State<TicketPanel> {
  // NEW: Controller to control sheet programmatically
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  
  File? _currentTicketFile;
  List<File> _localHistory = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initTicket();
  }

  // Toggle Sheet visibility (Fix for PC click)
  void _toggleSheet() {
    if (_sheetController.size < 0.2) {
      _sheetController.animateTo(
        0.85, 
        duration: const Duration(milliseconds: 300), 
        curve: Curves.easeOut
      );
    } else {
      _sheetController.animateTo(
        0.1, 
        duration: const Duration(milliseconds: 300), 
        curve: Curves.easeIn
      );
    }
  }

  Future<void> _initTicket() async {
    await _refreshHistory();
    if (_localHistory.isNotEmpty) {
      if (mounted) setState(() => _currentTicketFile = _localHistory.first);
    }
    _syncFromCloud();
  }

  Future<void> _refreshHistory() async {
    final directory = await getApplicationDocumentsDirectory();
    final files = directory.listSync()
        .whereType<File>()
        .where((f) => f.path.contains('ticket_') && f.path.endsWith('.jpg'))
        .toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    if (mounted) setState(() => _localHistory = files);
  }

  Future<void> _syncFromCloud() async {
    try {
      final url = await SupabaseService.getTicketUrl();
      if (url != null && url.isNotEmpty) {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          final directory = await getApplicationDocumentsDirectory();
          final backupFile = File('${directory.path}/ticket_cloud_backup.jpg');
          await backupFile.writeAsBytes(response.bodyBytes);
          await _refreshHistory();
        }
      }
    } catch (e) {
      debugPrint("Cloud sync failed: $e");
    }
  }

  Future<Uint8List?> _compressImage(File file) async {
    try {
      final result = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        minWidth: 540,
        minHeight: 540,
        quality: 85,
        format: CompressFormat.jpeg,
      );
      return result;
    } catch (e) {
      return null;
    }
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image == null) return;

    setState(() => _isLoading = true);
    
    try {
      final File originalFile = File(image.path);
      final Uint8List? compressedBytes = await _compressImage(originalFile);
      
      if (compressedBytes == null) throw "Image compression failed.";

      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final localPath = '${directory.path}/ticket_$timestamp.jpg';
      final localFile = File(localPath);
      await localFile.writeAsBytes(compressedBytes);
      
      await _refreshHistory();
      if (mounted) setState(() => _currentTicketFile = localFile);

      await SupabaseService.uploadTicketBytes(compressedBytes, 'jpg');

      if (mounted) setState(() => _isLoading = false);
      
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        String msg = e.toString();
        if (msg.contains("Bucket not found")) msg = "Cloud Error: Storage bucket missing.";
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Saved locally. $msg")));
      }
    }
  }

  void _openFullScreen(File file) {
    showDialog(
      context: context,
      barrierDismissible: true, 
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(context), 
        child: Container(
          color: Colors.black.withValues(alpha: 0.9),
          child: Center(
            child: Image.file(file, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  void _renameFile(File file) async {
    final controller = TextEditingController();
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Rename Ticket"),
        content: TextField(
          controller: controller, 
          decoration: const InputDecoration(hintText: "Enter label (e.g. Sept Ticket)")
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text("Save")),
        ],
      )
    );

    if (newName != null && newName.isNotEmpty) {
      final dir = file.parent.path;
      final newPath = '$dir/ticket_${newName.replaceAll(" ", "_")}.jpg';
      await file.rename(newPath);
      _refreshHistory();
      Navigator.pop(context); 
    }
  }

  void _deleteFile(File file) async {
    await file.delete();
    _refreshHistory();
    if (_currentTicketFile?.path == file.path) {
      setState(() => _currentTicketFile = _localHistory.isNotEmpty ? _localHistory.first : null);
    }
    Navigator.pop(context); 
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
            const Text("Ticket History", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Expanded(
              child: _localHistory.isEmpty 
                ? const Center(child: Text("No history found.")) 
                : ListView.separated(
                    itemCount: _localHistory.length,
                    separatorBuilder: (_,__) => const Divider(),
                    itemBuilder: (ctx, idx) {
                      final file = _localHistory[idx];
                      String name = file.path.split('/').last.replaceAll('ticket_', '').replaceAll('.jpg', '');
                      if (int.tryParse(name) != null) {
                         final date = DateTime.fromMillisecondsSinceEpoch(int.parse(name));
                         name = DateFormat('MMM dd, yyyy - HH:mm').format(date);
                      } else {
                         name = name.replaceAll('_', ' ');
                      }

                      return ListTile(
                        leading: Image.file(file, width: 40, height: 40, fit: BoxFit.cover),
                        title: Text(name),
                        onTap: () {
                          setState(() => _currentTicketFile = file);
                          Navigator.pop(ctx);
                        },
                        trailing: PopupMenuButton(
                          onSelected: (value) {
                            if (value == 'rename') _renameFile(file);
                            if (value == 'delete') _deleteFile(file);
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: 'rename', child: Text("Rename")),
                            const PopupMenuItem(value: 'delete', child: Text("Delete", style: TextStyle(color: Colors.red))),
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

    return DraggableScrollableSheet(
      controller: _sheetController, // NEW: Attached Controller
      initialChildSize: 0.1,
      minChildSize: 0.1,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.ticketSheetBg, 
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, -4))
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            children: [
              // HEADER AREA (Now Clickable)
              GestureDetector(
                onTap: _toggleSheet, // Click to expand/collapse
                behavior: HitTestBehavior.opaque, // Catch clicks anywhere in this area
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 40, 
                        height: 4, 
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(color: colors.modalHandle, borderRadius: BorderRadius.circular(2))
                      )
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.confirmation_number_outlined, color: colors.ticketHeader),
                        const SizedBox(width: 8),
                        Text(
                          "My Ticket", 
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colors.ticketHeader)
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              
              if (_isLoading)
                Container(height: 300, alignment: Alignment.center, child: const CircularProgressIndicator())
              else if (_currentTicketFile != null)
                Column(
                  children: [
                    GestureDetector(
                      onTap: () => _openFullScreen(_currentTicketFile!), 
                      onLongPress: _showHistorySheet, 
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(
                          _currentTicketFile!,
                          fit: BoxFit.contain,
                          key: ValueKey(_currentTicketFile!.path),
                          errorBuilder: (context, error, stackTrace) => 
                            Container(height: 200, alignment: Alignment.center, child: const Text("Error loading ticket file")),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text("Tap for fullscreen • Hold for history", style: TextStyle(fontSize: 10, color: Colors.grey)),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.textPrimary,
                          side: BorderSide(color: colors.divider),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                        ),
                        onPressed: _pickAndUploadImage,
                        icon: const Icon(Icons.edit),
                        label: const Text("Change Ticket"),
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
                      color: colors.isDark ? Colors.white10 : Colors.grey.shade100,
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
                            shape: BoxShape.circle
                          ),
                          child: Icon(Icons.add_a_photo_rounded, size: 32, color: colors.textSecondary)
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Add Ticket", 
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colors.textPrimary)
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Select image from gallery", 
                          style: TextStyle(fontSize: 12, color: colors.textSecondary)
                        ),
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
}