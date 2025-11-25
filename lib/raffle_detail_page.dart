import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';

import 'MultisorteosPage.dart';
import 'data/models.dart';
import 'data/raffles_repository.dart';

class RaffleDetailPage extends StatefulWidget {
  final Sorteo initialSorteo;
  const RaffleDetailPage({super.key, required this.initialSorteo});

  @override
  State<RaffleDetailPage> createState() => _RaffleDetailPageState();
}

class _RaffleDetailPageState extends State<RaffleDetailPage> {
  final _repo = RafflesRepository();
  late Future<Sorteo> _sorteoFuture;
  final ScrollController _scrollController = ScrollController();

  final _nombreCtrl = TextEditingController();
  final _cedulaCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _verificadorCtrl = TextEditingController();
  final _verificadorKey = GlobalKey();

  bool _verificando = false;
  String? _verificadorMsg;
  bool? _verificadorOk;
  List<VerifiedTicket> _verifyTickets = [];

  int _cantidad = 1;
  bool _loading = false;
  String? _feedback;
  String? _imageFileName;
  Uint8List? _imageBytes;
  Map<String, String>? _selectedBank;

  // Color primario unificado (mismo azul)
  final Color primaryColor = const Color(0xFF007BFF);

  final List<Map<String, String>> _banks = [
    {'name': 'BANCO POPULAR', 'account': '781890009', 'logo': 'popular.jpg'},
    {
      'name': 'BANCO BHD LEON',
      'account': '29320070012',
      'logo': 'bancobhd.jpg',
    },
    {'name': 'BANRESERVAS', 'account': '9601984658', 'logo': 'banreservas.jpg'},
    {
      'name': 'ASOCIACION CIBAO',
      'account': '100060299157',
      'logo': 'asociacioncibao.jpg',
    },
    {'name': 'SCOTIABANK', 'account': '64400266398', 'logo': 'scoatiabank.jpg'},
    {
      'name': 'BANCO SANTA CRUZ',
      'account': '11372010010948',
      'logo': 'santacruz.jpg',
    },
  ];

  // Titular dinámico según banco
  String get _currentAccountHolder {
    if (_selectedBank?['name'] == 'BANCO BHD LEON') {
      return 'Adajet Travel, SRL';
    }
    return 'SANTO RAFAEL TEJADA';
  }

