import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/supabase_service.dart';
import '../config/app_theme.dart';

class ChatSheet extends StatefulWidget {
  final String lineId;
  final String title;

  const ChatSheet({super.key, required this.lineId, required this.title});

  @override
  State<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<ChatSheet> {
  final TextEditingController _msgCtrl = TextEditingController();

  Widget _buildAvatar(String? url, String? emoji, String username) {
    if (emoji != null && emoji.isNotEmpty) {
      return CircleAvatar(
        radius: 16,
        backgroundColor: Colors.grey.shade200,
        child: Text(emoji, style: const TextStyle(fontSize: 20)),
      );
    }
    return CircleAvatar(
      radius: 16,
      backgroundImage: url != null ? NetworkImage(url) : null,
      child: url == null ? Text(username.isNotEmpty ? username[0].toUpperCase() : "?") : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);

    return Container(
      height: 600,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: colors.cardBg, // Use theme bg for the sheet itself
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24))
      ),
      child: Column(
        children: [
          Container(
            width: 40, height: 4, 
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: colors.modalHandle, borderRadius: BorderRadius.circular(2)),
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                CircleAvatar(backgroundColor: colors.chatHeaderIconBg, child: const Icon(Icons.directions_bus, color: Colors.white)),
                const SizedBox(width: 12),
                Text(widget.title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colors.textPrimary)),
              ],
            ),
          ),
          Divider(color: colors.divider),

          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: SupabaseService.getMessages(widget.lineId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final msgs = snapshot.data!;
                if (msgs.isEmpty) return Center(child: Text(AppLocalizations.of(context)!.noMessagesYet, style: TextStyle(color: colors.textSecondary)));

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: msgs.length,
                  itemBuilder: (ctx, idx) {
                    final msg = msgs[idx];
                    final isMe = msg['user_id'] == SupabaseService.currentUser?.id;
                    final username = msg['username'] ?? 'Unknown';
                    final avatar = msg['avatar_url'];
                    final emoji = msg['avatar_emoji'];
                    
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isMe) _buildAvatar(avatar, emoji, username),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              if (!isMe) 
                                Padding(
                                  padding: const EdgeInsets.only(left: 4, bottom: 2),
                                  child: Text(username, style: TextStyle(fontSize: 10, color: colors.textSecondary)),
                                ),
                              Container(
                                constraints: const BoxConstraints(maxWidth: 240),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isMe ? colors.chatBubbleMeBg : colors.chatBubbleFriendBg,
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(16),
                                    topRight: const Radius.circular(16),
                                    bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
                                    bottomRight: isMe ? Radius.zero : const Radius.circular(16),
                                  ),
                                  border: isMe ? null : Border.all(color: colors.chatBubbleFriendBorder)
                                ),
                                child: Text(
                                  msg['content'], 
                                  style: TextStyle(color: isMe ? colors.chatBubbleMeText : colors.chatBubbleFriendText)
                                ),
                              ),
                            ],
                          )
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: InputDecoration(
                      hintText: "Say something...",
                      hintStyle: TextStyle(color: colors.textSecondary),
                      filled: true,
                      fillColor: colors.chatInputFill,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20)
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: colors.chatSendBtnBg,
                  child: IconButton(icon: Icon(Icons.send, color: colors.chatSendBtnIcon), onPressed: _send),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  void _send() {
    if (_msgCtrl.text.trim().isEmpty) return;
    SupabaseService.sendMessage(widget.lineId, _msgCtrl.text.trim());
    _msgCtrl.clear();
  }
}