import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carousel_slider/carousel_slider.dart';

import 'ticket_image_saver_stub.dart'
    if (dart.library.html) 'ticket_image_saver_web.dart'
    if (dart.library.io) 'ticket_image_saver_io.dart'
    as ticket_saver;

import 'data/models.dart';
import 'data/raffles_repository.dart';
import 'raffle_detail_page.dart' hide SingleChildScrollView;
import 'chat_popup_widget.dart';

// =====================================================================
// ESTILOS GLOBALES
// =====================================================================

const Color kPrimaryColor = Color(0xFF007BFF); // Original Blue
const Color kBackgroundColor = Color(0xFFF8FAFC);
const Color kGoldColor = Color(0xFFD4AF37); // Premium Gold
const Color kGoldLight = Color(0xFFFFD700);
const Color kGreenSucces = Color(0xFF16A34A);

// Premium Shadow Effects
final List<BoxShadow> kPremiumShadow = [
  BoxShadow(
    color: kGoldColor.withValues(alpha: 0.25),
    blurRadius: 20,
    spreadRadius: 2,
    offset: const Offset(0, 4),
  ),
  BoxShadow(
    color: Colors.black.withValues(alpha: 0.1),
    blurRadius: 10,
    offset: const Offset(0, 4),
  ),
];

const TextStyle kTitleMain = TextStyle(
  fontSize: 38,
  fontWeight: FontWeight.w900,
  letterSpacing: 1,
  color: kPrimaryColor,
);

const TextStyle kTitleSection = TextStyle(
  fontSize: 32,
  fontWeight: FontWeight.w900,
  letterSpacing: 0.8,
  color: kPrimaryColor,
);

class MultisorteosPage extends StatefulWidget {
  final String? initialSearch;
  const MultisorteosPage({super.key, this.initialSearch});

  @override
  State<MultisorteosPage> createState() => _MultisorteosPageState();
}

class _MultisorteosPageState extends State<MultisorteosPage> {
  final ScrollController _scrollController = ScrollController();
  final RafflesRepository _repo = RafflesRepository();
  late Future<List<Sorteo>> _rafflesFuture;
  final TextEditingController _verificadorCtrl = TextEditingController();
  bool _verificando = false;
  String? _verificadorMsg;
  bool? _verificadorOk;
  List<VerifiedTicket> _tickets = [];
  bool _busquedaNumeroExacta = false;

  // Keys para capturar cada ticket como imagen
  final Map<String, GlobalKey> _ticketKeys = {};

  // Key para el Scaffold (necesario para abrir el drawer)
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final inicioKey = GlobalKey();
  final sorteosKey = GlobalKey();
  final acercaKey = GlobalKey();
  final ganadoresKey = GlobalKey();
  final verificadorKey = GlobalKey();
  final metodosKey = GlobalKey();
  final contactoKey = GlobalKey();
  final preguntasKey = GlobalKey();

