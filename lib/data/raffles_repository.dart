import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

class RafflesRepository {
  final SupabaseClient _client = Supabase.instance.client;

  String _sanitizeFileName(String fileName) {
    final cleaned = fileName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '_')
        .replaceAll(RegExp('_+'), '_')
        .trim();
    return cleaned.isEmpty ? 'comprobante.jpg' : cleaned;
  }

  String _guessMimeType(String fileName) {
    final parts = fileName.split('.');
    if (parts.length < 2) return 'application/octet-stream';
    switch (parts.last.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      default:
        return 'application/octet-stream';
    }
  }

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

  Future<List<int>> fetchNextAvailableNumbers(
    String sorteoId,
    int quantity, {
    int oversampleFactor = 3,
  }) async {
    final int take = (quantity * oversampleFactor).clamp(quantity, 5000);
    final response = await _client
        .from('boletos')
        .select('numero')
        .eq('sorteo_id', sorteoId)
        .eq('estado', 'available')
        .order('numero', ascending: true)
        .limit(take);

    final data = response as List<dynamic>;
    final sorted = data
        .map((e) => (e['numero'] as int))
        .toList()
      ..sort();

    if (sorted.length <= quantity) return sorted;
    return sorted.take(quantity).toList();
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

  Future<String?> saveReservationProof({
    required String orderId,
    required String sorteoId,
    required String buyerNombre,
    required String buyerCedula,
    required String buyerTelefono,
    required List<int> numeros,
    required Uint8List imageBytes,
    required String imageName,
    String? banco,
    double? montoTotal,
  }) async {
    final safeName = _sanitizeFileName(imageName);
    final storagePath =
        'order_$orderId/${DateTime.now().millisecondsSinceEpoch}_$safeName';

    await _client.storage.from('reservados').uploadBinary(
          storagePath,
          imageBytes,
          fileOptions: FileOptions(
            cacheControl: '3600',
            upsert: true,
            contentType: _guessMimeType(imageName),
          ),
        );

    final publicUrl =
        _client.storage.from('reservados').getPublicUrl(storagePath);

    await _client.from('reservados').insert({
      'order_id': orderId,
      'sorteo_id': sorteoId,
      'buyer_nombre': buyerNombre,
      'buyer_cedula': buyerCedula,
      'buyer_telefono': buyerTelefono,
      'numeros': numeros,
      'banco': banco,
      'monto_total': montoTotal,
      'comprobante_url': publicUrl,
      'comprobante_nombre': imageName,
    });

    return publicUrl;
  }
}
