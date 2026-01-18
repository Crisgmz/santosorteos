import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
  final _apellidoCtrl = TextEditingController();
  final _cedulaCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  int _cantidad = 1;
  bool _loading = false;
  String? _feedback;
  String? _imageFileName;
  Uint8List? _imageBytes;
  Map<String, String>? _selectedBank;

  // Color primario unificado (mismo azul)
  // Color primario unificado alineado con MultisorteosPage
  final Color primaryColor = kPrimaryColor;

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
    {
      'name': 'TARJETA DE CRÉDITO (LINK DE PAGO)',
      'account': 'Solicitar Link',
      'logo': 'card_payment.jpg',
    },
    {
      'name': 'Qik Banco Digital Dominicano',
      'account': '1000614498',
      'logo': 'Qik-logo.jpg',
    },
  ];

  // Titular dinámico según banco
  String get _currentAccountHolder {
    if (_selectedBank?['name'] == 'BANCO BHD LEON') {
      return 'Adajet Travel, SRL';
    }
    if (_selectedBank?['name'] == 'TARJETA DE CRÉDITO (LINK DE PAGO)') {
      return 'Solicitud vía WhatsApp';
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
    _apellidoCtrl.dispose();
    _cedulaCtrl.dispose();
    _telefonoCtrl.dispose();
    _emailCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _onConfirmar(Sorteo sorteo) async {
    if (!_canConfirm()) return;

    // Si NO es tarjeta de crédito (link de pago), exigimos la imagen
    final isLinkPayment =
        _selectedBank?['name'] == 'TARJETA DE CRÉDITO (LINK DE PAGO)';
    if (!isLinkPayment && (_imageBytes == null || _imageFileName == null)) {
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

      final buyerName =
          '${_nombreCtrl.text.trim()} ${_apellidoCtrl.text.trim()}';
      final buyerPhone = _telefonoCtrl.text.trim();
      final buyerId = _cedulaCtrl.text.trim();
      final buyerEmail = _emailCtrl.text.trim().isNotEmpty
          ? _emailCtrl.text.trim()
          : null;

      final orderId = await _repo.reserveTickets(
        sorteoId: sorteo.id,
        numbers: reservados,
        nombre: buyerName,
        cedula: buyerId,
        telefono: buyerPhone,
        email: buyerEmail,
      );

      if (orderId == null) {
        setState(() {
          _feedback = 'No se pudo reservar, intenta nuevamente.';
        });
        return;
      }

      final int paidTickets = _calculatePaidTickets(sorteo, _cantidad);
      final double totalAmount = sorteo.precioTicket * paidTickets;
      final int freeTickets = _cantidad - paidTickets;

      await _repo.saveReservationProof(
        orderId: orderId,
        sorteoId: sorteo.id,
        buyerNombre: buyerName,
        buyerCedula: buyerId,
        buyerTelefono: buyerPhone,
        numeros: reservados,
        imageBytes: _imageBytes,
        imageName: _imageFileName,
        banco: _selectedBank?['name'],
        montoTotal: totalAmount,
        email: buyerEmail,
      );

      // Disparar envío de correo al script PHP (si hay email)
      if (buyerEmail != null) {
        _repo.triggerEmailPhp(
          email: buyerEmail,
          nombre: buyerName,
          ticketId: "Orden-$orderId",
        );
      }

      if (isLinkPayment) {
        // Enviar a WhatsApp con formato solicitado
        String boletosText = "$_cantidad";
        if (freeTickets > 0) {
          boletosText += " ($paidTickets pagados + $freeTickets gratis)";
        }

        final message =
            "Hola! Quiero completar mi reserva:\n\n"
            "📋 *Reserva:* $orderId\n"
            "🎁 *Sorteo:* ${sorteo.titulo}\n"
            "🎫 *Boletos:* $boletosText\n"
            "💰 *Total:* RD\$${totalAmount.toStringAsFixed(0)}\n"
            "👤 *Nombre:* $buyerName\n"
            "📱 *Teléfono:* $buyerPhone";

        final encoded = Uri.encodeComponent(message);
        final whatsappUrl = "https://wa.me/18496285498?text=$encoded";

        if (await canLaunchUrl(Uri.parse(whatsappUrl))) {
          await launchUrl(
            Uri.parse(whatsappUrl),
            mode: LaunchMode.externalApplication,
          );
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No se pudo abrir WhatsApp automáticamente.'),
              ),
            );
          }
        }
      }

      await _showReservationDialog();
      _goToHome(search: buyerPhone);

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

    // Generar el link con el número de teléfono limpio (solo dígitos si es necesario, pero aquí usamos input directo)
    // El formato solicitado es: multisorteos.com/verificador/ + telefono
    // Asumimos que se desea incluir https:// para que sea un link válido
    final phone = _telefonoCtrl.text.trim();
    final link = 'https://multisorteos.com/?phone=$phone';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 28),
              const SizedBox(width: 10),
              const Text('Reserva realizada'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Su ticket ha sido reservado, nuestro equipo esta confirmando.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              const Text(
                'Puede verificar el estado de sus boletos en el siguiente enlace:',
                style: TextStyle(fontSize: 14, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        link,
                        style: TextStyle(
                          color: primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 20),
                      color: Colors.grey.shade700,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: link));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Enlace copiado al portapapeles'),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Entendido',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  bool _canConfirm() {
    final basic =
        _nombreCtrl.text.trim().isNotEmpty &&
        _apellidoCtrl.text.trim().isNotEmpty &&
        _cedulaCtrl.text.trim().isNotEmpty &&
        _telefonoCtrl.text.trim().isNotEmpty;

    if (_selectedBank?['name'] == 'TARJETA DE CRÉDITO (LINK DE PAGO)') {
      return basic;
    }

    return basic && _imageFileName != null;
    // Banco es opcional, pero comprobante es obligatorio (salvo Link de Pago)
  }

  void _goToHome({String? search}) {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => MultisorteosPage(initialSearch: search),
      ),
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
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeroSection(sorteo, percent, currency),
                          const SizedBox(height: 32),

                          if (sorteo.fechaSorteo != null &&
                              sorteo.fechaSorteo!.isBefore(DateTime.now()))
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.event_busy,
                                    size: 48,
                                    color: Colors.red.shade400,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    "SORTEO FINALIZADO",
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.red.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    "Este sorteo ya ha concluido. No se pueden adquirir más boletos.",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  ElevatedButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red.shade600,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 32,
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text(
                                      "Volver al inicio",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else ...[
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
                                    'Selecciona la Cantidad de Boletos',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      fontFamily: 'Roboto',
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  _counter(
                                    value: _cantidad,
                                    onChanged: (v) =>
                                        setState(() => _cantidad = v),
                                  ),
                                  const SizedBox(height: 8),
                                  const SizedBox(height: 8),
                                  _buildPriceDisplay(sorteo, currency),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Formulario de datos personales
                            // Formulario de datos personales (Refactorizado con Estilo Premium)
                            _buildResponsiveForm(),
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
                                        'MODOS DE PAGO (Opcional)',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Elegir una opción (si aplica)',
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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

                            // Comprobante de pago (Ocultar si es tarjeta de crédito/link de pago)
                            if (_selectedBank?['name'] !=
                                'TARJETA DE CRÉDITO (LINK DE PAGO)')
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.grey.shade200,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.04,
                                      ),
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
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
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
                                                      color:
                                                          Colors.grey.shade600,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ],
                                              )
                                            : Stack(
                                                children: [
                                                  ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
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
                                                      backgroundColor:
                                                          Colors.red,
                                                      radius: 16,
                                                      child: IconButton(
                                                        padding:
                                                            EdgeInsets.zero,
                                                        icon: const Icon(
                                                          Icons.close,
                                                          color: Colors.white,
                                                          size: 16,
                                                        ),
                                                        onPressed: () {
                                                          setState(() {
                                                            _imageBytes = null;
                                                            _imageFileName =
                                                                null;
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
                                        '${_selectedBank!['name']}: ${currency.format(sorteo.precioTicket * _calculatePaidTickets(sorteo, _cantidad))} ($_cantidad boletos)',
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
                                  backgroundColor: kPrimaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  elevation: 10,
                                  shadowColor: kGoldColor.withValues(
                                    alpha: 0.4,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(
                                      color: kGoldColor.withValues(alpha: 0.5),
                                      width: 1,
                                    ),
                                  ),
                                  disabledBackgroundColor: Colors.grey.shade300,
                                ),
                                child: Text(
                                  _loading
                                      ? 'PROCESANDO...'
                                      : '✓ CONFIRMAR RESERVA',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Center(
                              child: Text(
                                "ℹ️ Al confirmar recibirás un número de reserva único",
                                style: TextStyle(
                                  color: Colors.black54,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            if (_feedback != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                _feedback!,
                                style: TextStyle(
                                  color:
                                      _feedback!.toLowerCase().contains('error')
                                      ? Colors.red
                                      : Colors.green.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
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
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: SafeArea(
              bottom: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 600;

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Logo con tamaño responsive
                      Expanded(
                        child: Image.asset(
                          'assets/imagenes/logo_completo.png',
                          height: isMobile ? 48 : 64,
                          alignment: Alignment.centerLeft,
                        ),
                      ),

                      // Menú simplificado para móvil
                      if (isMobile)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.home,
                                color: primaryColor,
                                size: 28,
                              ),
                              onPressed: _goHome,
                              tooltip: 'Inicio',
                            ),
                          ],
                        )
                      else
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _menuItem("Inicio", _goHome),
                              _menuItem("Contacto", _goHome),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
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

  Widget _counter({required int value, required ValueChanged<int> onChanged}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: value > 1 ? () => onChanged(value - 1) : null,
            icon: Icon(
              Icons.remove,
              color: value > 1 ? Colors.black87 : Colors.grey.shade300,
              size: 24,
            ),
          ),
          Container(
            width: 100,
            alignment: Alignment.center,
            child: Text(
              "$value Boleto${value > 1 ? 's' : ''}",
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
          IconButton(
            onPressed: () => onChanged(value + 1),
            icon: const Icon(Icons.add, color: Colors.black87, size: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildBankOptions() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 500;
        final logoSize = isMobile ? 100.0 : 90.0;
        final logoHeight = isMobile ? 80.0 : 70.0;

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
                width: logoSize,
                height: logoHeight,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? kGoldColor : Colors.grey.shade300,
                    width: isSelected ? 3 : 1.5,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: kGoldColor.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
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
                          size: isMobile ? 35 : 30,
                          color: isSelected
                              ? primaryColor
                              : Colors.grey.shade600,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          bank['name']!.split(' ').first,
                          style: TextStyle(
                            fontSize: isMobile ? 10 : 9,
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
      },
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
    return SizedBox(
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 900;
          final isFinished =
              sorteo.fechaSorteo != null &&
              sorteo.fechaSorteo!.isBefore(DateTime.now());

          // 🖼️ Columna Izquierda: Imagen + Badges
          final imageWidget = Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.blue.shade50, Colors.white],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      AspectRatio(
                        aspectRatio: 1, // Cuadrado
                        child: sorteo.imagenUrl != null
                            ? CachedNetworkImage(
                                imageUrl: sorteo.imagenUrl!,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => _placeholder(),
                                errorWidget: (context, url, error) =>
                                    _placeholder(),
                              )
                            : _placeholder(),
                      ),
                      if (sorteo.hasPromo)
                        Positioned(
                          top: 10,
                          left: 10,
                          child: _promotionBadge(sorteo),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    _trustBadge(Icons.verified_user, "100% Seguro"),
                    _trustBadge(Icons.local_shipping, "Entrega Garantizada"),
                    _trustBadge(Icons.star, "Verificado"),
                  ],
                ),
              ],
            ),
          );

          // 📝 Columna Derecha: Info
          final infoWidget = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Badge de Estado
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isFinished
                      ? Colors.red.shade100
                      : Colors.green.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isFinished ? Colors.red : Colors.green,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isFinished ? Icons.error_outline : Icons.check_circle,
                      size: 16,
                      color: isFinished ? Colors.red : Colors.green[700],
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isFinished ? "SORTEO FINALIZADO" : "SORTEO ACTIVO",
                      style: TextStyle(
                        color: isFinished ? Colors.red : Colors.green[800],
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                sorteo.titulo,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111827),
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                sorteo.descripcion ?? '',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),

              // Grid Informativo
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _infoItem(
                        "💰 Precio por boleto",
                        currency.format(sorteo.precioTicket),
                        isPrimary: true,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.grey.shade300,
                    ),
                    Expanded(
                      child: _infoItem(
                        "📅 Fecha del sorteo",
                        sorteo.fechaSorteo != null
                            ? DateFormat(
                                'dd MMM yyyy',
                                'es',
                              ).format(sorteo.fechaSorteo!)
                            : "Al vender el 100%",
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              // Barra de progreso
              if (!isFinished)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Progreso de venta",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        Text(
                          "${(percent * 100).toStringAsFixed(0)}%",
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: kPrimaryColor,
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
                        // Glow effect simulated by color
                        color: percent > 0.7 ? kGoldColor : kPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Boletos limitados, ¡no te quedes sin el tuyo!",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 32),
              // Lista de Premios
              Container(
                decoration: BoxDecoration(
                  color: kGoldColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kGoldColor.withValues(alpha: 0.3)),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.emoji_events, color: kGoldColor),
                        const SizedBox(width: 8),
                        const Text(
                          "Premios del Sorteo",
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: Color(0xFFB8860B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (sorteo.premios.isEmpty)
                      const Text(
                        "Premios espectaculares",
                        style: TextStyle(color: Colors.black54),
                      ),
                    ...sorteo.premios.map(
                      (p) => Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: kGoldColor),
                              ),
                              child: Text(
                                "${p.posicion}",
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                p.titulo,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          if (isMobile) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [imageWidget, const SizedBox(height: 32), infoWidget],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: imageWidget),
              const SizedBox(width: 40),
              Expanded(flex: 3, child: infoWidget),
            ],
          );
        },
      ),
    );
  }

  Widget _trustBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.green),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoItem(String label, String value, {bool isPrimary = false}) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: isPrimary ? kPrimaryColor : Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildResponsiveForm() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kPrimaryColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.person_outline,
                  size: 24,
                  color: kPrimaryColor,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'DATOS PERSONALES',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: kPrimaryColor,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;
              return Column(
                children: [
                  if (isMobile) ...[
                    _buildTextField(_nombreCtrl, 'Nombre', Icons.person),
                    const SizedBox(height: 16),
                    _buildTextField(
                      _apellidoCtrl,
                      'Apellido',
                      Icons.person_outline,
                    ),
                  ] else
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            _nombreCtrl,
                            'Nombre',
                            Icons.person,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            _apellidoCtrl,
                            'Apellido',
                            Icons.person_outline,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  if (isMobile) ...[
                    _buildTextField(_cedulaCtrl, 'Cédula', Icons.badge),
                    const SizedBox(height: 16),
                    _buildTextField(
                      _telefonoCtrl,
                      'Teléfono',
                      Icons.phone,
                      prefix: 'DO +1 ',
                    ),
                  ] else
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            _cedulaCtrl,
                            'Cédula',
                            Icons.badge,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            _telefonoCtrl,
                            'Teléfono',
                            Icons.phone,
                            prefix: 'DO +1 ',
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    _emailCtrl,
                    'Email (Opcional)',
                    Icons.email_outlined,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "El email es opcional, pero si lo introduces recibirás una confirmación de tu compra por correo.",
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue.shade900,
                              height: 1.3,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    String? prefix,
  }) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(fontWeight: FontWeight.w700, color: kPrimaryColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: Colors.blueGrey.shade400,
          fontWeight: FontWeight.w600,
        ),
        prefixText: prefix,
        prefixStyle: const TextStyle(
          color: kPrimaryColor,
          fontWeight: FontWeight.w700,
        ),
        prefixIcon: Icon(
          icon,
          color: kGoldColor.withValues(alpha: 0.8),
          size: 22,
        ),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: kGoldColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
      ),
    );
  }

  Widget _buildPriceDisplay(Sorteo sorteo, NumberFormat currency) {
    // Si no hay promo, se muestra normal
    if (!sorteo.hasPromo) {
      return Text(
        'Total: ${currency.format(sorteo.precioTicket * _cantidad)}',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      );
    }

    // Calculo con la funcion de bloques
    final int paidTickets = _calculatePaidTickets(sorteo, _cantidad);
    final int freeTickets = _cantidad - paidTickets;
    final double totalAmount = sorteo.precioTicket * paidTickets;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center, // Centrado bajo el counter
      children: [
        Text(
          'Total: ${currency.format(totalAmount)}',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: Color(0xFF111827),
          ),
        ),
        if (freeTickets > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              '($paidTickets pagados + $freeTickets gratis)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.green.shade700,
              ),
            ),
          ),
      ],
    );
  }

  int _calculatePaidTickets(Sorteo sorteo, int cantidadTotal) {
    if (!sorteo.hasPromo || cantidadTotal <= 0) {
      return cantidadTotal;
    }

    // Regla: Buy X Get Y Free -> BlockSize = X + Y
    final int buy = sorteo.promoBuy;
    final int get = sorteo.promoGet;
    final int blockSize = buy + get;

    if (blockSize <= 0) return cantidadTotal;

    // Cuantos bloques completos de oferta hay en la selección?
    final int sets = (cantidadTotal / blockSize).floor();

    // Tickets sueltos que sobran fuera de los bloques completos
    final int remainder = cantidadTotal % blockSize;

    // De los sueltos, el cliente paga hasta completar la parte 'buy'
    // Si sobran más, esos son gratis (parte del 'get' incompleto)
    final int paidRemainder = (remainder < buy) ? remainder : buy;

    // Total de tickets que realmente se cobran
    final int totalPaidCount = (sets * buy) + paidRemainder;

    return totalPaidCount;
  }

  Widget _promotionBadge(Sorteo sorteo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFCC00), // Dorado brillante
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.flash_on, color: Colors.red, size: 16),
          const SizedBox(width: 4),
          Text(
            "OFERTA: PAGA ${sorteo.promoBuy} Y RECIBE ${sorteo.promoGet} GRATIS",
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
