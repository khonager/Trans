import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/community_safety_service.dart';
import '../services/supabase_service.dart';
import '../config/app_theme.dart';
import '../utils/app_error.dart';

class PrivateChatSheet extends StatefulWidget {
  final String friendId;
  final String friendName;

  const PrivateChatSheet(
      {super.key, required this.friendId, required this.friendName});

  @override
  State<PrivateChatSheet> createState() => _PrivateChatSheetState();
}

class _PrivateChatSheetState extends State<PrivateChatSheet> {
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  bool get _isGerman => Localizations.localeOf(context).languageCode == 'de';

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
      child: url == null
          ? Text(username.isNotEmpty ? username[0].toUpperCase() : "?")
          : null,
    );
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _showConversationActions() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: Colors.orange),
              title: Text(_isGerman ? 'Nutzer melden' : 'Report user'),
              subtitle: Text(widget.friendName),
              onTap: () async {
                Navigator.pop(sheetContext);
                await CommunitySafetyService.showReportDialog(
                  context,
                  contentType: 'private chat user',
                  targetId: widget.friendId,
                  targetLabel: widget.friendName,
                  reportedUserId: widget.friendId,
                  reportedUsername: widget.friendName,
                  source: 'private chat',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.block, color: Colors.red),
              title: Text(_isGerman ? 'Nutzer blockieren' : 'Block user'),
              subtitle: Text(widget.friendName),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(sheetContext);
                await SupabaseService.blockUser(widget.friendId);
                if (!mounted) return;
                Navigator.pop(context);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(_isGerman
                        ? '${widget.friendName} wurde blockiert.'
                        : '${widget.friendName} was blocked.'),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reportMessage(Map<String, dynamic> msg) async {
    await CommunitySafetyService.showReportDialog(
      context,
      contentType: 'private chat message',
      targetId: msg['id']?.toString() ?? '${widget.friendId}:message',
      targetLabel: widget.friendName,
      reportedUserId: widget.friendId,
      reportedUsername: widget.friendName,
      messagePreview: msg['content']?.toString(),
      source: 'private chat',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    final size = MediaQuery.of(context).size;
    final double sheetHeight = size.height * 0.9; // 90% of screen height

    return Container(
      height: sheetHeight,
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
          color: colors.cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
                color: colors.modalHandle,
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.lock, size: 16, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(
                        AppLocalizations.of(context)!
                            .secureChat(widget.friendName),
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary)),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.shield_outlined,
                          color: colors.textSecondary),
                      tooltip:
                          _isGerman ? 'Sicherheitsoptionen' : 'Safety options',
                      onPressed: _showConversationActions,
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: colors.textSecondary),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                )
              ],
            ),
          ),
          Divider(color: colors.divider),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: SupabaseService.getPrivateMessages(widget.friendId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final msgs = snapshot.data!;

                // Auto-scroll to bottom when new messages arrive
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _scrollToBottom());

                if (msgs.isEmpty) {
                  return Center(
                      child: Text(
                          AppLocalizations.of(context)!.noSecureMessagesYet,
                          style: TextStyle(color: colors.textSecondary)));
                }

                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(16),
                  itemCount: msgs.length,
                  itemBuilder: (ctx, idx) {
                    final msg = msgs[idx];
                    final isMe =
                        msg['user_id'] == SupabaseService.currentUser?.id;
                    final username = msg['username'] ?? 'Unknown';
                    final avatar = msg['avatar_url'];
                    final emoji = msg['avatar_emoji'];

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: isMe
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isMe) ...[
                            _buildAvatar(avatar, emoji, username),
                            const SizedBox(width: 8),
                          ],
                          Column(
                            crossAxisAlignment: isMe
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onLongPress:
                                    isMe ? null : () => _reportMessage(msg),
                                child: Container(
                                  constraints: BoxConstraints(
                                      maxWidth: size.width * 0.7),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isMe
                                        ? Colors.green.shade800
                                        : colors.chatBubbleFriendBg,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(16),
                                      topRight: const Radius.circular(16),
                                      bottomLeft: isMe
                                          ? const Radius.circular(16)
                                          : Radius.zero,
                                      bottomRight: isMe
                                          ? Radius.zero
                                          : const Radius.circular(16),
                                    ),
                                  ),
                                  child: Text(msg['content'],
                                      style: TextStyle(
                                          color: isMe
                                              ? Colors.white
                                              : colors.chatBubbleFriendText)),
                                ),
                              ),
                            ],
                          ),
                          if (!isMe) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.flag_outlined,
                                  size: 18, color: colors.textSecondary),
                              tooltip: _isGerman
                                  ? 'Nachricht melden'
                                  : 'Report message',
                              onPressed: () => _reportMessage(msg),
                            ),
                          ],
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
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20)),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: colors.chatSendBtnBg,
                  child: IconButton(
                      icon: Icon(Icons.send, color: colors.chatSendBtnIcon),
                      onPressed: _send),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Future<void> _send() async {
    if (_msgCtrl.text.trim().isEmpty) return;
    try {
      await SupabaseService.sendPrivateMessage(
          widget.friendId, _msgCtrl.text.trim());
      _msgCtrl.clear();
      // Wait slightly for the stream to update then scroll
      Future.delayed(const Duration(milliseconds: 300), _scrollToBottom);
    } catch (e, st) {
      if (!mounted) return;
      AppError.showSnackBar(
        context,
        error: e,
        stackTrace: st,
        source: 'send private message',
      );
    }
  }
}
