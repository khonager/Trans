import 'dart:io' show File; // Only import File for mobile checks
import 'package:flutter/foundation.dart' show kIsWeb;
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
  
  // We use String path instead of File object to be web-safe
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
        // On web, path is just the URL/blob
        setState(() => _localTicketPath = path);
      } else {
        // On mobile, check if file exists
        if (await File(path).exists()) {
          setState(() => _localTicketPath = path);
        }
      }
    }
  }

  Future<void> _syncTicketFromCloud() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;

    final remoteUrl = await SupabaseService.getTicketUrl();
    final prefs = await SharedPreferences.getInstance();
    final lastUrl = prefs.getString('remote_ticket_url');

    if (remoteUrl != null) {
      // On Web, we just use the remote URL directly, no "download to file" needed
      if (kIsWeb) {
        await prefs.setString('local_ticket_path', remoteUrl);
        setState(() => _localTicketPath = remoteUrl);
        return;
      }

      // On Mobile: Download file if changed
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

            setState(() => _localTicketPath = file.path);
          }
        } catch (e) {
          print("Error syncing ticket: $e");
        }
      }
    }
  }

  Future<void> _pickAndUploadTicket() async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(source: ImageSource.gallery);
    
    if (picked != null) {
      setState(() => _isLoading = true);
      
      try {
        if (kIsWeb) {
          // Web: Just upload bytes directly
          final bytes = await picked.readAsBytes();
          // Note: Supabase Flutter web upload might need a Blob or specific handling, 
          // but for now we assume standard upload works or we rely on the URL update.
          // Since Supabase `upload` expects a File object which doesn't exist on web,
          // we use uploadBinary if available or skip local caching logic for now.
          
          // *Correction*: To make this 100% web safe without complex binary upload logic 
          // in the service right now, we will skip the upload implementation for Web in this snippet
          // unless you update SupabaseService to support `uploadBinary`.
          // For now, we will just show it locally.
          
          setState(() => _localTicketPath = picked.path); // picked.path on web is a blob URL
          
          // On Web, standard File upload won't work with dart:io File. 
          // You would need to update SupabaseService to take Uint8List.
          
        } else {
          // Mobile Logic
          final dir = await getApplicationDocumentsDirectory();
          final filename = 'ticket_local_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final savedFile = await File(picked.path).copy('${dir.path}/$filename');

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('local_ticket_path', savedFile.path);

          setState(() => _localTicketPath = savedFile.path);

          // Upload
          final url = await SupabaseService.uploadTicket(savedFile);
          if (url != null) {
            await prefs.setString('remote_ticket_url', url);
          }
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
      snap: true, 
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
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              GestureDetector(
                onTap: _toggleSheet,
                behavior: HitTestBehavior.opaque, 
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey,
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

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _isLoading
                  ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                  : _localTicketPath != null
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
                              // WEB SAFE IMAGE LOADING
                              child: kIsWeb 
                                ? Image.network(_localTicketPath!) 
                                : Image.file(File(_localTicketPath!)),
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