  @override
  void initState() {
    super.initState();
    _sorteoFuture = _repo.fetchRaffleDetail(widget.initialSorteo.id);
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _cedulaCtrl.dispose();
    _telefonoCtrl.dispose();
    _verificadorCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _onConfirmar(Sorteo sorteo) async {
    if (!_canConfirm()) return;
    if (_imageBytes == null || _imageFileName == null) {
      setState(() {
        _feedback = 'Adjunta el comprobante antes de confirmar.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _feedback = null;
    });

    try {
      // Tomar los siguientes numeros disponibles (orden creciente) y reservarlos
      final disponibles = await _repo.fetchNextAvailableNumbers(
        sorteo.id,
        _cantidad,
      );
      final reservados = disponibles.take(_cantidad).toList();

      if (disponibles.length < _cantidad) {
        setState(() {
          _feedback = 'No hay suficientes boletos disponibles.';
        });
        return;
      }

      final orderId = await _repo.reserveTickets(
        sorteoId: sorteo.id,
        numbers: reservados,
        nombre: _nombreCtrl.text.trim(),
        cedula: _cedulaCtrl.text.trim(),
        telefono: _telefonoCtrl.text.trim(),
      );

      if (orderId == null) {
        setState(() {
          _feedback = 'No se pudo reservar, intenta nuevamente.';
        });
        return;
      }

      await _repo.saveReservationProof(
        orderId: orderId,
        sorteoId: sorteo.id,
        buyerNombre: _nombreCtrl.text.trim(),
        buyerCedula: _cedulaCtrl.text.trim(),
        buyerTelefono: _telefonoCtrl.text.trim(),
        numeros: reservados,
        imageBytes: _imageBytes!,
        imageName: _imageFileName!,
        banco: _selectedBank?['name'],
        montoTotal: sorteo.precioTicket * _cantidad,
      );

      await _showReservationDialog();
      _goToHome();

      setState(() {
        _feedback = 'Boletos reservados! Nuestro equipo esta confirmando.';
      });
    } catch (e) {
      setState(() {
        _feedback = 'Error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _showReservationDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reserva realizada'),
          content: const Text(
            'Su ticket ha sido reservado, nuestro equipo esta confirmando. '
            'Puede verificar el estado de sus boletos utilizando su numero de telefono.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Entendido'),
            ),
          ],
        );
      },
    );
  }

  bool _canConfirm() {
    return _nombreCtrl.text.trim().isNotEmpty &&
        _cedulaCtrl.text.trim().isNotEmpty &&
        _telefonoCtrl.text.trim().isNotEmpty &&
        _selectedBank != null &&
        _imageFileName != null;
  }

  void _goToHome() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MultisorteosPage()),
      (route) => false,
    );
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        setState(() {
          _imageFileName = file.name;
          _imageBytes = file.bytes;
        });
      }
    } catch (e) {
      setState(() {
        _feedback = 'Error al seleccionar imagen: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const double headerHeight = 92;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          FutureBuilder<Sorteo>(
            future: _sorteoFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              final sorteo = snapshot.data ?? widget.initialSorteo;
              final double percent = sorteo.porcentajeVendido
                  .clamp(0, 1)
                  .toDouble();
              final currency = NumberFormat.currency(
                locale: 'es_DO',
                symbol: 'RD\$',
              );

              return Padding(
                padding: const EdgeInsets.only(top: headerHeight),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeroSection(sorteo, percent, currency),
                      const SizedBox(height: 32),

                      // Selector de cantidad
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'BOLETOS',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _counter(
                              value: _cantidad,
                              onChanged: (v) => setState(() => _cantidad = v),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Total: ${currency.format(sorteo.precioTicket * _cantidad)}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Formulario de datos personales
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.person_outline,
                                  size: 20,
                                  color: primaryColor,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'DATOS PERSONALES',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _nombreCtrl,
                              decoration: InputDecoration(
                                labelText: 'Nombre y Apellidos *',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _cedulaCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'Cédula *',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 12,
                                          ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _telefonoCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'Teléfono *',
                                      prefixText: 'DO +1 ',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 12,
                                          ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Sección de bancos
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.account_balance,
                                  size: 20,
                                  color: primaryColor,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'MODOS DE PAGO',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Elegir una opción',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildBankOptions(),
                            const SizedBox(height: 16),
                            if (_selectedBank != null) ...[
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _selectedBank!['name']!,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _selectedBank!['account']!,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.copy,
                                            size: 18,
                                          ),
                                          onPressed: () {
                                            // TODO: copiar al portapapeles si quieres
                                          },
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'TITULAR',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    Text(
                                      _currentAccountHolder,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Comprobante de pago
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.receipt_long,
                                  size: 20,
                                  color: primaryColor,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'COMPROBANTE DE PAGO',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            GestureDetector(
                              onTap: _pickImage,
                              child: Container(
                                width: double.infinity,
                                height: 150,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                    style: BorderStyle.solid,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  color: Colors.grey.shade50,
                                ),
                                child: _imageBytes == null
                                    ? Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.camera_alt_outlined,
                                            size: 40,
                                            color: Colors.grey.shade400,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Foto/Captura de tu comprobante',
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      )
                                    : Stack(
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            child: Image.memory(
                                              _imageBytes!,
                                              width: double.infinity,
                                              height: double.infinity,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                          Positioned(
                                            top: 8,
                                            right: 8,
                                            child: CircleAvatar(
                                              backgroundColor: Colors.red,
                                              radius: 16,
                                              child: IconButton(
                                                padding: EdgeInsets.zero,
                                                icon: const Icon(
                                                  Icons.close,
                                                  color: Colors.white,
                                                  size: 16,
                                                ),
                                                onPressed: () {
                                                  setState(() {
                                                    _imageBytes = null;
                                                    _imageFileName = null;
                                                  });
                                                },
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                            if (_imageFileName != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                '📎 $_imageFileName',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            if (_selectedBank != null)
                              Text(
                                '${_selectedBank!['name']}: ${currency.format(sorteo.precioTicket * _cantidad)} ($_cantidad boleto${_cantidad > 1 ? 's' : ''})',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Botón confirmar
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _canConfirm() && !_loading
                              ? () => _onConfirmar(sorteo)
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            disabledBackgroundColor: Colors.grey.shade300,
                          ),
                          child: Text(
                            _loading ? 'PROCESANDO...' : 'CONFIRMAR',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                      if (_feedback != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _feedback!,
                          style: TextStyle(
                            color: _feedback!.toLowerCase().contains('error')
                                ? Colors.red
                                : Colors.green.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 30),
                      _buildInlineVerifier(),
                    ],
                  ),
                ),
              );
            },
          ),
          Positioned(top: 0, left: 0, right: 0, child: _buildHeader()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Image.asset('assets/imagenes/logo_completo.png', height: 64),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _menuItem("Inicio", _goHome),
                  _menuItem("Verificador", _scrollToVerifier),
                  _menuItem("Contacto", _goHome),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.blueGrey.shade700,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _scrollToVerifier() {
    if (_verificadorKey.currentContext != null) {
      Scrollable.ensureVisible(
        _verificadorKey.currentContext!,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    }
  }

  // ================= VERIFICADOR INLINE =================
  Widget _buildInlineVerifier() {
    return Container(
      key: _verificadorKey,
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Verificador de boletos",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _verificadorCtrl,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _buscarEnDetalle(),
            decoration: InputDecoration(
              hintText: "Número de teléfono o #Boleto",
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: primaryColor, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _verificando ? null : _buscarEnDetalle,
              icon: const Icon(Icons.search, color: Colors.white),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              label: Text(
                _verificando ? "Buscando..." : "Buscar",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          if (_verificadorMsg != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  _verificadorOk == true
                      ? Icons.check_circle
                      : Icons.error_outline,
                  color: _verificadorOk == true ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _verificadorMsg!,
                    style: TextStyle(
                      color: _verificadorOk == true
                          ? Colors.green.shade800
                          : Colors.red.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_verifyTickets.isNotEmpty) ...[
            const SizedBox(height: 16),
            ..._verifyTickets.map(
              (t) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _inlineTicketTile(t),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _inlineTicketTile(VerifiedTicket t) {
    final sanitized = _verificadorCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    final isShort = sanitized.length < 5;
    final showFull = !isShort;
    final bool isReserved = t.estado.toLowerCase() == 'reserved';
    final statusLabel = isReserved ? "Reservado" : "Pago verificado";
    final statusColor = isReserved
        ? const Color(0xFFF59E0B)
        : const Color(0xFF16A34A);

    String maskName(String name) {
      final parts = name.split(" ");
      if (parts.length <= 2) return "${parts.first} ****";
      return "${parts[0]} ${parts[1]} **** ****";
    }

    String maskPhone(String phone) {
      if (phone.length <= 5) return phone;
      final keepStart = phone.substring(0, 3);
      final keepEnd = phone.substring(phone.length - 2);
      final middle = "*" * (phone.length - 5);
      return "$keepStart-$middle-$keepEnd";
    }

    final displayName = showFull
        ? (t.buyerNombre ?? "Cliente")
        : (t.buyerNombre != null ? maskName(t.buyerNombre!) : "Cliente");
    final displayPhone = showFull
        ? (t.buyerTelefono ?? "***")
        : (t.buyerTelefono != null ? maskPhone(t.buyerTelefono!) : "***");

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.qr_code, color: primaryColor, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Boleto ${t.numero.toString().padLeft(4, '0')}",
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusLabel.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
                Text(
                  t.sorteoTitulo,
                  style: const TextStyle(color: Colors.black54),
                ),
                if (t.buyerNombre != null && t.buyerNombre!.isNotEmpty)
                  Text(
                    displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                if (t.buyerTelefono != null && t.buyerTelefono!.isNotEmpty)
                  Text(displayPhone),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _buscarEnDetalle() async {
    final input = _verificadorCtrl.text.trim();
    if (input.isEmpty) return;
    final sanitized = input.replaceAll(RegExp(r'[^0-9]'), '');
    final isShort = sanitized.length < 5;

    setState(() {
      _verificando = true;
      _verificadorOk = null;
      _verificadorMsg = null;
      _verifyTickets = [];
    });

    try {
      final tickets = await _repo.verifyTickets(
        input,
        searchNumberExact: isShort,
        searchPhoneOnly: !isShort,
        sorteoId: widget.initialSorteo.id,
      );
      if (tickets.isEmpty) {
        setState(() {
          _verificadorOk = false;
          _verificadorMsg = "No encontramos boletos con ese dato.";
        });
      } else {
        setState(() {
          _verifyTickets = tickets;
          _verificadorOk = true;
          _verificadorMsg =
              "Encontramos ${tickets.length} boleto${tickets.length > 1 ? 's' : ''}.";
        });
      }
    } catch (e) {
      setState(() {
        _verificadorOk = false;
        _verificadorMsg = "Error al verificar: $e";
      });
    } finally {
      if (mounted) {
        setState(() {
          _verificando = false;
        });
      }
    }
  }

  Widget _counter({required int value, required ValueChanged<int> onChanged}) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: value > 1 ? () => onChanged(value - 1) : null,
            icon: Icon(
              Icons.remove_circle_outline,
              color: value > 1 ? Colors.black : Colors.grey,
              size: 32,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              value.toString(),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24),
            ),
          ),
          IconButton(
            onPressed: () => onChanged(value + 1),
            icon: const Icon(
              Icons.add_circle_outline,
              color: Colors.black,
              size: 32,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBankOptions() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: _banks.map((bank) {
        final isSelected = _selectedBank == bank;
        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedBank = bank;
            });
          },
          child: Container(
            width: 90,
            height: 70,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? primaryColor : Colors.grey.shade300,
                width: isSelected ? 3 : 1.5,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : [],
            ),
            child: Image.asset(
              'assets/imagenes/${bank['logo']}',
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.account_balance,
                      size: 30,
                      color: isSelected ? primaryColor : Colors.grey.shade600,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bank['name']!.split(' ').first,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? primaryColor : Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                );
              },
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: primaryColor,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      height: 260,
      color: Colors.grey.shade200,
      child: const Center(
        child: Icon(Icons.image_not_supported_outlined, size: 40),
      ),
    );
  }

  Widget _buildHeroSection(
    Sorteo sorteo,
    double percent,
    NumberFormat currency,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 3 / 5,
                child: sorteo.imagenUrl != null
                    ? Image.network(
                        sorteo.imagenUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder(),
                      )
                    : _placeholder(),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _infoBadge(
                      Icons.attach_money,
                      "${currency.format(sorteo.precioTicket)} por boleto",
                    ),
                    if (sorteo.fechaSorteo != null)
                      _infoBadge(
                        Icons.event_available,
                        "Fecha: ${DateFormat('dd/MM/yyyy').format(sorteo.fechaSorteo!)}",
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  sorteo.titulo,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  sorteo.descripcion ?? 'Sin descripción disponible.',
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(
                      '${(percent * 100).toStringAsFixed(2)}% vendido',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.black87,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: percent,
                    minHeight: 12,
                    backgroundColor: Colors.grey.shade200,
                    color: Colors.green.shade600,
                  ),
                ),
                const SizedBox(height: 18),
                _buildPrizeListInline(sorteo),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBadge(IconData icon, String text, {bool compact = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: primaryColor),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: primaryColor,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 12 : 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrizeListInline(Sorteo sorteo) {
    if (sorteo.premios.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.emoji_events_outlined, color: Colors.grey),
            SizedBox(width: 8),
            Text(
              "Próximamente premios",
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Premios",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        ...sorteo.premios.map((p) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF7FAFD),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      p.posicion.toString(),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: primaryColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.titulo,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      if (p.descripcion != null &&
                          p.descripcion!.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            p.descripcion!,
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 13,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
