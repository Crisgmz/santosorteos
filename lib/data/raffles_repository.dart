import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:convert';
import 'package:http/http.dart' as http;
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

  Future<List<Sorteo>> fetchAllRaffles() async {
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
      imagenes,
      mostrar_numeros,
      promocion_cantidad_compra,
      promocion_cantidad_regalo,
      estado,
      premios(
        id,
        posicion,
        titulo,
        descripcion,
        imagen_url
      )
    ''')
        // .eq('estado', 'active') // Eliminado para traer todos (activos y finalizados)
        .order('fecha_sorteo', ascending: true)
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
      imagenes,
      mostrar_numeros,
      promocion_cantidad_compra,
      promocion_cantidad_regalo,
      estado,
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
      throw const PostgrestException(message: 'Evento no encontrado');
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

    return response.count;
  }

  Future<List<int>> fetchSoldTicketNumbers(String sorteoId) async {
    final response = await _client
        .from('boletos')
        .select('numero')
        .eq('sorteo_id', sorteoId)
        .filter('estado', 'in', [
          'sold',
          'reserved',
        ]); // Include both sold and reserved

    final data = response as List<dynamic>;
    return data.map((e) => (e['numero'] as int)).toList();
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
    final sorted = data.map((e) => (e['numero'] as int)).toList()..sort();

    if (sorted.length <= quantity) return sorted;
    return sorted.take(quantity).toList();
  }

  Future<List<int>> fetchRandomAvailableNumbers(
    String sorteoId,
    int quantity,
  ) async {
    // Traemos un pool grande de boletos disponibles (ej. 2000)
    // para asegurar aleatoriedad en la selección
    final response = await _client
        .from('boletos')
        .select('numero')
        .eq('sorteo_id', sorteoId)
        .eq('estado', 'available')
        .limit(100000);

    final data = response as List<dynamic>;
    var numbers = data.map((e) => (e['numero'] as int)).toList();

    // Mezclar la lista localmente
    numbers.shuffle();

    if (numbers.length <= quantity) return numbers;
    return numbers.take(quantity).toList();
  }

  Future<List<VerifiedTicket>> verifyTickets(
    String rawInput, {
    bool searchNumberExact = false,
    bool searchPhoneOnly = false,
    String? sorteoId,
  }) async {
    final sanitized = rawInput.replaceAll(RegExp(r'[^0-9]'), '');
    if (sanitized.isEmpty) return [];

    print('🔍 Iniciando búsqueda con: "$rawInput" (sanitized: "$sanitized")');

    final List<VerifiedTicket> results = [];
    final Set<String> processedTicketIds = {};

    // PASO 1: Buscar por número de ticket directo
    final number = int.tryParse(sanitized);
    const int maxPgInt = 2147483647;

    if (!searchPhoneOnly &&
        number != null &&
        number > 0 &&
        number <= maxPgInt) {
      print('🎫 Buscando ticket #$number');
      try {
        var query = _client
            .from('boletos')
            .select(
              'id, numero, estado, sorteo_id, order_id, buyer_nombre, buyer_cedula, buyer_telefono, precio_snapshot, sold_at, sorteo:sorteos(titulo, imagen_url), sorteo_titulo_snapshot',
            )
            .eq('numero', number)
            .filter('estado', 'in', ['sold', 'reserved']);

        if (sorteoId != null && sorteoId.isNotEmpty) {
          query = query.eq('sorteo_id', sorteoId);
        }

        final ticketsData = await query.limit(500);

        for (var t in (ticketsData as List<dynamic>)) {
          final map = t as Map<String, dynamic>;
          final ticketId = map['id'].toString();
          if (!processedTicketIds.contains(ticketId)) {
            processedTicketIds.add(ticketId);

            // Si es reservado y no tiene buyer info, buscar en orden
            if (map['estado'] == 'reserved' && map['buyer_nombre'] == null) {
              final oid = map['order_id']?.toString();
              if (oid != null) {
                try {
                  final orderData = await _client
                      .from('ordenes')
                      .select('buyer_nombre, buyer_cedula, buyer_telefono')
                      .eq('id', oid)
                      .maybeSingle();

                  if (orderData != null) {
                    map['orden'] = orderData;
                  }
                } catch (e) {
                  print('⚠️ No se pudo obtener orden $oid: $e');
                }
              }
            }

            results.add(VerifiedTicket.fromMap(map));
          }
        }
        print('✅ Encontrados ${ticketsData.length} tickets por número');
      } catch (e) {
        print('❌ Error buscando por número: $e');
      }
    }

    // PASO 2: Buscar por teléfono en ordenes
    if (!searchNumberExact) {
      print('📞 Buscando por teléfono en ordenes');

      // Primero intentar buscar directamente en boletos por teléfono
      try {
        print('🔍 Intentando búsqueda directa en boletos...');
        final boletoConditions = <String>[];
        boletoConditions.add('buyer_telefono.eq.$sanitized');
        boletoConditions.add('buyer_telefono.eq.$rawInput');
        boletoConditions.add('buyer_telefono.ilike.%$sanitized%');

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
          boletoConditions.add('buyer_telefono.ilike.%$spacedPattern%');
        }

        var directQuery = _client
            .from('boletos')
            .select(
              'id, numero, estado, sorteo_id, order_id, buyer_nombre, buyer_cedula, buyer_telefono, precio_snapshot, sold_at, sorteo:sorteos(titulo, imagen_url), sorteo_titulo_snapshot',
            )
            .or(boletoConditions.join(','))
            .filter('estado', 'in', ['sold', 'reserved']);

        if (sorteoId != null && sorteoId.isNotEmpty) {
          directQuery = directQuery.eq('sorteo_id', sorteoId);
        }

        final directTickets = await directQuery
            .order('sold_at', ascending: false, nullsFirst: true)
            .limit(500);

        print(
          '🎫 Búsqueda directa encontró ${(directTickets as List).length} tickets',
        );

        for (var t in directTickets) {
          final map = Map<String, dynamic>.from(t);
          final ticketId = map['id'].toString();

          if (!processedTicketIds.contains(ticketId)) {
            processedTicketIds.add(ticketId);
            print(
              '  ✅ Ticket #${map['numero']} - Estado: ${map['estado']} - Tel: ${map['buyer_telefono']}',
            );
            results.add(VerifiedTicket.fromMap(map));
          }
        }
      } catch (e) {
        print('⚠️ Búsqueda directa en boletos falló: $e');
      }

      // Luego intentar vía ordenes (para tickets sin buyer_telefono en boletos)
      try {
        final orderConditions = <String>[];
        orderConditions.add('buyer_telefono.eq.$sanitized');
        orderConditions.add('buyer_telefono.eq.$rawInput');
        orderConditions.add('buyer_telefono.ilike.%$sanitized%');

        // Agregar búsqueda con guiones
        if (sanitized.length == 10) {
          final withDashes =
              '${sanitized.substring(0, 3)}-${sanitized.substring(3, 6)}-${sanitized.substring(6)}';
          orderConditions.add('buyer_telefono.eq.$withDashes');
          print('🔎 También buscando formato: $withDashes');
        }

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
          orderConditions.add('buyer_telefono.ilike.%$spacedPattern%');
        }

        print(
          '🔎 Condiciones de búsqueda en ordenes: ${orderConditions.join(' OR ')}',
        );

        final ordersResponse = await _client
            .from('ordenes')
            .select('id, buyer_nombre, buyer_cedula, buyer_telefono, status')
            .or(orderConditions.join(','))
            .limit(500);

        final ordersList = ordersResponse as List<dynamic>;
        print('📦 Encontradas ${ordersList.length} órdenes (todas)');

        // Debug: mostrar las primeras órdenes encontradas
        if (ordersList.isNotEmpty) {
          for (
            var i = 0;
            i < (ordersList.length > 3 ? 3 : ordersList.length);
            i++
          ) {
            final o = ordersList[i] as Map<String, dynamic>;
            print(
              '  📋 Orden ${i + 1}: ID=${o['id']}, Tel=${o['buyer_telefono']}, Status=${o['status']}',
            );
          }
        }

        if (ordersList.isNotEmpty) {
          final orderIds = ordersList
              .map((o) => (o as Map<String, dynamic>)['id'].toString())
              .toList();

          print('🔍 Buscando tickets para ${orderIds.length} órdenes');

          // Buscar todos los tickets de esas órdenes
          var ticketsQuery = _client
              .from('boletos')
              .select(
                'id, numero, estado, sorteo_id, order_id, buyer_nombre, buyer_cedula, buyer_telefono, precio_snapshot, sold_at, sorteo:sorteos(titulo, imagen_url), sorteo_titulo_snapshot',
              )
              .filter('order_id', 'in', orderIds)
              .filter('estado', 'in', ['sold', 'reserved']);

          if (sorteoId != null && sorteoId.isNotEmpty) {
            ticketsQuery = ticketsQuery.eq('sorteo_id', sorteoId);
          }

          final ticketsData = await ticketsQuery
              .order('sold_at', ascending: false, nullsFirst: true)
              .limit(500);

          print(
            '🎫 Encontrados ${(ticketsData as List).length} tickets de esas órdenes',
          );

          // Crear un mapa de órdenes para acceso rápido
          final ordersMap = {
            for (var o in ordersList)
              (o as Map<String, dynamic>)['id'].toString(): o,
          };

          for (var t in ticketsData) {
            final map = Map<String, dynamic>.from(t);
            final ticketId = map['id'].toString();

            if (!processedTicketIds.contains(ticketId)) {
              processedTicketIds.add(ticketId);

              // Inyectar datos de la orden si no están en el ticket
              final oid = map['order_id']?.toString();
              if (oid != null && ordersMap.containsKey(oid)) {
                map['orden'] = ordersMap[oid];
                print(
                  '  ✅ Ticket #${map['numero']} - Estado: ${map['estado']} - Orden: $oid',
                );
              }

              results.add(VerifiedTicket.fromMap(map));
            }
          }
        }
      } catch (e, stackTrace) {
        print('❌ Error buscando por teléfono en ordenes: $e');
        print('   Stack trace: $stackTrace');
      }

      // PASO 3: Buscar en tabla reservados (comprobantes subidos)
      print('📋 Buscando en tabla reservados');
      try {
        final resConditions = <String>[];
        resConditions.add('buyer_telefono.eq.$sanitized');
        resConditions.add('buyer_telefono.eq.$rawInput');
        resConditions.add('buyer_telefono.ilike.%$sanitized%');

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
          resConditions.add('buyer_telefono.ilike.%$spacedPattern%');
        }

        final reservadosResponse = await _client
            .from('reservados')
            .select(
              'id, sorteo_id, buyer_nombre, buyer_cedula, buyer_telefono, numeros, created_at',
            )
            .or(resConditions.join(','))
            .limit(500);

        final reservadosList = reservadosResponse as List<dynamic>;
        print(
          '📦 Encontrados ${reservadosList.length} registros en reservados',
        );

        for (var r in reservadosList) {
          final map = r as Map<String, dynamic>;
          final numerosRaw = map['numeros'];
          final numeros = numerosRaw is List
              ? List<int>.from(
                  numerosRaw.map(
                    (e) => e is int ? e : int.tryParse(e.toString()) ?? 0,
                  ),
                )
              : <int>[];

          final sId = map['sorteo_id'].toString();
          if (sorteoId != null && sorteoId.isNotEmpty && sId != sorteoId) {
            continue;
          }

          for (var n in numeros) {
            // Verificar si ya tenemos este ticket
            final exists = results.any(
              (t) => t.numero == n && t.sorteoId == sId,
            );
            if (!exists) {
              results.add(
                VerifiedTicket(
                  boletoId: 'res_${map['id']}_$n',
                  numero: n,
                  estado: 'reserved',
                  sorteoId: sId,
                  sorteoTitulo: 'Evento',
                  buyerNombre: map['buyer_nombre'],
                  buyerCedula: map['buyer_cedula'],
                  buyerTelefono: map['buyer_telefono'],
                  soldAt: map['created_at'] != null
                      ? DateTime.tryParse(map['created_at'].toString())
                      : null,
                ),
              );
            }
          }
        }
      } catch (e) {
        print('❌ Error buscando en reservados: $e');
      }
    }

    print('✅ Total de resultados: ${results.length}');
    return results;
  }

  Future<String?> reserveTickets({
    required String sorteoId,
    required List<int> numbers,
    required String nombre,
    required String cedula,
    required String telefono,
    String? email,
  }) async {
    final params = {
      'p_sorteo_id': sorteoId,
      'p_numbers': numbers,
      'p_buyer_nombre': nombre,
      'p_buyer_cedula': cedula,
      'p_buyer_telefono': telefono,
    };

    if (email != null && email.isNotEmpty) {
      params['p_buyer_email'] = email;
    }

    final response = await _client.rpc('reserve_tickets', params: params);

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
    Uint8List? imageBytes,
    String? imageName,
    String? banco,
    double? montoTotal,
    String? email,
  }) async {
    String? publicUrl;
    String? finalImageName = imageName;

    if (imageBytes != null && imageName != null) {
      final safeName = _sanitizeFileName(imageName);
      final storagePath =
          'order_$orderId/${DateTime.now().millisecondsSinceEpoch}_$safeName';

      await _client.storage
          .from('reservados')
          .uploadBinary(
            storagePath,
            imageBytes,
            fileOptions: FileOptions(
              cacheControl: '3600',
              upsert: true,
              contentType: _guessMimeType(imageName),
            ),
          );

      publicUrl = _client.storage.from('reservados').getPublicUrl(storagePath);
    }

    final dataToInsert = {
      'order_id': orderId,
      'sorteo_id': sorteoId,
      'buyer_nombre': buyerNombre,
      'buyer_cedula': buyerCedula,
      'buyer_telefono': buyerTelefono,
      'numeros': numeros,
      'banco': banco,
      'monto_total': montoTotal,
      'comprobante_url': publicUrl ?? '',
      'comprobante_nombre': finalImageName ?? '',
    };

    if (email != null && email.isNotEmpty) {
      dataToInsert['buyer_email'] = email;
    }

    await _client.from('reservados').insert(dataToInsert);

    return publicUrl;
  }

  /// Dispara el envío de correo llamando al script PHP en el servidor
  Future<void> triggerEmailPhp({
    required String email,
    required String nombre,
    required List<int> boletos,
    String? comprobanteUrl,
    String? telefono,
    String? nombreSorteo,
  }) async {
    try {
      // AJUSTAR URL SI ES NECESARIO
      final url = Uri.parse('https://multisorteos.com/api_trigger_email.php');

      print('🚀 Disparando email PHP a $url para $email...');

      // Convertir lista de enteros a string separado por comas: "2, 3, 4"
      final boletosStr = boletos.join(', ');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'nombre': nombre,
          'boletos': boletosStr, // Campo nuevo 'boletos'
          'ticket_id': boletosStr, // Backwards compatibility
          'telefono': telefono ?? '',
          'nombre_sorteo': nombreSorteo ?? 'Evento Multisorteos',
          if (comprobanteUrl != null) 'comprobante_url': comprobanteUrl,
        }),
      );

      if (response.statusCode == 200) {
        print(
          '✅ Email PHP disparado correctamente. Respuesta: ${response.body}',
        );
      } else {
        print(
          '❌ Error disparando email PHP. Código: ${response.statusCode}. Body: ${response.body}',
        );
      }
    } catch (e) {
      print('❌ Excepción al disparar email PHP: $e');
    }
  }
}
