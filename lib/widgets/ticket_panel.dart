import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intl/intl.dart';
import '../../repositories/ticket_repository.dart';

class TicketPanel extends StatefulWidget {
  final ScrollController scrollController;

  const TicketPanel({super.key, required this.scrollController});

  @override
  State<TicketPanel> createState() => _TicketPanelState();
}

class _TicketPanelState extends State<TicketPanel> {
  final _ticketRepo = TicketRepository();

  @override
  void initState() {
    super.initState();
    _ticketRepo.fetchTickets();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -5))],
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Your Tickets", style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: Colors.blue),
                  onPressed: () {
                    _ticketRepo.addTicket({
                      'title': 'Single Trip - AB',
                      'type': 'QR',
                      'valid_until': DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
                      'metadata': {'code': 'TICKET-${DateTime.now().millisecondsSinceEpoch}'}
                    });
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _ticketRepo.ticketsStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final tickets = snapshot.data!;
                if (tickets.isEmpty) {
                  return Center(child: Text("No active tickets", style: GoogleFonts.inter(color: Colors.grey)));
                }
                return ListView.builder(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  itemCount: tickets.length,
                  itemBuilder: (context, index) => _buildTicketCard(tickets[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketCard(Map<String, dynamic> ticket) {
    final title = ticket['title'] ?? 'Ticket';
    final validUntil = DateTime.parse(ticket['valid_until']);
    final isExpired = validUntil.isBefore(DateTime.now());
    final qrData = ticket['metadata']?['code'] ?? 'INVALID';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isExpired ? Colors.grey[50] : Colors.blue[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isExpired ? Colors.grey[200]! : Colors.blue[100]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: QrImageView(data: qrData, size: 60.0, gapless: false),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(isExpired ? "Expired" : "Valid until ${DateFormat('HH:mm').format(validUntil)}",
                      style: GoogleFonts.inter(fontSize: 14, color: isExpired ? Colors.red : Colors.green[700])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}