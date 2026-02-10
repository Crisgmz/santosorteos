import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'ticket_image_saver_stub.dart'
    if (dart.library.html) 'ticket_image_saver_web.dart'
    if (dart.library.io) 'ticket_image_saver_io.dart'
    as ticket_saver;

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
  final GlobalKey _verificadorSectionKey = GlobalKey();

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

  // Verificador de boletos
  final _verificadorCtrl = TextEditingController();
  bool _verificando = false;
  String? _verificadorMsg;
  bool? _verificadorOk;
  List<VerifiedTicket> _tickets = [];
  bool _busquedaNumeroExacta = false;
  final Map<String, GlobalKey> _ticketKeys = {};

  // Image gallery state
  int _currentImageIndex = 0;
  Timer? _autoScrollTimer;

  // Ticket selection state
  final Set<int> _selectedTickets = {};
  final Set<int> _soldTicketNumbers = {};
  int _ticketsToShow = 100; // Show 100 tickets at a time

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
    _loadSoldTickets();
  }

  Future<void> _loadSoldTickets() async {
    try {
      final soldNumbers = await _repo.fetchSoldTicketNumbers(
        widget.initialSorteo.id,
      );
      setState(() {
        _soldTicketNumbers.clear();
        _soldTicketNumbers.addAll(soldNumbers);
      });
    } catch (e) {
      print('Error loading sold tickets: $e');
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _nombreCtrl.dispose();
    _apellidoCtrl.dispose();
    _cedulaCtrl.dispose();
    _telefonoCtrl.dispose();
    _emailCtrl.dispose();
    _verificadorCtrl.dispose();
    _autoScrollTimer?.cancel(); // Cancel the timer
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

      final publicUrl = await _repo.saveReservationProof(
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

      if (buyerEmail != null) {
        _repo.triggerEmailPhp(
          email: buyerEmail,
          nombre: buyerName,
          boletos: reservados,
          comprobanteUrl: publicUrl,
          telefono: buyerPhone,
          nombreSorteo: sorteo.titulo,
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
        _feedback = 'Boletos reservados! Nuestro equipo está confirmando.';
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
                'Su ticket ha sido reservado, nuestro equipo está confirmando.',
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
                          const SizedBox(height: 40),
                          _buildVerificador(sorteo),
                          const SizedBox(height: 60),
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
                            IconButton(
                              icon: Icon(
                                Icons.verified,
                                color: primaryColor,
                                size: 28,
                              ),
                              onPressed: _scrollToVerificador,
                              tooltip: 'Verificador',
                            ),
                          ],
                        )
                      else
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _menuItem("Inicio", _goHome),
                              _menuItem("Verificador", _scrollToVerificador),
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

  void _scrollToVerificador() {
    final context = _verificadorSectionKey.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOutCubic,
      alignment: 0.05,
    );
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

  Widget _buildHeroSection(
    Sorteo sorteo,
    double percent,
    NumberFormat currency,
  ) {
    // Prepare image list from sorteo.imagenes
    final imageList = sorteo.imagenes
        .where((img) => img.trim().isNotEmpty)
        .toList();
    final hasMultipleImages = imageList.length > 1;

    // Ensure current index is valid
    if (_currentImageIndex >= imageList.length && imageList.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _currentImageIndex = 0;
          });
        }
      });
    }

    final isFinished =
        sorteo.fechaSorteo != null &&
        sorteo.fechaSorteo!.isBefore(DateTime.now());

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 900;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Gallery + Title/Description
            if (isMobile) ...[
              // Mobile: Stack vertically
              _buildImageGalery(
                sorteo,
                imageList,
                hasMultipleImages,
                isFinished,
              ),
              const SizedBox(height: 16),
              // Info cards below gallery (mobile)
              _buildInfoCards(sorteo, currency),
              const SizedBox(height: 24),
              _buildTitleDescriptionSection(sorteo, isFinished),
            ] else
              // Desktop: Side by side
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: Gallery + Info Cards
                  Expanded(
                    flex: 5,
                    child: Column(
                      children: [
                        _buildImageGalery(
                          sorteo,
                          imageList,
                          hasMultipleImages,
                          isFinished,
                        ),
                        const SizedBox(height: 16),
                        _buildInfoCards(sorteo, currency),
                      ],
                    ),
                  ),
                  const SizedBox(width: 32),
                  // Right: Title + Description
                  Expanded(
                    flex: 5,
                    child: _buildTitleDescriptionSection(sorteo, isFinished),
                  ),
                ],
              ),

            const SizedBox(height: 32),

            // Progress bar
            if (!isFinished) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Progreso de venta',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  Text(
                    '${(percent * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 18,
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
                  minHeight: 10,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    percent > 0.7 ? kGoldColor : kPrimaryColor,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Boletos limitados, no te quedes sin el tuyo.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 32),
            ],

            // Prizes section (separate card)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: kGoldColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kGoldColor.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.emoji_events,
                        color: kGoldColor,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '🏆 Premios:',
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
                      'Premios espectaculares',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ...sorteo.premios.map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getPrizeEmoji(p.posicion),
                            style: const TextStyle(fontSize: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _getPrizeLabel(p.posicion),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '👉 ${p.titulo}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Quantity selector section FIRST
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Empty spacer for balance
                      const SizedBox(width: 120),
                      // Centered text
                      const Expanded(
                        child: Text(
                          'Selecciona la Cantidad de Boletos',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ),
                      // Random selection button (or spacer if not showing numbers)
                      if (sorteo.mostrarNumeros)
                        OutlinedButton.icon(
                          onPressed: _cantidad > 0
                              ? () => _selectRandomTickets(sorteo)
                              : null,
                          icon: const Icon(Icons.casino, size: 18),
                          label: const Text('Elegir al azar'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kPrimaryColor,
                            side: BorderSide(
                              color: kPrimaryColor.withOpacity(0.5),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: 120),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _counter(
                    value: _cantidad,
                    onChanged: (v) => setState(() => _cantidad = v),
                  ),
                  const SizedBox(height: 8),
                  const SizedBox(height: 8),
                  _buildPriceDisplay(sorteo, currency),
                ],
              ),
            ),

            // Ticket selection grid BELOW (only if mostrarNumeros is true)
            if (sorteo.mostrarNumeros) ...[
              const SizedBox(height: 24),
              _buildTicketSelectionGrid(sorteo),
            ],
          ],
        );
      },
    );
  }

  // Info cards widget (Price and Date)
  Widget _buildInfoCards(Sorteo sorteo, NumberFormat currency) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _infoItem(
              '💰 Precio por boleto',
              currency.format(sorteo.precioTicket),
              isPrimary: true,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: Colors.grey.shade300,
            margin: const EdgeInsets.symmetric(horizontal: 20),
          ),
          Expanded(
            child: _infoItem(
              '📅 Fecha del evento',
              sorteo.fechaSorteo != null
                  ? DateFormat('dd MMM yyyy', 'es').format(sorteo.fechaSorteo!)
                  : 'Al vender el 100%',
            ),
          ),
        ],
      ),
    );
  }

  // Title and Description section
  Widget _buildTitleDescriptionSection(Sorteo sorteo, bool isFinished) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isFinished ? Colors.red.shade50 : Colors.green.shade50,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isFinished ? Colors.red.shade300 : Colors.green.shade300,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isFinished ? Icons.cancel : Icons.check_circle,
                size: 18,
                color: isFinished ? Colors.red.shade700 : Colors.green.shade700,
              ),
              const SizedBox(width: 8),
              Text(
                isFinished ? 'EVENTO FINALIZADO' : 'EVENTO ACTIVO',
                style: TextStyle(
                  color: isFinished
                      ? Colors.red.shade700
                      : Colors.green.shade700,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Title
        Text(
          sorteo.titulo,
          style: const TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
            height: 1.1,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 24),

        // Description card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.description, color: kPrimaryColor, size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    'Descripcion',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (sorteo.descripcion != null && sorteo.descripcion!.isNotEmpty)
                Text(
                  sorteo.descripcion!,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey.shade700,
                    height: 1.6,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _getPrizeEmoji(int position) {
    switch (position) {
      case 1:
        return '🥇';
      case 2:
        return '🥈';
      case 3:
        return '🥉';
      default:
        return '🎁';
    }
  }

  String _getPrizeLabel(int position) {
    switch (position) {
      case 1:
        return 'Primer Premio:';
      case 2:
        return 'Segundo Premio:';
      case 3:
        return 'Tercer Premio:';
      default:
        return 'Premio ${position}:';
    }
  }

  // Image gallery with thumbnails
  Widget _buildImageGalery(
    Sorteo sorteo,
    List<String> imageList,
    bool hasMultipleImages,
    bool isFinished,
  ) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: kGoldColor.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(width: 3, color: kGoldColor),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(4),
          child: Column(
            children: [
              // Main image
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 1.2,
                  child: Stack(
                    children: [
                      // Image carousel
                      if (imageList.isNotEmpty)
                        GestureDetector(
                          onHorizontalDragEnd: !hasMultipleImages
                              ? null
                              : (details) {
                                  if (details.primaryVelocity! > 0) {
                                    setState(() {
                                      _currentImageIndex =
                                          (_currentImageIndex -
                                              1 +
                                              imageList.length) %
                                          imageList.length;
                                    });
                                  } else if (details.primaryVelocity! < 0) {
                                    setState(() {
                                      _currentImageIndex =
                                          (_currentImageIndex + 1) %
                                          imageList.length;
                                    });
                                  }
                                },
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 400),
                            child: CachedNetworkImage(
                              key: ValueKey<String>(
                                'img_${imageList[_currentImageIndex]}',
                              ),
                              imageUrl: imageList[_currentImageIndex],
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              placeholder: (context, url) => Container(
                                color: Colors.grey.shade800,
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    color: kGoldColor,
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: Colors.grey.shade800,
                                child: Icon(
                                  Icons.broken_image,
                                  size: 60,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          color: Colors.grey.shade800,
                          child: const Center(
                            child: Icon(
                              Icons.image_not_supported,
                              size: 60,
                              color: Colors.grey,
                            ),
                          ),
                        ),

                      // Promotion badge
                      if (sorteo.hasPromo)
                        Positioned(
                          top: 12,
                          left: 12,
                          child: _promotionBadge(sorteo),
                        ),

                      // Navigation arrows
                      if (hasMultipleImages) ...[
                        Positioned(
                          left: 12,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _currentImageIndex =
                                        (_currentImageIndex -
                                            1 +
                                            imageList.length) %
                                        imageList.length;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.6),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.chevron_left,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 12,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _currentImageIndex =
                                        (_currentImageIndex + 1) %
                                        imageList.length;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.6),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.chevron_right,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Counter indicator
                        Positioned(
                          bottom: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: kGoldColor, width: 1),
                            ),
                            child: Text(
                              '${_currentImageIndex + 1}/${imageList.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Thumbnails
              if (hasMultipleImages) ...[
                const SizedBox(height: 8),
                Container(
                  height: 80,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: imageList.length,
                    itemBuilder: (context, index) {
                      final isSelected = index == _currentImageIndex;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _currentImageIndex = index;
                          });
                        },
                        child: Container(
                          width: 80,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? kGoldColor
                                  : Colors.grey.shade600,
                              width: isSelected ? 3 : 1.5,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: kGoldColor.withOpacity(0.5),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ]
                                : [],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: imageList[index],
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Colors.grey.shade800,
                                child: const Center(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: kGoldColor,
                                    ),
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: Colors.grey.shade800,
                                child: Icon(
                                  Icons.broken_image,
                                  size: 24,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }

  //  Event information section
  Widget _buildEventInfo(
    Sorteo sorteo,
    double percent,
    NumberFormat currency,
    bool isFinished,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isFinished ? Colors.red.shade50 : Colors.green.shade50,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isFinished ? Colors.red.shade300 : Colors.green.shade300,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isFinished ? Icons.cancel : Icons.check_circle,
                size: 18,
                color: isFinished ? Colors.red.shade700 : Colors.green.shade700,
              ),
              const SizedBox(width: 8),
              Text(
                isFinished ? 'Evento finalizado' : '● Evento activo',
                style: TextStyle(
                  color: isFinished
                      ? Colors.red.shade700
                      : Colors.green.shade700,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Title
        Text(
          sorteo.titulo,
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
            height: 1.2,
          ),
        ),
        const SizedBox(height: 12),

        // Description
        if (sorteo.descripcion != null && sorteo.descripcion!.isNotEmpty)
          Text(
            sorteo.descripcion!,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade700,
              height: 1.6,
            ),
          ),
        const SizedBox(height: 24),

        // Info cards grid
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _infoCard(
              icon: Icons.calendar_today,
              label: 'Fecha',
              value: sorteo.fechaSorteo != null
                  ? DateFormat(
                      'EEEE, dd \'De\'\nMMM \'De\' yyyy',
                      'es',
                    ).format(sorteo.fechaSorteo!)
                  : 'Al vender\nel 100%',
            ),
            _infoCard(
              icon: Icons.access_time,
              label: 'Hora',
              value: sorteo.fechaSorteo != null
                  ? DateFormat(
                      'HH:mm \'Hrs\'',
                      'es',
                    ).format(sorteo.fechaSorteo!)
                  : 'TBD',
            ),
            _infoCard(
              icon: Icons.confirmation_number,
              label: 'Disponibles',
              value:
                  '${sorteo.totalTickets - sorteo.soldTickets} De ${sorteo.totalTickets}',
            ),
            _infoCard(
              icon: Icons.people,
              label: 'Participantes',
              value: '${sorteo.soldTickets}',
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Progress bar
        if (!isFinished) ...[
          Text(
            'Progreso de venta',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: percent,
                    minHeight: 10,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      percent > 0.7 ? kGoldColor : kPrimaryColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${(percent * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: kPrimaryColor,
                ),
              ),
            ],
          ),
        ],

        // Premios section
        const SizedBox(height: 32),
        Container(
          decoration: BoxDecoration(
            color: kGoldColor.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kGoldColor.withOpacity(0.3)),
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
                    "Premios del Evento",
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
  }

  // Purchase panel (right column)
  Widget _buildPurchasePanel(
    Sorteo sorteo,
    NumberFormat currency,
    double percent,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Comprar boletos',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 24),

          // Quantity selector
          const Text(
            'Cantidad',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          _counter(
            value: _cantidad,
            onChanged: (v) => setState(() => _cantidad = v),
          ),
          const SizedBox(height: 24),

          // Total a pagar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total a pagar',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              Text(
                currency.format(
                  sorteo.precioTicket *
                      _calculatePaidTickets(sorteo, _cantidad),
                ),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),

          if (sorteo.hasPromo) ...[
            const SizedBox(height: 12),
            _promotionBadge(sorteo),
          ],

          const SizedBox(height: 24),

          // CTA Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _canConfirm() && !_loading
                  ? () => _onConfirmar(sorteo)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade500,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
                shadowColor: Colors.transparent,
              ),
              child: Text(
                _loading ? 'PROCESANDO...' : 'Participar ahora',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Trust badge
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.verified_user, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Text(
                'Compra 100% segura y verificable',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Ticket selection grid
  Widget _buildTicketSelectionGrid(Sorteo sorteo) {
    // Get only available tickets (not sold)
    final availableTickets = List<int>.generate(
      sorteo.totalTickets,
      (index) => index + 1,
    ).where((num) => !_soldTicketNumbers.contains(num)).toList();

    // Tickets to display (limited by _ticketsToShow)
    final ticketsToDisplay = availableTickets.take(_ticketsToShow).toList();
    final hasMore = availableTickets.length > _ticketsToShow;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.touch_app, color: kPrimaryColor, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Selecciona tus boletos',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              if (_selectedTickets.isNotEmpty)
                TextButton.icon(
                  onPressed: () => setState(() => _selectedTickets.clear()),
                  icon: const Icon(Icons.clear_all, size: 16),
                  label: const Text('Limpiar'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _selectedTickets.isEmpty
                ? 'Selecciona ${_cantidad} boleto${_cantidad != 1 ? 's' : ''} · ${availableTickets.length} disponibles'
                : 'Seleccionados: ${_selectedTickets.length} de $_cantidad · ${availableTickets.length} disponibles',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),

          // SELECTED TICKETS FIRST (at the top)
          if (_selectedTickets.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kPrimaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kPrimaryColor.withOpacity(0.3)),
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _selectedTickets.map((num) {
                  return Chip(
                    label: Text(
                      num.toString().padLeft(3, '0'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    backgroundColor: kPrimaryColor,
                    labelStyle: const TextStyle(color: Colors.white),
                    deleteIconColor: Colors.white,
                    onDeleted: () =>
                        setState(() => _selectedTickets.remove(num)),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // GRID BELOW selected tickets
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = (constraints.maxWidth / 60).floor().clamp(
                6,
                15,
              );

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemCount: ticketsToDisplay.length,
                itemBuilder: (context, index) {
                  final ticketNumber = ticketsToDisplay[index];
                  final isSelected = _selectedTickets.contains(ticketNumber);

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedTickets.remove(ticketNumber);
                        } else {
                          if (_selectedTickets.length < _cantidad) {
                            _selectedTickets.add(ticketNumber);
                          }
                        }
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected ? kPrimaryColor : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? kPrimaryColor
                              : Colors.grey.shade300,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          ticketNumber.toString().padLeft(3, '0'),
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontWeight: isSelected
                                ? FontWeight.w900
                                : FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),

          // Load more button
          if (hasMore) ...[
            const SizedBox(height: 16),
            Center(
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _ticketsToShow += 100;
                  });
                },
                icon: const Icon(Icons.expand_more, size: 20),
                label: Text(
                  'Cargar más (${availableTickets.length - _ticketsToShow} restantes)',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kPrimaryColor,
                  side: BorderSide(color: kPrimaryColor.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Select random tickets
  void _selectRandomTickets(Sorteo sorteo) {
    setState(() {
      _selectedTickets.clear();

      // Get available tickets (not sold)
      final availableTickets = List<int>.generate(
        sorteo.totalTickets,
        (index) => index + 1,
      ).where((num) => !_soldTicketNumbers.contains(num)).toList();

      if (availableTickets.isEmpty) {
        return;
      }

      // Shuffle and take the required quantity
      availableTickets.shuffle();
      final ticketsToSelect = availableTickets.take(_cantidad).toList();
      _selectedTickets.addAll(ticketsToSelect);
    });
  }

  // Info card widget

  // Info card widget
  Widget _infoCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      width: 145,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: kPrimaryColor),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
              height: 1.2,
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

  // =====================================================================
  // VERIFICADOR PARA ESTE SORTEO
  // =====================================================================
  Widget _buildVerificador(Sorteo sorteo) {
    return Container(
      key: _verificadorSectionKey,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                const Text(
                  "VERIFICADOR DE BOLETOS",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: kPrimaryColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  "Consulta el estado de tus boletos reservados para\n\"${sorteo.titulo}\"",
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _verificadorCtrl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _buscarBoleto(sorteo.id),
                  decoration: InputDecoration(
                    hintText: "Número de teléfono o #boleto",
                    filled: true,
                    fillColor: const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: kPrimaryColor, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _verificando
                        ? null
                        : () => _buscarBoleto(sorteo.id),
                    icon: _verificando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.search, color: Colors.white),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kGoldColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                    label: Text(
                      _verificando ? "BUSCANDO..." : "BUSCAR MIS BOLETOS",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                if (_verificadorMsg != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _verificadorOk == true
                            ? Icons.check_circle
                            : Icons.error_outline,
                        color: _verificadorOk == true
                            ? Colors.green
                            : Colors.red,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _verificadorMsg!,
                          textAlign: TextAlign.center,
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
                if (_tickets.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  _verificadorResultados(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _buscarBoleto(String sorteoId) async {
    final input = _verificadorCtrl.text.trim();
    if (input.isEmpty) return;

    final sanitized = input.replaceAll(RegExp(r'[^0-9]'), '');
    final bool esNumeroCorto = sanitized.length < 5;

    setState(() {
      _verificando = true;
      _verificadorMsg = null;
      _verificadorOk = null;
      _tickets = [];
      _ticketKeys.clear();
      _busquedaNumeroExacta = esNumeroCorto;
    });

    try {
      final result = await _repo.verifyTickets(
        input,
        searchNumberExact: esNumeroCorto,
        searchPhoneOnly: !esNumeroCorto,
        sorteoId: sorteoId,
      );

      if (result.isEmpty) {
        setState(() {
          _verificadorOk = false;
          _verificadorMsg =
              "No encontramos boletos para este sorteo con ese dato.";
        });
      } else {
        final keysMap = <String, GlobalKey>{};
        for (final t in result) {
          keysMap[_ticketKeyId(t)] = GlobalKey();
        }

        setState(() {
          _verificadorOk = true;
          _tickets = result;
          _ticketKeys.addAll(keysMap);
          _verificadorMsg =
              "Encontramos ${result.length} boleto${result.length > 1 ? 's' : ''}.";
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

  String _ticketKeyId(VerifiedTicket t) => "ticket_${t.sorteoId}_${t.numero}";

  Widget _verificadorResultados() {
    final first = _tickets.first;
    final dateFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    final qrData =
        'https://multisorteos.com/?ticket=${Uri.encodeComponent(_verificadorCtrl.text.trim())}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 6),
        if (!_busquedaNumeroExacta) ...[
          Text(
            first.buyerNombre ?? 'Comprador',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300, width: 2),
          ),
          child: QrImageView(
            data: qrData,
            version: QrVersions.auto,
            size: 140,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Colors.black,
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Colors.black,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          "Numeros en total: ${_tickets.length}",
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        const SizedBox(height: 20),
        Column(
          children: _tickets
              .map(
                (t) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Center(child: _ticketCard(t, dateFmt)),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
  Widget _ticketCard(VerifiedTicket t, DateFormat dateFmt) {
    final fecha = t.soldAt != null
        ? dateFmt.format(t.soldAt!.toLocal())
        : 'Reserva (Boleto por confirmar)';
    final bool isReserved = t.estado.toLowerCase() == 'reserved';
    final statusText = isReserved ? "Reservado" : "Pago verificado";
    final statusColor = isReserved ? Colors.orange : Colors.green;
    final statusIcon = isReserved
        ? Icons.access_time_filled
        : Icons.check_circle;
    final bg = t.sorteoImagenUrl;

    final key = _ticketKeys[_ticketKeyId(t)] ?? GlobalKey();
    _ticketKeys.putIfAbsent(_ticketKeyId(t), () => key);

    String maskPhone(String phone) {
      if (phone.length <= 5) return phone;
      final keepStart = phone.substring(0, 3);
      final keepEnd = phone.substring(phone.length - 2);
      final middle = "*" * (phone.length - 5);
      return "$keepStart-$middle-$keepEnd";
    }

    String maskName(String name) {
      final parts = name.split(" ");
      if (parts.length <= 2) return "${parts.first} ****";
      return "${parts[0]} ${parts[1]} **** ****";
    }

    final maskedName = t.buyerNombre != null
        ? maskName(t.buyerNombre!)
        : "Cliente";

    final showFullData = !_busquedaNumeroExacta;
    final displayName = showFullData
        ? (t.buyerNombre ?? "Cliente")
        : maskedName;
    final displayPhone = showFullData
        ? (t.buyerTelefono ?? "***")
        : (t.buyerTelefono != null ? maskPhone(t.buyerTelefono!) : "***");

    return RepaintBoundary(
      key: key,
      child: Container(
        width: 260,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0A2B57),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                image: bg != null
                    ? DecorationImage(
                        image: CachedNetworkImageProvider(bg),
                        fit: BoxFit.cover,
                        colorFilter: ColorFilter.mode(
                          Colors.black.withValues(alpha: 0.55),
                          BlendMode.darken,
                        ),
                      )
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.sorteoTitulo,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(statusIcon, color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          statusText.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.person, color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.phone_android,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        displayPhone,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.event, color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          fecha,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
              ),
              child: Column(
                children: [
                  const Text(
                    "BOLETO",
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t.numero.toString().padLeft(4, '0'),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ticketActionButtons(t),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _ticketActionButtons(VerifiedTicket t) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _downloadTicket(t),
            icon: const Icon(Icons.download, size: 18, color: Colors.white),
            label: const Text(
              "DESCARGAR",
              style: TextStyle(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryColor,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _printTicket(t),
            icon: const Icon(Icons.print, size: 18, color: Colors.white),
            label: const Text(
              "IMPRIMIR",
              style: TextStyle(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryColor.withValues(alpha: 0.9),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }
  Future<void> _downloadTicket(VerifiedTicket t) async {
    final key = _ticketKeys[_ticketKeyId(t)];
    if (key == null) return;
    try {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();
      await ticket_saver.saveTicketImage(bytes, "Ticket_${t.numero}.png");
    } catch (e) {
      debugPrint("Error downloading ticket: $e");
    }
  }

  Future<void> _printTicket(VerifiedTicket t) async {
    final key = _ticketKeys[_ticketKeyId(t)];
    if (key == null) return;
    try {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      final pdf = pw.Document();
      final pdfImage = pw.MemoryImage(bytes);
      pdf.addPage(
        pw.Page(
          build: (pw.Context context) => pw.Center(child: pw.Image(pdfImage)),
        ),
      );
      await Printing.layoutPdf(onLayout: (format) async => pdf.save());
    } catch (e) {
      debugPrint("Error printing ticket: $e");
    }
  }
}

