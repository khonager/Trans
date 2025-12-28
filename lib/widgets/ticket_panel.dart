import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http; // For downloading backup
import 'package:trans/services/supabase_service.dart';
import 'package:trans/config/app_theme.dart';

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
    _initTicket();
  }

  Future<void> _initTicket() async {
    // 1. Check Local Storage First (Offline Support)
    final directory = await getApplicationDocumentsDirectory();
    final localPath = '${directory.path}/saved_ticket.png';
    final localFile = File(localPath);

    if (await localFile.exists()) {
      if (mounted) setState(() => _localTicketFile = localFile);
    } 
    
    // 2. Check Cloud Backup (Sync)
    // We do this silently in background to update if needed
    _syncFromCloud(localFile);
  }

  Future<void> _syncFromCloud(File localFile) async {
    try {
      final url = await SupabaseService.getTicketUrl();
      if (url != null && url.isNotEmpty) {
        // Download and compare/save
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          await localFile.writeAsBytes(response.bodyBytes);
          if (mounted) setState(() => _localTicketFile = localFile);
        }
      }
    } catch (e) {
      // Offline or error, just ignore and keep using local file if it exists
      debugPrint("Cloud sync failed: $e");
    }
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    // Pick image
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50); // Quality 50 = "Low Res" backup
    
    if (image == null) return;

    setState(() => _isLoading = true);
    
    try {
      final bytes = await image.readAsBytes();
      
      // 1. Save Locally (High Priority)
      final directory = await getApplicationDocumentsDirectory();
      final localPath = '${directory.path}/saved_ticket.png';
      final localFile = File(localPath);
      await localFile.writeAsBytes(bytes);
      
      // Update UI immediately
      if (mounted) {
        setState(() {
          _localTicketFile = localFile;
        });
      }

      // 2. Upload to Cloud (Backup)
      final fileExt = image.path.split('.').last;
      await SupabaseService.uploadTicketBytes(bytes, fileExt);

      if (mounted) setState(() => _isLoading = false);
      
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        // Even if upload fails, we have the local file, so we just warn the user
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Saved locally. Cloud backup failed: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);

    return DraggableScrollableSheet(
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
              // Handle
              Center(
                child: Container(
                  width: 40, 
                  height: 4, 
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(color: colors.modalHandle, borderRadius: BorderRadius.circular(2))
                )
              ),
              
              // Header
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
              
              // Content
              if (_isLoading)
                Container(height: 300, alignment: Alignment.center, child: const CircularProgressIndicator())
              else if (_localTicketFile != null)
                Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(
                        _localTicketFile!,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => 
                          Container(height: 200, alignment: Alignment.center, child: const Text("Error loading ticket file")),
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
                // Empty State
                GestureDetector(
                  onTap: _pickAndUploadImage,
                  child: Container(
                    height: 220,
                    decoration: BoxDecoration(
                      // Clean look: Light grey/dark grey fill with dashed-style border effect
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