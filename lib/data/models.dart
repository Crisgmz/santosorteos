class Premio {
  final String id;
  final int posicion;
  final String titulo;
  final String? descripcion;
  final String? imagenUrl;

  const Premio({
    required this.id,
    required this.posicion,
    required this.titulo,
    this.descripcion,
    this.imagenUrl,
  });

  factory Premio.fromMap(Map<String, dynamic> map) {
    return Premio(
      id: map['id'] as String,
      posicion: (map['posicion'] ?? 1) as int,
      titulo: (map['titulo'] ?? '').toString(),
      descripcion: map['descripcion'] as String?,
      imagenUrl: map['imagen_url'] as String?,
    );
  }
}

class Sorteo {
  final String id;
  final String titulo;
  final String? descripcion;
  final double precioTicket;
  final int totalTickets;
  final DateTime? fechaSorteo;
  final String? imagenUrl;
  final List<Premio> premios;
  final int soldTickets;

  const Sorteo({
    required this.id,
    required this.titulo,
    this.descripcion,
    required this.precioTicket,
    required this.totalTickets,
    this.fechaSorteo,
    this.imagenUrl,
    this.premios = const [],
    this.soldTickets = 0,
  });

  factory Sorteo.fromMap(Map<String, dynamic> map, {int soldTickets = 0}) {
    final premiosData = map['premios'] as List<dynamic>? ?? [];
    return Sorteo(
      id: map['id'] as String,
      titulo: (map['titulo'] ?? '').toString(),
      descripcion: map['descripcion'] as String?,
      precioTicket: double.tryParse('${map['precio_ticket']}') ?? 0,
      totalTickets: map['total_tickets'] as int? ?? 0,
      fechaSorteo: map['fecha_sorteo'] != null
          ? DateTime.tryParse(map['fecha_sorteo'])
          : null,
      imagenUrl: map['imagen_url'] as String?,
      premios: premiosData
          .map((p) => Premio.fromMap(p as Map<String, dynamic>))
          .toList(),
      soldTickets: soldTickets,
    );
  }

  double get porcentajeVendido {
    if (totalTickets == 0) return 0;
    return soldTickets / totalTickets;
  }

  Sorteo copyWith({int? soldTickets}) {
    return Sorteo(
      id: id,
      titulo: titulo,
      descripcion: descripcion,
      precioTicket: precioTicket,
      totalTickets: totalTickets,
      fechaSorteo: fechaSorteo,
      imagenUrl: imagenUrl,
      premios: premios,
      soldTickets: soldTickets ?? this.soldTickets,
    );
  }
}

class VerifiedTicket {
  final String boletoId;
  final int numero;
  final String estado;
  final String sorteoId;
  final String sorteoTitulo;
  final String? buyerNombre;
  final String? buyerTelefono;
  final String? buyerCedula;
  final double? precio;
  final DateTime? soldAt;
  final String? sorteoImagenUrl;

  const VerifiedTicket({
    required this.boletoId,
    required this.numero,
    required this.estado,
    required this.sorteoId,
    required this.sorteoTitulo,
    this.buyerNombre,
    this.buyerTelefono,
    this.buyerCedula,
    this.precio,
    this.soldAt,
    this.sorteoImagenUrl,
  });

  factory VerifiedTicket.fromMap(Map<String, dynamic> map) {
    return VerifiedTicket(
      boletoId: (map['id'] ?? '').toString(),
      numero: int.tryParse('${map['numero']}') ?? 0,
      estado: (map['estado'] ?? '').toString(),
      sorteoId: (map['sorteo_id'] ?? '').toString(),
      sorteoTitulo: (map['sorteo']?['titulo'] ?? map['sorteo_titulo_snapshot'] ?? '').toString(),
      buyerNombre: map['buyer_nombre'] as String?,
      buyerTelefono: map['buyer_telefono'] as String?,
      buyerCedula: map['buyer_cedula'] as String?,
      precio: map['precio_snapshot'] != null
          ? double.tryParse('${map['precio_snapshot']}')
          : null,
      soldAt: map['sold_at'] != null
          ? DateTime.tryParse(map['sold_at'].toString())
          : null,
      sorteoImagenUrl: map['sorteo']?['imagen_url'] as String?,
    );
  }
}
