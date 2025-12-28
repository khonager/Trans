import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:trans/services/supabase_service.dart';
import 'package:trans/config/app_theme.dart';

class TicketPanel extends StatefulWidget {
  const TicketPanel({super.key});

  @override
  State<TicketPanel> createState() => _TicketPanelState();
}

class _TicketPanelState extends State<TicketPanel> {
  String? _ticketUrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadTicket();
  }

  Future<void> _loadTicket() async {
    final url = await SupabaseService.getTicketUrl();
    if (mounted) setState(() => _ticketUrl = url);
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image == null) return;

    setState(() => _isLoading = true);
    
    try {
      String? url;
      final bytes = await image.readAsBytes();
      final fileExt = image.path.split('.').last;
      url = await SupabaseService.uploadTicketBytes(bytes, fileExt);

      if (mounted) {
        setState(() {
          _ticketUrl = url;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
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
            color: colors.ticketSheetBg, // Uses corrected untinted color
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, -5))
            ],
            border: Border(top: BorderSide(color: colors.ticketBorder)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Container(
                  width: 40, 
                  height: 4, 
                  decoration: BoxDecoration(color: colors.modalHandle, borderRadius: BorderRadius.circular(2))
                )
              ),
              const SizedBox(height: 20),
              Text(
                "My Ticket", 
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colors.ticketHeader)
              ),
              const SizedBox(height: 20),
              
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else if (_ticketUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    _ticketUrl!,
                    fit: BoxFit.cover,
                    loadingBuilder: (c, child, progress) {
                      if (progress == null) return child;
                      return const Center(child: CircularProgressIndicator());
                    },
                  ),
                )
              else
                GestureDetector(
                  onTap: _pickAndUploadImage,
                  child: Container(
                    height: 200,
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.ticketBorder, width: 2, style: BorderStyle.solid),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.qr_code_scanner, size: 48, color: colors.ticketEmptyIcon),
                        const SizedBox(height: 10),
                        Text("Tap to upload ticket", style: TextStyle(color: colors.textSecondary)),
                      ],
                    ),
                  ),
                ),
                
              if (_ticketUrl != null) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.ticketAddBtnBg,
                      foregroundColor: colors.ticketAddBtnText,
                    ),
                    onPressed: _pickAndUploadImage,
                    child: const Text("Update Ticket"),
                  ),
                )
              ]
            ],
          ),
        );
      },
    );
  }
}