  void _scrollToSection(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
        alignment: 0.05, // Slight offset from top
      );
    } else {
      debugPrint("Scroll target context is null");
    }
  }

  @override
  void initState() {
    super.initState();
    _rafflesFuture = _repo.fetchActiveRaffles();

    if (widget.initialSearch != null && widget.initialSearch!.isNotEmpty) {
      _verificadorCtrl.text = widget.initialSearch!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSection(verificadorKey);
        _buscarBoleto();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _verificadorCtrl.dispose();
    super.dispose();
  }

  // =====================================================================
  // WHATSAPP BUTTON REUSABLE
  // =====================================================================
  Widget whatsappButton(String text, String phone) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          final url = "https://api.whatsapp.com/send?phone=$phone";
          launchUrl(Uri.parse(url));
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF25D366),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: const Icon(Icons.phone, color: Colors.white, size: 22),
        label: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // =====================================================================
  // CAPTURA DE TICKET COMO IMAGEN JPG
  // =====================================================================

  String _ticketKeyId(VerifiedTicket t) =>
      '${t.sorteoTitulo}_${t.numero.toString().padLeft(4, '0')}';

  Future<Uint8List?> _captureTicketAsJpg(GlobalKey repaintKey) async {
    try {
      final boundary =
          repaintKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;

      // Renderizamos con buena resolución
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      final pngBytes = byteData.buffer.asUint8List();

      // Convertir PNG -> JPG usando package:image
      final decoded = img.decodeImage(pngBytes);
      if (decoded == null) return pngBytes;

      final jpgBytes = img.encodeJpg(decoded, quality: 90);
      return Uint8List.fromList(jpgBytes);
    } catch (e) {
      debugPrint('Error capturando ticket: $e');
      return null;
    }
  }

  Future<void> _downloadTicket(VerifiedTicket t) async {
    final key = _ticketKeys[_ticketKeyId(t)];
    if (key == null) return;

    final bytes = await _captureTicketAsJpg(key);
    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo generar la imagen.')),
        );
      }
      return;
    }

    try {
      final filename = 'ticket_${t.numero.toString().padLeft(4, '0')}.jpg';
      await ticket_saver.saveTicketImage(bytes, filename);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Imagen descargada correctamente.')),
        );
      }
    } catch (e) {
      debugPrint('Error guardando imagen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al guardar la imagen del ticket.'),
          ),
        );
      }
    }
  }

  Future<void> _printTicket(VerifiedTicket t) async {
    final key = _ticketKeys[_ticketKeyId(t)];
    if (key == null) return;

    final bytes = await _captureTicketAsJpg(key);
    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo generar la imagen.')),
        );
      }
      return;
    }

    // WEB: usar el saver condicional en lugar de dart:html
    if (kIsWeb) {
      try {
        final filename = 'ticket_${t.numero.toString().padLeft(4, '0')}.jpg';
        await ticket_saver.saveTicketImage(bytes, filename);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Imagen abierta en nueva pestaña')),
          );
        }
      } catch (e) {
        debugPrint('Error abriendo imagen: $e');
      }
      return;
    }

    // NO WEB: plugin printing
    await Printing.layoutPdf(
      name: 'ticket_${t.numero.toString().padLeft(4, '0')}.pdf',
      onLayout: (format) async {
        final pdf = pw.Document();
        final image = pw.MemoryImage(bytes);
        pdf.addPage(
          pw.Page(
            pageFormat: format,
            build: (context) => pw.Center(child: pw.Image(image)),
          ),
        );
        return pdf.save();
      },
    );
  }

  // =====================================================================
  // MAIN BUILD
  // =====================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: kBackgroundColor,
      drawer: _buildDrawer(),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 92),
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                children: [
                  _buildInicio(),
                  _buildSorteos(),
                  _buildAcerca(),
                  _buildGanadores(),
                  _buildVerificador(),
                  _buildMetodosPago(),
                  _buildContacto(),
                  _buildPreguntas(),
                  _buildFooter(),
                ],
              ),
            ),
          ),
          Positioned(top: 0, left: 0, right: 0, child: _buildHeader()),
          // Widget de chat flotante
          const ChatPopupWidget(),
        ],
      ),
    );
  }

  // =====================================================================
  // HEADER
  // =====================================================================
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 900;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Logo
                    Expanded(
                      child: Image.asset(
                        'assets/imagenes/logo_completo.png',
                        height: isMobile ? 48 : 64,
                        alignment: Alignment.centerLeft,
                      ),
                    ),

                    // Menú hamburguesa para móvil o menú completo para desktop
                    if (isMobile)
                      IconButton(
                        icon: const Icon(
                          Icons.menu,
                          color: kPrimaryColor,
                          size: 32,
                        ),
                        onPressed: () {
                          _scaffoldKey.currentState?.openDrawer();
                        },
                      )
                    else
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _menuItem(
                              "Inicio",
                              () => _scrollToSection(inicioKey),
                            ),
                            _menuItem(
                              "Acerca de Nosotros",
                              () => _scrollToSection(acercaKey),
                            ),
                            _menuItem(
                              "Sorteos Anteriores",
                              () => _scrollToSection(ganadoresKey),
                            ),
                            _menuItem(
                              "Verificador",
                              () => _scrollToSection(verificadorKey),
                            ),
                            _menuItem(
                              "Contacto",
                              () => _scrollToSection(contactoKey),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
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
          style: const TextStyle(
            color: kPrimaryColor,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // =====================================================================
  // DRAWER (MENÚ LATERAL MÓVIL)
  // =====================================================================
  Widget _buildDrawer() {
    return Drawer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kPrimaryColor.withValues(alpha: 0.05), Colors.white],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header del Drawer
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: kPrimaryColor,
                  boxShadow: [
                    BoxShadow(
                      color: kPrimaryColor.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Image.asset(
                      'assets/imagenes/logo_completo.png',
                      height: 60,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'MENÚ DE NAVEGACIÓN',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),

              // Menú Items
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  children: [
                    _drawerMenuItem(
                      icon: Icons.home_rounded,
                      text: 'Inicio',
                      onTap: () {
                        Navigator.pop(context);
                        _scrollToSection(inicioKey);
                      },
                    ),
                    _drawerMenuItem(
                      icon: Icons.info_rounded,
                      text: 'Acerca de Nosotros',
                      onTap: () {
                        Navigator.pop(context);
                        _scrollToSection(acercaKey);
                      },
                    ),
                    _drawerMenuItem(
                      icon: Icons.emoji_events_rounded,
                      text: 'Sorteos Anteriores',
                      onTap: () {
                        Navigator.pop(context);
                        _scrollToSection(ganadoresKey);
                      },
                    ),
                    _drawerMenuItem(
                      icon: Icons.verified_rounded,
                      text: 'Verificador',
                      onTap: () {
                        Navigator.pop(context);
                        _scrollToSection(verificadorKey);
                      },
                    ),
                    _drawerMenuItem(
                      icon: Icons.contact_support_rounded,
                      text: 'Contacto',
                      onTap: () {
                        Navigator.pop(context);
                        _scrollToSection(contactoKey);
                      },
                    ),
                  ],
                ),
              ),

              // Footer del Drawer
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade200, width: 1),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.star, color: kPrimaryColor, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'MULTISORTEOS',
                          style: TextStyle(
                            color: kPrimaryColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Plataforma oficial de ventas online para eventos y dinámicas con @santotejadard',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _drawerMenuItem({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: kPrimaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: kPrimaryColor, size: 24),
      ),
      title: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1F2937),
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      hoverColor: kPrimaryColor.withValues(alpha: 0.05),
    );
  }

  // =====================================================================
  // INICIO (HERO)
  // =====================================================================
  Widget _buildInicio() {
    return Container(
      key: inicioKey,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      color: Colors.white, // Fondo limpio blanco o muy claro
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 900;

              // --- COLUMNA IZQUIERDA: INFORMACIÓN ---
              final infoColumn = Column(
                crossAxisAlignment: isNarrow
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Badge Superior
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.card_giftcard,
                          size: 16,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "PLATAFORMA CONFIABLE Y TRANSPARENTE",
                          style: TextStyle(
                            color: kPrimaryColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Titulo Principal
                  RichText(
                    textAlign: isNarrow ? TextAlign.center : TextAlign.start,
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: isNarrow ? 36 : 52,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                        color: Colors.black87, // Standard dark text
                        fontFamily:
                            'Roboto', // Asegurar fuente default o custom
                      ),
                      children: const [
                        TextSpan(text: "Participa en "),
                        TextSpan(
                          text: "Sorteos\nOnline",
                          style: TextStyle(color: kPrimaryColor),
                        ),
                        TextSpan(text: " y Gana\n"),
                        TextSpan(text: "Premios Increíbles"),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Descripción
                  Text(
                    "La forma más emocionante, segura y transparente de ganar premios espectaculares. Compra tu boleto, participa en el sorteo y ¡conviértete en el próximo ganador!",
                    textAlign: isNarrow ? TextAlign.center : TextAlign.start,
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.blueGrey.shade700,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Botones
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    alignment: isNarrow
                        ? WrapAlignment.center
                        : WrapAlignment.start,
                    children: [
                      // Botón Sólido (Ver Sorteos)
                      ElevatedButton.icon(
                        onPressed: () => _scrollToSection(sorteosKey),
                        icon: const Icon(Icons.confirmation_num, size: 20),
                        label: const Text("VER SORTEOS ACTIVOS"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimaryColor, // Azul fuerte
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 4,
                          shadowColor: kPrimaryColor.withValues(alpha: 0.4),
                        ),
                      ),

                      // Botón Outlined (Cómo funciona)
                      OutlinedButton.icon(
                        onPressed: () => _scrollToSection(acercaKey),
                        icon: const Icon(Icons.play_circle_fill, size: 20),
                        label: const Text("CÓMO FUNCIONA"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kPrimaryColor,
                          side: const BorderSide(
                            color: kPrimaryColor,
                            width: 2,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),

                  // Trust Indicators (Iconos abajo)
                  Wrap(
                    spacing: 24,
                    runSpacing: 12,
                    alignment: isNarrow
                        ? WrapAlignment.center
                        : WrapAlignment.start,
                    children: [
                      _trustItem(
                        Icons.verified_user,
                        "100% Seguro",
                        Colors.green,
                      ),
                      _trustItem(Icons.star, "Transparente", Colors.blue),
                      _trustItem(
                        Icons.emoji_events,
                        "+50 Ganadores",
                        kGoldColor,
                      ),
                    ],
                  ),
                ],
              );

              // --- COLUMNA DERECHA: IMAGEN / COMPOSICIÓN ---
              // Simulamos el frame de la derecha con un Container azul claro y la imagen 'logo_completo.png'
              // y algunos elementos flotantes para darle dinamismo.
              final graphicComposition = Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // Fondo azul claro redondeado
                  Container(
                    width: 450,
                    height: 400,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50, // Azul muy suave
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(color: Colors.blue.shade100, width: 2),
                    ),
                  ),

                  // Imagen Principal (Usamos una imagen genérica o el logo si no hay assets de premios)
                  // Como placeholder usaremos el logo_completo pero estilizado o una imagen de asset si hubiese.
                  // Usaremos 'assets/imagenes/logo_completo.png' ya que sabemos que existe.
                  // Carrousel de Sorteos Activos (Reemplaza Logo Estático)
                  FutureBuilder<List<Sorteo>>(
                    future: _rafflesFuture,
                    builder: (context, snapshot) {
                      final activeSorteos =
                          snapshot.data
                              ?.where(
                                (s) =>
                                    s.fechaSorteo == null ||
                                    s.fechaSorteo!.isAfter(DateTime.now()),
                              )
                              .toList() ??
                          [];

                      if (snapshot.hasData && activeSorteos.isNotEmpty) {
                        return Container(
                          width: 380,
                          height: 320,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: CarouselSlider(
                            options: CarouselOptions(
                              height: 320,
                              viewportFraction: 1.0,
                              autoPlay: true,
                              autoPlayInterval: const Duration(seconds: 4),
                              autoPlayAnimationDuration: const Duration(
                                milliseconds: 800,
                              ),
                              autoPlayCurve: Curves.fastOutSlowIn,
                              enlargeCenterPage: true,
                            ),
                            items: activeSorteos.map((sorteo) {
                              return Builder(
                                builder: (BuildContext context) {
                                  return GestureDetector(
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => RaffleDetailPage(
                                            initialSorteo: sorteo,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      width: 380,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(20),
                                        color: Colors.white,
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(20),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            if (sorteo.imagenUrl != null)
                                              CachedNetworkImage(
                                                imageUrl: sorteo.imagenUrl!,
                                                fit: BoxFit.cover,
                                              )
                                            else
                                              Image.asset(
                                                'assets/imagenes/logo_completo.png',
                                                fit: BoxFit.contain,
                                              ),
                                            // Gradiente y Titulo
                                            Positioned(
                                              bottom: 0,
                                              left: 0,
                                              right: 0,
                                              child: Container(
                                                padding: const EdgeInsets.all(
                                                  16,
                                                ),
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    begin:
                                                        Alignment.bottomCenter,
                                                    end: Alignment.topCenter,
                                                    colors: [
                                                      Colors.black.withValues(
                                                        alpha: 0.8,
                                                      ),
                                                      Colors.transparent,
                                                    ],
                                                  ),
                                                ),
                                                child: Text(
                                                  sorteo.titulo,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            }).toList(),
                          ),
                        );
                      }
                      // Fallback: Logo Estático
                      return Container(
                        width: 380,
                        height: 320,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Image.asset(
                          'assets/imagenes/logo_completo.png',
                          fit: BoxFit.contain,
                        ),
                      );
                    },
                  ),

                  // Elemento Flotante 1: Boleto (Izquierda)
                  Positioned(
                    left: -20,
                    bottom: 80,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.local_activity,
                            color: kPrimaryColor,
                            size: 32,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            "BOLETO",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                          Text(
                            "#12345",
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: kPrimaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Elemento Flotante 2: Ganaste (Derecha, abajo)

                  // Elemento Flotante 3: Copa (Derecha, arriba)
                  Positioned(
                    right: -10,
                    top: -10,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: kPrimaryColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: kPrimaryColor.withValues(alpha: 0.4),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: const Icon(
                        Icons.emoji_events,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                ],
              );

              if (isNarrow) {
                return Column(
                  children: [
                    infoColumn,
                    const SizedBox(height: 60),
                    graphicComposition,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: infoColumn),
                  const SizedBox(width: 40),
                  // No Expanded para el gráfico para que mantenga su tamaño fijo relativo
                  graphicComposition,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _trustItem(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.blueGrey.shade600,
          ),
        ),
      ],
    );
  }

  // =====================================================================
  // BANNER 3-EN-1 (MUESTRA 3 SORTEOS A LA VEZ)
  // =====================================================================

  // =====================================================================
  // SORTEOS ACTUALES
  // =====================================================================
  Widget _buildSorteos() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            children: [
              Text(
                "SORTEOS ACTUALES",
                key: sorteosKey,
                style: kTitleMain,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                "Explora los sorteos disponibles y asegura tus boletos antes de que se agoten.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 25),
              FutureBuilder<List<Sorteo>>(
                future: _rafflesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const CircularProgressIndicator();
                  }

                  if (snapshot.hasError) {
                    return Text("Error: ${snapshot.error}");
                  }

                  final sorteos = snapshot.data ?? [];
                  final now = DateTime.now();

                  // Filtrar sorteos activos (fecha futura o nula)
                  final activeSorteos = sorteos.where((s) {
                    if (s.fechaSorteo == null) return true;
                    return !s.fechaSorteo!.isBefore(now);
                  }).toList();

                  if (activeSorteos.isEmpty) {
                    return const Text(
                      "AÚN NO HAY SORTEOS ACTIVOS.",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.black54,
                      ),
                    );
                  }

                  // Ordenar sorteos por fecha_sorteo ascendente
                  // Los que terminan primero aparecen primero
                  // Los que no tienen fecha van al final
                  final sortedSorteos = List<Sorteo>.from(activeSorteos)
                    ..sort((a, b) {
                      if (a.fechaSorteo == null && b.fechaSorteo == null) {
                        return 0;
                      }
                      if (a.fechaSorteo == null) return 1;
                      if (b.fechaSorteo == null) return -1;
                      return a.fechaSorteo!.compareTo(b.fechaSorteo!);
                    });

                  return Column(
                    children: [
                      const SizedBox(height: 20),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 48,
                        runSpacing: 48,
                        children: sortedSorteos
                            .map((s) => _buildSorteoItem(context, s))
                            .toList(),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSorteoItem(BuildContext context, Sorteo sorteo) {
    return SorteoCard(sorteo: sorteo);
  }

  Widget _buildAcerca() {
    return Container(
      key: acercaKey,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
      color: Colors.white,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [kGoldColor, kGoldLight],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: kGoldColor.withValues(alpha: 0.5),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.confirmation_num_outlined,
                  size: 40,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                "ACERCA DE NOSOTROS",
                textAlign: TextAlign.center,
                style: kTitleSection,
              ),
              const SizedBox(height: 16),
              const SizedBox(
                width: 700,
                child: Text(
                  "Multisorteos es una plataforma moderna y transparente, diseñada para que participar en rifas sea una experiencia confiable, rápida y totalmente segura. Con tecnología de verificación en tiempo real, procesos claros y un enfoque en la experiencia del usuario, conectamos a miles de personas con oportunidades reales de ganar en cada dinámica.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    height: 1.6,
                    color: Colors.black54,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.star, color: kPrimaryColor, size: 22),
                  SizedBox(width: 8),
                  Icon(Icons.star_border, color: kPrimaryColor, size: 22),
                  SizedBox(width: 8),
                  Icon(Icons.star, color: kPrimaryColor, size: 22),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================================
  // GANADORES
  // =====================================================================
  Widget _buildGanadores() {
    return Container(
      key: ganadoresKey,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              children: [
                const Text(
                  "GANADORES ANTERIORES",
                  style: kTitleSection,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  "Historial de ganadores y sorteos completados.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 25),
                FutureBuilder<List<Sorteo>>(
                  future: _rafflesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        height: 50,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    if (snapshot.hasError) {
                      return Text("Error: ${snapshot.error}");
                    }

                    final sorteos = snapshot.data ?? [];
                    final now = DateTime.now();

                    // Filtrar sorteos finalizados (fecha pasada)
                    final finishedSorteos = sorteos.where((s) {
                      if (s.fechaSorteo == null) return false;
                      return s.fechaSorteo!.isBefore(now);
                    }).toList();

                    if (finishedSorteos.isEmpty) {
                      return const Text(
                        "Aún no hay sorteos finalizados.",
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.black54,
                        ),
                      );
                    }

                    // Ordenar sorteos por fecha_sorteo descendente (más recientes primero)
                    final sortedSorteos = List<Sorteo>.from(finishedSorteos)
                      ..sort((a, b) {
                        return b.fechaSorteo!.compareTo(a.fechaSorteo!);
                      });

                    return Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 48,
                      runSpacing: 48,
                      children: sortedSorteos
                          .map((s) => _buildSorteoItem(context, s))
                          .toList(),
                    );
                  },
                ),
              ], // Fixed missing bracket
            ),
          ),
        ),
      ),
    );
  }

  // =====================================================================
  // VERIFICADOR
  // =====================================================================
  Widget _buildVerificador() {
    return Container(
      key: verificadorKey,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "VERIFICADOR DE BOLETOS",
                  style: kTitleSection,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  "Ingresa tu número de teléfono o el número de boleto para validar tu compra.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.black54),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _verificadorCtrl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _buscarBoleto(),
                  decoration: InputDecoration(
                    hintText: "Número de teléfono o #boleto",
                    filled: true,
                    fillColor: kBackgroundColor,
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
                    onPressed: _verificando ? null : _buscarBoleto,
                    icon: const Icon(Icons.search, color: Colors.white),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kGoldColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 6,
                      shadowColor: kGoldColor.withValues(alpha: 0.4),
                    ),
                    label: Text(
                      _verificando ? "BUSCANDO..." : "BUSCAR",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                if (_verificadorMsg != null) ...[
                  const SizedBox(height: 14),
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
                  const SizedBox(height: 18),
                  _verificadorResultados(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _buscarBoleto() async {
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
      );
      if (result.isEmpty) {
        setState(() {
          _verificadorOk = false;
          _verificadorMsg = "No encontramos boletos con ese dato.";
        });
      } else {
        final keysMap = <String, GlobalKey>{};
        for (final t in result) {
          keysMap[_ticketKeyId(t)] = GlobalKey();
        }

        setState(() {
          _verificadorOk = true;
          _tickets = result;
          _ticketKeys
            ..clear()
            ..addAll(keysMap);
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
          "Números en total: ${_tickets.length}",
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

    // ======== ENMASCARAR DATOS SENSIBLES ========

    String maskPhone(String phone) {
      if (phone.length <= 5) return phone;
      final keepStart = phone.substring(0, 3);
      final keepEnd = phone.substring(phone.length - 2);
      final middle = "*" * (phone.length - 5);
      return "$keepStart-$middle-$keepEnd";
    }

    // ======== ENMASCARAR DATOS SENSIBLES ========
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
            // CABECERA
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0A2B57),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                image: bg != null
                    ? DecorationImage(
                        image: NetworkImage(bg),
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

            // CUERPO DEL BOLETO
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
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _downloadTicket(t),
                          icon: const Icon(
                            Icons.download,
                            size: 18,
                            color: Colors.white,
                          ),
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
                          icon: const Icon(
                            Icons.print,
                            size: 18,
                            color: Colors.white,
                          ),
                          label: const Text(
                            "IMPRIMIR",
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimaryColor.withValues(
                              alpha: 0.9,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================================
  // MÉTODOS DE PAGO
  // =====================================================================
  Widget _buildMetodosPago() {
    return Container(
      key: metodosKey,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              children: [
                const Text(
                  "MÉTODOS DE PAGO",
                  style: kTitleSection,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  "Coordina tu pago directo con el equipo oficial y asegura tu participación.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.black54),
                ),
                const SizedBox(height: 30),
                Wrap(
                  spacing: 20,
                  runSpacing: 20,
                  children: [
                    _buildMetodoItem(
                      "💵",
                      "Efectivo",
                      "Disponible mediante acuerdos directos según la dinámica.",
                    ),
                    _buildMetodoItem(
                      "🏦",
                      "Transferencia Bancaria",
                      "",
                      isWhatsapp: true,
                    ),
                    _buildMetodoItem(
                      "💳",
                      "Tarjeta de crédito",
                      "Aceptamos pagos mediante enlaces seguros con validación.",
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetodoItem(
    String icon,
    String titulo,
    String desc, {
    bool isWhatsapp = false,
  }) {
    return _PremiumInfoCard(
      icon: icon,
      titulo: titulo,
      desc: desc,
      isWhatsapp: isWhatsapp,
    );
  }

  // =====================================================================
  // CONTACTO
  // =====================================================================
  Widget _buildContacto() {
    return Container(
      key: contactoKey,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              children: [
                const Text(
                  "CONTÁCTANOS",
                  style: kTitleSection,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  "Canales oficiales para dudas, soporte y coordinación de pagos.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.black54),
                ),
                const SizedBox(height: 30),
                Wrap(
                  spacing: 20,
                  runSpacing: 20,
                  children: [
                    _buildContactoItem("🌐", "Sitio Web", "multisorteos.com"),
                    _buildContactoItem(
                      "📍",
                      "Ubicación",
                      "Santiago, República Dominicana",
                    ),
                    _buildContactoItem(
                      "📞",
                      "WhatsApp Directo",
                      "",
                      isWhatsapp: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactoItem(
    String icon,
    String titulo,
    String desc, {
    bool isWhatsapp = false,
  }) {
    return _PremiumInfoCard(
      icon: icon,
      titulo: titulo,
      desc: desc,
      isWhatsapp: isWhatsapp,
    );
  }

  // =====================================================================
  // FAQs
  // =====================================================================
  Widget _buildPreguntas() {
    return Container(
      key: preguntasKey,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              children: [
                const Text(
                  "PREGUNTAS FRECUENTES",
                  style: kTitleSection,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                _buildFAQ(
                  "¿Cuándo podré comprar boletos en línea?",
                  "Estamos preparando la plataforma de pagos para que puedas adquirir tus boletos directamente desde la web.",
                ),
                _buildFAQ(
                  "¿Los sorteos de Montao se gestionan aquí?",
                  "Sí, Multisorteos centraliza la información oficial de las dinámicas y sus procesos.",
                ),
                _buildFAQ(
                  "¿Dónde puedo ver más información?",
                  "Síguenos en Instagram como @multisorteosrd y @santotejadard para noticias, lanzamientos y ganadores.",
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFAQ(String pregunta, String respuesta) {
    return ExpansionTile(
      title: Text(
        pregunta,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            respuesta,
            style: const TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ),
      ],
    );
  }

  // =====================================================================
  // FOOTER
  // =====================================================================
  Widget _buildFooter() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [kPrimaryColor, Color(0xFF0056b3)], // Blue gradient
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 50),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 250,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          "Multisorteos",
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          "Plataforma oficial de ventas online para eventos y dinámicas con @santotejadard",
                          style: TextStyle(fontSize: 15, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        "Secciones",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      SizedBox(height: 10),
                      FooterText("Inicio"),
                      FooterText("Sorteos actuales"),
                      FooterText("Verificador"),
                      FooterText("Métodos de pago"),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        "Contacto",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      SizedBox(height: 10),
                      FooterText("Compras Web: 849-628-5498"),
                      FooterText("Ventas WhatsApp: 849-539-5025"),
                      FooterText("Adajet Travel: 809-819-1525"),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        "Síguenos",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      SizedBox(height: 10),
                      FooterText("@adajetravel"),
                      FooterText("@santotejadard"),
                      FooterText("@2025montao"),
                      FooterText("@multisorteosrd"),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 40),
              const Divider(color: Colors.white24, thickness: 0.5),
              const SizedBox(height: 10),
              const Text(
                "© 2025 Multisorteos. Todos los derechos reservados.",
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// FOOTER TEXT WIDGET
// =====================================================================
class FooterText extends StatelessWidget {
  final String text;
  const FooterText(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white70, fontSize: 15),
      ),
    );
  }
}

class SorteoCard extends StatefulWidget {
  final Sorteo sorteo;
  const SorteoCard({super.key, required this.sorteo});

  @override
  State<SorteoCard> createState() => _SorteoCardState();
}

class _SorteoCardState extends State<SorteoCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
    final double percentRaw = widget.sorteo.totalTickets == 0
        ? 0.0
        : widget.sorteo.soldTickets / widget.sorteo.totalTickets;
    final double percentDisplay = ((percentRaw * 1000).truncate() / 10);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: 350, // Aumentado de 320 a 350
        transform: Matrix4.identity()..scale(_isHovered ? 1.03 : 1.0),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: _isHovered ? kGoldColor : Colors.grey.shade200,
            width: _isHovered ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: _isHovered
              ? kPremiumShadow
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RaffleDetailPage(initialSorteo: widget.sorteo),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // IMAGEN
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                child: Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: 3 / 5,
                      child: CachedNetworkImage(
                        imageUrl: widget.sorteo.imagenUrl ?? "",
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: Icon(Icons.image, size: 40),
                          ),
                        ),
                      ),
                    ),
                    if (widget.sorteo.hasPromo)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
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
                              const Icon(
                                Icons.flash_on,
                                color: Colors.red,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "PAGA ${widget.sorteo.promoBuy} Y RECIBE ${widget.sorteo.promoGet} GRATIS",
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // CONTENIDO
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      widget.sorteo.titulo,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20, // Aumentado ligeramente
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.event,
                          size: 18,
                          color: Color(0xFF6B7280),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.sorteo.fechaSorteo != null
                              ? 'Fecha del sorteo: ${DateFormat('dd/MM/yyyy').format(widget.sorteo.fechaSorteo!)}'
                              : "Sorteo al completar el 100% de la venta",
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // VALOR DEL TICKET
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Valor del ticket",
                          style: TextStyle(
                            fontSize: 15,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                        Text(
                          currency.format(widget.sorteo.precioTicket),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF16A34A),
                          ),
                        ),
                      ],
                    ),

                    if (!(widget.sorteo.fechaSorteo != null &&
                        widget.sorteo.fechaSorteo!.isBefore(
                          DateTime.now(),
                        ))) ...[
                      const SizedBox(height: 16),
                      _buildProgressBar(percentDisplay),

                      const SizedBox(height: 8),
                      Text(
                        "${percentDisplay.toStringAsFixed(1)}% vendido",
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF4B5563),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // BOTÓN
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed:
                            (widget.sorteo.fechaSorteo != null &&
                                widget.sorteo.fechaSorteo!.isBefore(
                                  DateTime.now(),
                                ))
                            ? null
                            : () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => RaffleDetailPage(
                                      initialSorteo: widget.sorteo,
                                    ),
                                  ),
                                );
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              (widget.sorteo.fechaSorteo != null &&
                                  widget.sorteo.fechaSorteo!.isBefore(
                                    DateTime.now(),
                                  ))
                              ? Colors.grey
                              : const Color(0xFF007BFF),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: _isHovered ? 8 : 4, // Elevación dinámica
                          shadowColor: const Color(
                            0xFF007BFF,
                          ).withValues(alpha: 0.4),
                        ),
                        child: Text(
                          (widget.sorteo.fechaSorteo != null &&
                                  widget.sorteo.fechaSorteo!.isBefore(
                                    DateTime.now(),
                                  ))
                              ? "FINALIZADO"
                              : "PARTICIPAR",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar(double percent) {
    final bool isHighDemand = percent > 70;
    return Container(
      height: 10,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(5),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: (percent / 100).clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isHighDemand
                  ? [kGoldColor, kGoldLight]
                  : [const Color(0xFF22C55E), const Color(0xFF16A34A)],
            ),
            borderRadius: BorderRadius.circular(5),
            boxShadow: [
              BoxShadow(
                color: isHighDemand
                    ? kGoldColor.withValues(alpha: 0.6)
                    : const Color(0xFF16A34A).withValues(alpha: 0.4),
                blurRadius: isHighDemand ? 12 : 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// HERO BUTTON COMPONENT (Con efecto de brillo dorado)
// =====================================================================
class _HeroButton extends StatefulWidget {
  final String text;
  final VoidCallback onTap;
  final bool isPrimary;

  const _HeroButton({
    required this.text,
    required this.onTap,
    required this.isPrimary,
  });

  @override
  State<_HeroButton> createState() => _HeroButtonState();
}

class _HeroButtonState extends State<_HeroButton>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: widget.isPrimary
          ? AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              transform: Matrix4.identity()..scale(_isHovered ? 1.05 : 1.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: _isHovered
                    ? [
                        BoxShadow(
                          color: kGoldColor.withValues(alpha: 0.4),
                          blurRadius: 15,
                          spreadRadius: 1,
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: kPrimaryColor.withValues(alpha: 0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: ElevatedButton(
                onPressed: widget.onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                ),
                child: Text(
                  widget.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            )
          : AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              transform: Matrix4.identity()..scale(_isHovered ? 1.05 : 1.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: _isHovered
                    ? [
                        BoxShadow(
                          color: kPrimaryColor.withValues(alpha: 0.1),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ]
                    : [],
              ),
              child: OutlinedButton(
                onPressed: widget.onTap,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: _isHovered ? kGoldColor : kPrimaryColor,
                    width: 1.6,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  widget.text,
                  style: TextStyle(
                    color: _isHovered ? kGoldColor : kPrimaryColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
    );
  }
}

// =====================================================================
// PREMIUM INFO CARD (Métodos de pago / Contacto)
// =====================================================================
class _PremiumInfoCard extends StatefulWidget {
  final String icon;
  final String titulo;
  final String desc;
  final bool isWhatsapp;

  const _PremiumInfoCard({
    required this.icon,
    required this.titulo,
    required this.desc,
    required this.isWhatsapp,
  });

  @override
  State<_PremiumInfoCard> createState() => _PremiumInfoCardState();
}

class _PremiumInfoCardState extends State<_PremiumInfoCard> {
  bool _isHovered = false;

  void _launchWhatsApp(String phone) async {
    final url = Uri.parse("https://wa.me/$phone");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 330,
        transform: Matrix4.identity()..scale(_isHovered ? 1.05 : 1.0),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _isHovered ? kGoldColor : Colors.grey.shade200,
            width: _isHovered ? 2 : 1,
          ),
          boxShadow: _isHovered
              ? kPremiumShadow
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Column(
          children: [
            Text(widget.icon, style: const TextStyle(fontSize: 40)),
            const SizedBox(height: 10),
            Text(
              widget.titulo.toUpperCase(),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: kPrimaryColor,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            if (!widget.isWhatsapp)
              Text(
                widget.desc,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.blueGrey,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            if (widget.isWhatsapp) ...[
              const SizedBox(height: 8),
              _whatsappBtn("Compras Web", "18496285498"),
              const SizedBox(height: 10),
              _whatsappBtn("Ventas WhatsApp", "18495395025"),
              const SizedBox(height: 10),
              _whatsappBtn("Adajet Travel", "18098191525"),
            ],
          ],
        ),
      ),
    );
  }

  Widget _whatsappBtn(String label, String phone) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _launchWhatsApp(phone),
        icon: const Icon(Icons.perm_phone_msg, size: 20, color: Colors.white),
        label: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF25D366),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
          shadowColor: const Color(0xFF25D366).withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
