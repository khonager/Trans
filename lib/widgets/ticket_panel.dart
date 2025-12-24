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
  File? _localTicketFile;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadLocalTicket();
    _syncTicketFromCloud();
  }

  /// 1. Load ticket from local storage (Offline support)
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

  /// 2. Check cloud for updates and download if necessary
  Future<void> _syncTicketFromCloud() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;

    final remoteUrl = await SupabaseService.getTicketUrl();
    final prefs = await SharedPreferences.getInstance();
    final lastUrl = prefs.getString('remote_ticket_url');

    // If we have a new URL from the cloud, download it
    if (remoteUrl != null && remoteUrl != lastUrl) {
      try {
        final response = await http.get(Uri.parse(remoteUrl));
        if (response.statusCode == 200) {
          final dir = await getApplicationDocumentsDirectory();
          // Save with a unique name to avoid cache issues
          final filename = 'ticket_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final file = File('${dir.path}/$filename');
          await file.writeAsBytes(response.bodyBytes);

          // Update pointers
          await prefs.setString('local_ticket_path', file.path);
          await prefs.setString('remote_ticket_url', remoteUrl);

          setState(() => _localTicketFile = file);
        }
      } catch (e) {
        print("Error syncing ticket: $e");
      }
    }
  }

  /// 3. User picks a new ticket
  Future<void> _pickAndUploadTicket() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    
    if (picked != null) {
      setState(() => _isLoading = true);
      
      try {
        // Save locally first
        final dir = await getApplicationDocumentsDirectory();
        final filename = 'ticket_local_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final savedFile = await File(picked.path).copy('${dir.path}/$filename');

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('local_ticket_path', savedFile.path);

        setState(() => _localTicketFile = savedFile);

        // Upload to cloud
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
      initialChildSize: 0.08, // Small bar at bottom
      minChildSize: 0.08,
      maxChildSize: 0.85,     // Almost full screen when open
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
            padding: const EdgeInsets.all(16),
            children: [
              // Handle Bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              
              // Collapsed Header View
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
              
              const SizedBox(height: 30),

              // Expanded Content
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else if (_localTicketFile != null)
                Column(
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
              else
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 50),
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
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}