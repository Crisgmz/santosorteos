import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

class RafflesRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Sorteo>> fetchActiveRaffles() async {
    final response = await _client
        .from('sorteos')
        .select('''
      id,
      titulo,
      descripcion,
      precio_ticket,
      total_tickets,
      fecha_sorteo,
      imagen_url,
      premios(
        id,
        posicion,
        titulo,
        descripcion,
        imagen_url
      )
    ''')
        .eq('estado', 'active')
        .order('created_at', ascending: false)
        .order('posicion', referencedTable: 'premios', ascending: true);

    final List<dynamic> data = response as List<dynamic>;

    return Future.wait(
      data.map((item) async {
        final sorteoId = item['id'] as String;
        final sold = await _countSoldTickets(sorteoId);
        return Sorteo.fromMap(item as Map<String, dynamic>, soldTickets: sold);
      }),
    );
  }

  Future<Sorteo> fetchRaffleDetail(String sorteoId) async {
    final response = await _client
        .from('sorteos')
        .select('''
      id,
      titulo,
      descripcion,
      precio_ticket,
      total_tickets,
      fecha_sorteo,
      imagen_url,
      premios(
        id,
        posicion,
        titulo,
        descripcion,
        imagen_url
      )
    ''')
        .eq('id', sorteoId)
        .order('posicion', referencedTable: 'premios', ascending: true)
        .maybeSingle();

    if (response == null) {
      throw const PostgrestException(message: 'Sorteo no encontrado');
    }

    final sold = await _countSoldTickets(sorteoId);
    return Sorteo.fromMap(response, soldTickets: sold);
  }

  Future<int> _countSoldTickets(String sorteoId) async {
    final response = await _client
        .from('boletos')
        .select('id')
        .eq('sorteo_id', sorteoId)
        .eq('estado', 'sold')
        .count(CountOption.exact); // aquí está la magia

    return response.count ?? 0;
  }

  Future<List<int>> fetchAvailableNumbers(String sorteoId, int limit) async {
    final response = await _client
        .from('boletos')
        .select('numero')
        .eq('sorteo_id', sorteoId)
        .eq('estado', 'available')
        .order('numero')
        .limit(limit);

    final data = response as List<dynamic>;
    return data.map((e) => (e['numero'] as int)).toList();
  }

  Future<List<VerifiedTicket>> verifyTickets(
    String rawInput, {
    bool searchNumberExact = false,
    bool searchPhoneOnly = false,
    String? sorteoId,
  }) async {
    final sanitized = rawInput.replaceAll(RegExp(r'[^0-9]'), '');
    if (sanitized.isEmpty) return [];

    final List<String> conditions = [];
    final number = int.tryParse(sanitized);

    const int maxPgInt = 2147483647;
    if (!searchPhoneOnly &&
        number != null &&
        number > 0 &&
        number <= maxPgInt) {
      conditions.add('numero.eq.$number');
    }

    if (!searchNumberExact) {
      final phonePatterns = <String>[
        'buyer_telefono.eq.$sanitized',
        'buyer_telefono.eq.$rawInput',
        'buyer_telefono.ilike.%$sanitized%',
      ];

      if (sanitized.length >= 6) {
        final chunk1 = sanitized.substring(0, 3);
        final chunk2 = sanitized.substring(
          3,
          sanitized.length >= 6 ? 6 : sanitized.length,
        );
        final chunk3 = sanitized.length > 6 ? sanitized.substring(6) : '';
        final spacedPattern = [
          chunk1,
          chunk2,
          chunk3,
        ].where((c) => c.isNotEmpty).join('%');
        phonePatterns.add('buyer_telefono.ilike.%$spacedPattern%');
      }

      conditions.addAll(phonePatterns);
    }

    if (conditions.isEmpty) return [];

    final orFilter = conditions.join(',');

    var query = _client
        .from('boletos')
        .select(
          'id, numero, estado, sorteo_id, buyer_nombre, buyer_cedula, buyer_telefono, precio_snapshot, sold_at, sorteo:sorteos(titulo, imagen_url), sorteo_titulo_snapshot',
        )
        .filter('estado', 'in', ['sold', 'reserved']);

    if (sorteoId != null && sorteoId.isNotEmpty) {
      query = query.eq('sorteo_id', sorteoId);
    }

    final response = await query
        .or(orFilter)
        .order('sold_at', ascending: false)
        .limit(50);

    final data = response as List<dynamic>;
    return data
        .map((item) => VerifiedTicket.fromMap(item as Map<String, dynamic>))
        .toList();
  }

  Future<String?> reserveTickets({
    required String sorteoId,
    required List<int> numbers,
    required String nombre,
    required String cedula,
    required String telefono,
  }) async {
    final response = await _client.rpc(
      'reserve_tickets',
      params: {
        'p_sorteo_id': sorteoId,
        'p_numbers': numbers,
        'p_buyer_nombre': nombre,
        'p_buyer_cedula': cedula,
        'p_buyer_telefono': telefono,
      },
    );

    final data = response as List<dynamic>;
    if (data.isEmpty) return null;
    final first = data.first as Map<String, dynamic>;
    return first['order_id'] as String?;
  }
}
