import 'dart:convert';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TicketRepository {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  // Broadcasts the list of tickets to the UI
  final _ticketsController = StreamController<List<Map<String, dynamic>>>.broadcast();

  Stream<List<Map<String, dynamic>>> get ticketsStream => _ticketsController.stream;

  /// Loads tickets from cache immediately, then attempts to refresh from Supabase.
  Future<void> fetchTickets() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    // 1. Load Local Cache
    await _loadFromLocalCache();

    // 2. Fetch from Network
    try {
      final response = await _supabase
          .from('tickets')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      final List<Map<String, dynamic>> tickets = 
          List<Map<String, dynamic>>.from(response);

      // 3. Save & Emit
      await _saveToLocalCache(tickets);
      _ticketsController.add(tickets);
      
    } catch (e) {
      print('Ticket sync failed, keeping offline data: $e');
    }
  }

  /// Adds a ticket to the database and updates the local list.
  Future<void> addTicket(Map<String, dynamic> ticketData) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final newTicket = {
      ...ticketData,
      'user_id': user.id,
      'created_at': DateTime.now().toIso8601String(),
    };

    try {
      // 1. Save to Cloud
      final response = await _supabase
          .from('tickets')
          .insert(newTicket)
          .select()
          .single();

      // 2. Refresh local data
      await fetchTickets(); 

    } catch (e) {
      print('Failed to add ticket: $e');
      rethrow;
    }
  }

  Future<void> _saveToLocalCache(List<Map<String, dynamic>> tickets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_tickets', jsonEncode(tickets));
  }

  Future<void> _loadFromLocalCache() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('cached_tickets');
    
    if (jsonString != null) {
      try {
        final List<dynamic> decoded = jsonDecode(jsonString);
        final tickets = decoded.cast<Map<String, dynamic>>();
        _ticketsController.add(tickets);
      } catch (e) {
        print('Error parsing local ticket cache: $e');
      }
    }
  }
}