import 'dart:io'; 
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart'; 
import '../services/supabase_service.dart';
import '../config/app_theme.dart';

class TicketPanel extends StatefulWidget {
  const TicketPanel({super.key});

  @override
  State<TicketPanel> createState() => _TicketPanelState();
}

class _TicketPanelState extends State<TicketPanel> {
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  
  String? _localTicketPath; 
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadLocalTicket();
    _syncTicketFromCloud();
  }

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  void _toggleSheet() {
    if (_sheetController.size > 0.3) {
      _sheetController.animateTo(0.08, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      _sheetController.animateTo(0.85, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  Future<void> _loadLocalTicket() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('local_ticket_path');
    if (path != null) {
      if (kIsWeb) {
        setState(() => _localTicketPath = path);
      } else {
        if (await File(path).exists()) {
          setState(() => _localTicketPath = path);
        }
      }
    }
  }

  Future<String> _getLocalHistoryDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final historyDir = Directory('${dir.path}/ticket_history');
    if (!await historyDir.exists()) {
      await historyDir.create(recursive: true);
    }
    return historyDir.path;
  }

  Future<void> _saveToHistory(File file) async {
    if (kIsWeb) return; 
    try {
      final historyPath = await _getLocalHistoryDir();
      final filename = 'hist_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await file.copy('$historyPath/$filename');
    } catch (e) {
      print("Error saving to local history: $e");
    }
  }

  Future<List<File>> _getLocalHistoryFiles() async {
    if (kIsWeb) return [];
    try {
      final historyPath = await _getLocalHistoryDir();
      final dir = Directory(historyPath);
      final List<File> files = dir.listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.jpg'))
          .toList();
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      return files;
    } catch (e) {
      return [];
    }
  }

  Future<void> _renameHistoryItem(File file, String currentName, Function refreshCallback) async {
    final colors = TransColors.of(context);
    final nameCtrl = TextEditingController(text: currentName.replaceAll(".jpg", "").replaceAll("hist_", "Ticket "));
    final newName = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(backgroundColor: colors.cardBg, title: Text("Rename Ticket", style: TextStyle(color: colors.textPrimary)), content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "New Name")), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")), ElevatedButton(onPressed: () => Navigator.pop(ctx, nameCtrl.text), child: const Text("Rename"))]));
    if (newName != null && newName.isNotEmpty) {
      try {
        final dir = file.parent;
        final newPath = '${dir.path}/$newName.jpg';
        if (await File(newPath).exists()) { if (mounted) { await showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: colors.cardBg, title: const Text("Name Unavailable"), content: const Text("A ticket with this name already exists."), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))])); } return; }
        await file.rename(newPath);
        refreshCallback();
      } catch (e) { print("Rename error: $e"); }
    }
  }

  Future<void> _syncTicketFromCloud() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    final remoteUrl = await SupabaseService.getTicketUrl();
    final prefs = await SharedPreferences.getInstance();
    final lastUrl = prefs.getString('remote_ticket_url');
    if (remoteUrl != null) {
      if (kIsWeb) { await prefs.setString('local_ticket_path', remoteUrl); setState(() => _localTicketPath = remoteUrl); return; }
      if (remoteUrl != lastUrl) {
        try {
          final response = await http.get(Uri.parse(remoteUrl));
          if (response.statusCode == 200) {
            final dir = await getApplicationDocumentsDirectory();
            final filename = 'ticket_${DateTime.now().millisecondsSinceEpoch}.jpg';
            final file = File('${dir.path}/$filename');
            await file.writeAsBytes(response.bodyBytes);
            await prefs.setString('local_ticket_path', file.path);
            await prefs.setString('remote_ticket_url', remoteUrl);
            await _saveToHistory(file);
            setState(() => _localTicketPath = file.path);
          }
        } catch (e) { print("Error syncing ticket: $e"); }
      }
    }
  }

  Future<void> _pickAndUploadTicket() async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, maxHeight: 1024, imageQuality: 80);
    if (picked != null) {
      setState(() => _isLoading = true);
      try {
        if (kIsWeb) {
          final bytes = await picked.readAsBytes();
          final ext = picked.name.contains('.') ? picked.name.split('.').last : 'jpg';
          setState(() => _localTicketPath = picked.path);
          final url = await SupabaseService.uploadTicketBytes(bytes, ext);
          if (url != null) { final prefs = await SharedPreferences.getInstance(); await prefs.setString('remote_ticket_url', url); }
        } else {
          final dir = await getApplicationDocumentsDirectory();
          final filename = 'ticket_local_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final savedFile = await File(picked.path).copy('${dir.path}/$filename');
          await _saveToHistory(savedFile);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('local_ticket_path', savedFile.path);
          setState(() => _localTicketPath = savedFile.path);
          final url = await SupabaseService.uploadTicket(savedFile);
          if (url != null) { await prefs.setString('remote_ticket_url', url); }
        }
      } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"))); } finally { setState(() => _isLoading = false); }
    }
  }

  void _showFullImage({String? overridePath}) {
    final path = overridePath ?? _localTicketPath;
    if (path == null) return;
    showDialog(context: context, builder: (ctx) => GestureDetector(onTap: () => Navigator.pop(ctx), child: Dialog(backgroundColor: Colors.transparent, insetPadding: EdgeInsets.zero, child: SizedBox(width: double.infinity, height: double.infinity, child: InteractiveViewer(maxScale: 4.0, child: (kIsWeb || path.startsWith('http')) ? Image.network(path, loadingBuilder: (context, child, loadingProgress) { if (loadingProgress == null) return child; return const Center(child: CircularProgressIndicator(color: Colors.white)); }) : Image.file(File(path)))))));
  }

  void _manageTicketHistory() {
    final colors = TransColors.of(context);
    showModalBottomSheet(context: context, backgroundColor: colors.cardBg, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))), builder: (ctx) => StatefulBuilder(builder: (context, setModalState) {
          return Container(padding: const EdgeInsets.all(20), height: 500, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("Ticket History (Local)", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colors.textPrimary)),
                const SizedBox(height: 8), Text("Tickets saved on this device.", style: TextStyle(fontSize: 12, color: colors.textSecondary)), const SizedBox(height: 16),
                Expanded(child: FutureBuilder<List<File>>(future: _getLocalHistoryFiles(), builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                      final files = snapshot.data ?? [];
                      if (files.isEmpty) return Center(child: Text("No local history found.", style: TextStyle(color: colors.textSecondary)));
                      return ListView.separated(itemCount: files.length, separatorBuilder: (_,__) => Divider(color: colors.divider), itemBuilder: (ctx, idx) {
                          final file = files[idx];
                          final filename = file.path.split('/').last.replaceAll(".jpg", "");
                          final date = file.lastModifiedSync();
                          final dateStr = "${date.day}/${date.month}/${date.year}";
                          String displayName = filename.startsWith("hist_") ? "Ticket ${files.length - idx}" : filename;
                          return ListTile(leading: const Icon(Icons.airplane_ticket), title: Text(displayName, style: TextStyle(color: colors.textPrimary)), subtitle: Text(dateStr, style: TextStyle(color: colors.textSecondary)), onTap: () => _showFullImage(overridePath: file.path), trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _renameHistoryItem(file, filename, () => setModalState((){}))), IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () async { await file.delete(); setModalState(() {}); })]));
                        });
                    }))
              ]));
        }));
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.08,
      minChildSize: 0.08,
      maxChildSize: 0.85,
      snap: true, 
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.ticketSheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, -5),
              )
            ],
          ),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
            ),
            child: ListView(
              controller: scrollController,
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                GestureDetector(
                  onTap: _toggleSheet,
                  behavior: HitTestBehavior.opaque, 
                  onVerticalDragUpdate: (details) {
                    final double screenHeight = MediaQuery.of(context).size.height;
                    final double delta = details.delta.dy;
                    final double currentSize = _sheetController.size;
                    
                    double newSize = currentSize - (delta / screenHeight);
                    
                    if (newSize < 0.08) newSize = 0.08;
                    if (newSize > 0.85) newSize = 0.85;
                    
                    _sheetController.jumpTo(newSize);
                  },
                  onVerticalDragEnd: (details) {
                    final double velocity = details.primaryVelocity ?? 0;
                    if (velocity < -500) { 
                      _sheetController.animateTo(0.85, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                    } else if (velocity > 500) { 
                      _sheetController.animateTo(0.08, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                    } else {
                      if (_sheetController.size > 0.4) {
                        _sheetController.animateTo(0.85, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                      } else {
                        _sheetController.animateTo(0.08, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                      }
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: colors.modalHandle,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.qr_code, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              "My Ticket",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: colors.ticketHeader
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 10),

                // Content
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _isLoading
                    ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                    : _localTicketPath != null
                      ? Column(
                          children: [
                            GestureDetector(
                              onTap: () => _showFullImage(), 
                              onLongPress: _manageTicketHistory, 
                              child: Container(
                                constraints: const BoxConstraints(maxHeight: 500),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: colors.ticketBorder),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: kIsWeb 
                                    ? Image.network(
                                        _localTicketPath!,
                                        loadingBuilder: (context, child, loadingProgress) {
                                           if (loadingProgress == null) return child;
                                           return const SizedBox(
                                             height: 200,
                                             child: Center(child: CircularProgressIndicator())
                                           );
                                        },
                                      ) 
                                    : Image.file(File(_localTicketPath!)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextButton.icon(
                              onPressed: _pickAndUploadTicket,
                              icon: const Icon(Icons.edit),
                              label: const Text("Update Ticket"),
                            )
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 30),
                            Icon(Icons.airplane_ticket_outlined, size: 64, color: colors.ticketEmptyIcon),
                            const SizedBox(height: 16),
                            Text("No ticket added yet", style: TextStyle(color: colors.textSecondary)),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _pickAndUploadTicket,
                              icon: const Icon(Icons.add_a_photo),
                              label: Text("Add Ticket Photo", style: TextStyle(color: colors.ticketAddBtnText)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colors.ticketAddBtnBg,
                                foregroundColor: colors.ticketAddBtnText,
                              ),
                            ),
                            const SizedBox(height: 50),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}