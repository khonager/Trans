// lib/widgets/ticket_panel.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../services/supabase_service.dart';

class TicketPanel extends StatefulWidget {
  const TicketPanel({super.key});

  @override
  State<TicketPanel> createState() => _TicketPanelState();
}

class _TicketPanelState extends State<TicketPanel> {
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  File? _localTicketFile;
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

  // Toggle between closed (min) and open (max)
  void _toggleSheet() {
    if (_sheetController.size > 0.3) {
      _sheetController.animateTo(
        0.08, // Close
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _sheetController.animateTo(
        0.85, // Open
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _loadLocalTicket() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('local_ticket_path');
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        setState(() => _localTicketFile = file);
      }
    }
  }

  Future<void> _syncTicketFromCloud() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;

    final remoteUrl = await SupabaseService.getTicketUrl();
    final prefs = await SharedPreferences.getInstance();
    final lastUrl = prefs.getString('remote_ticket_url');

    if (remoteUrl != null && remoteUrl != lastUrl) {
      try {
        final response = await http.get(Uri.parse(remoteUrl));
        if (response.statusCode == 200) {
          final dir = await getApplicationDocumentsDirectory();
          final filename = 'ticket_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final file = File('${dir.path}/$filename');
          await file.writeAsBytes(response.bodyBytes);

          await prefs.setString('local_ticket_path', file.path);
          await prefs.setString('remote_ticket_url', remoteUrl);

          setState(() => _localTicketFile = file);
        }
      } catch (e) {
        print("Error syncing ticket: $e");
      }
    }
  }

  Future<void> _pickAndUploadTicket() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    
    if (picked != null) {
      setState(() => _isLoading = true);
      
      try {
        final dir = await getApplicationDocumentsDirectory();
        final filename = 'ticket_local_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final savedFile = await File(picked.path).copy('${dir.path}/$filename');

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('local_ticket_path', savedFile.path);

        setState(() => _localTicketFile = savedFile);

        final url = await SupabaseService.uploadTicket(savedFile);
        if (url != null) {
          await prefs.setString('remote_ticket_url', url);
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.08,
      minChildSize: 0.08,
      maxChildSize: 0.85,
      snap: true, // Helps the sheet snap to open/closed positions
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1F2937) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, -5),
              )
            ],
          ),
          child: ListView(
            controller: scrollController,
            // CRITICAL: AlwaysScrollableScrollPhysics ensures drag gestures work even when content is short
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              // 1. The "Handle" Area - Now Tappable!
              GestureDetector(
                onTap: _toggleSheet,
                behavior: HitTestBehavior.opaque, // Ensures the entire area catches the tap
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Visual Handle Bar
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // Header Text
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
                              color: isDark ? Colors.white : Colors.black
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 10),

              // 2. The Content
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _isLoading
                  ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                  : _localTicketFile != null
                    ? Column(
                        children: [
                          Container(
                            constraints: const BoxConstraints(maxHeight: 500),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.withOpacity(0.2)),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.file(_localTicketFile!),
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
                          Icon(Icons.airplane_ticket_outlined, size: 64, color: Colors.grey.withOpacity(0.5)),
                          const SizedBox(height: 16),
                          const Text("No ticket added yet"),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _pickAndUploadTicket,
                            icon: const Icon(Icons.add_a_photo),
                            label: const Text("Add Ticket Photo"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5),
                              foregroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 50),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}