import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../config/app_theme.dart';

class PrivateChatSheet extends StatefulWidget {
  final String friendId;
  final String friendName;

  const PrivateChatSheet({super.key, required this.friendId, required this.friendName});

  @override
  State<PrivateChatSheet> createState() => _PrivateChatSheetState();
}

class _PrivateChatSheetState extends State<PrivateChatSheet> {
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
        color: colors.cardBg, 
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
                const Icon(Icons.lock, size: 16, color: Colors.green),
                const SizedBox(width: 8),
                Text("Secure Chat: ${widget.friendName}", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colors.textPrimary)),
              ],
            ),
          ),
          Divider(color: colors.divider),

          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: SupabaseService.getPrivateMessages(widget.friendId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final msgs = snapshot.data!;
                if (msgs.isEmpty) return Center(child: Text("No secure messages yet.", style: TextStyle(color: colors.textSecondary)));

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
                              Container(
                                constraints: const BoxConstraints(maxWidth: 240),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isMe ? Colors.green.shade800 : colors.chatBubbleFriendBg,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  msg['content'], 
                                  style: TextStyle(color: isMe ? Colors.white : colors.chatBubbleFriendText)
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
                      hintText: "Encrypted Message...",
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
    SupabaseService.sendPrivateMessage(widget.friendId, _msgCtrl.text.trim());
    _msgCtrl.clear();
  }
}