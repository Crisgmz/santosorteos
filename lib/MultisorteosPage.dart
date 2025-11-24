import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/foundation.dart';
import 'dart:html' as html;

import 'ticket_image_saver_stub.dart'
    if (dart.library.html) 'ticket_image_saver_web.dart'
    if (dart.library.io) 'ticket_image_saver_io.dart'
    as ticket_saver;

import 'data/models.dart';
import 'data/raffles_repository.dart';
import 'raffle_detail_page.dart' hide SingleChildScrollView;

// =====================================================================
// ESTILOS GLOBALES
// =====================================================================

const Color kPrimaryColor = Color(0xFF007BFF);
const Color kBackgroundColor = Color(0xFFF8FAFC);

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
  const MultisorteosPage({super.key});

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

  final inicioKey = GlobalKey();
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
        curve: Curves.easeInOut,
        alignment: 0.1,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _rafflesFuture = _repo.fetchActiveRaffles();
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

    // WEB: abrir imagen en pestaña nueva
    if (kIsWeb) {
      final blob = html.Blob([bytes], 'image/jpeg');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.window.open(url, '_blank');
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
      backgroundColor: kBackgroundColor,
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
        color: Colors.white.withOpacity(0.96),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
                  _menuItem("Inicio", () => _scrollToSection(inicioKey)),
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
                    "Métodos de Pago",
                    () => _scrollToSection(metodosKey),
                  ),
                  _menuItem("Contacto", () => _scrollToSection(contactoKey)),
                  _menuItem("Preguntas", () => _scrollToSection(preguntasKey)),
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
  // INICIO (HERO)
  // =====================================================================
  Widget _buildInicio() {
    return Container(
      key: inicioKey,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, Colors.blue.shade50],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 900;
          final info = Column(
            crossAxisAlignment: isNarrow
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              const Text(
                "MULTISORTEOS",
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: kPrimaryColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                "PLATAFORMA OFICIAL DE RIFAS Y DINÁMICAS",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                  letterSpacing: 0.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              const Text(
                "Participa, verifica y sigue cada sorteo desde un solo lugar.\nRápido, seguro y transparente.",
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.black54,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ElevatedButton(
                    onPressed: () => _scrollToSection(ganadoresKey),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 6,
                      shadowColor: kPrimaryColor.withOpacity(0.4),
                    ),
                    child: const Text(
                      "VER SORTEOS Y GANADORES",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => _scrollToSection(contactoKey),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kPrimaryColor, width: 1.6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      "HABLAR POR WHATSAPP",
                      style: TextStyle(
                        color: kPrimaryColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );

          final logo = ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              'assets/imagenes/logo_completo.png',
              height: 180,
              fit: BoxFit.contain,
            ),
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [info, const SizedBox(height: 24), logo],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: info),
              const SizedBox(width: 30),
              Expanded(
                child: Align(alignment: Alignment.centerRight, child: logo),
              ),
            ],
          );
        },
      ),
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
      child: Column(
        children: [
          const Text(
            "SORTEOS ACTUALES",
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

              if (sorteos.isEmpty) {
                return const Text(
                  "AÚN NO HAY SORTEOS ACTIVOS.",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                );
              }

              return Column(
                children: [
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 48,
                    runSpacing: 48,
                    children: sorteos
                        .map((s) => _buildSorteoItem(context, s))
                        .toList(),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSorteoItem(BuildContext context, Sorteo sorteo) {
    final currency = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');

    final double percentRaw = sorteo.totalTickets == 0
        ? 0.0
        : sorteo.soldTickets / sorteo.totalTickets;

    final double percentDisplay = ((percentRaw * 1000).truncate() / 10);

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
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
              builder: (_) => RaffleDetailPage(initialSorteo: sorteo),
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
              child: AspectRatio(
                aspectRatio: 3 / 5,
                child: Image.network(
                  sorteo.imagenUrl ?? "",
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.grey.shade200,
                    child: const Center(child: Icon(Icons.image, size: 40)),
                  ),
                ),
              ),
            ),

            // CONTENIDO
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    sorteo.titulo,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.event, size: 18, color: Color(0xFF6B7280)),
                      SizedBox(width: 6),
                      Text(
                        "CON LA VENTA DEL 100%",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // VALOR DEL TICKET
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Valor del ticket",
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                      Text(
                        currency.format(sorteo.precioTicket),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF16A34A),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),
                  _buildPrettyProgressBar(percentDisplay),
                  const SizedBox(height: 6),
                  Text(
                    "${percentDisplay.toStringAsFixed(1)}% vendido",
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // BOTÓN
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                RaffleDetailPage(initialSorteo: sorteo),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                        elevation: 4,
                        shadowColor: kPrimaryColor.withOpacity(0.4),
                      ),
                      child: const Text(
                        "BOLETOS DISPONIBLES",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                          color: Colors.white,
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
    );
  }

  Widget _buildPrettyProgressBar(double percentDisplay) {
    final factor = (percentDisplay / 100).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Stack(
        children: [
          Container(height: 22, color: const Color(0xFFE5E7EB)),
          FractionallySizedBox(
            widthFactor: factor,
            child: Container(
              height: 22,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF38BDF8), kPrimaryColor],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Center(
              child: Text(
                "${percentDisplay.toStringAsFixed(1)}%",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // ACERCA
  // =====================================================================
  Widget _buildAcerca() {
    return Container(
      key: acercaKey,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
      color: Colors.white,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: kPrimaryColor,
              shape: BoxShape.circle,
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
    );
  }

  // =====================================================================
  // GANADORES
  // =====================================================================
  Widget _buildGanadores() {
    return Container(
      key: ganadoresKey,
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 40, horizontal: 16),
        child: Column(
          children: [
            Text(
              "GANADORES ANTERIORES",
              style: kTitleSection,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              "Muy pronto podrás ver el historial de ganadores y sorteos completados.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
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
                  color: Colors.black.withOpacity(0.05),
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
                      backgroundColor: kPrimaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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
        Text(
          first.buyerNombre ?? 'Comprador',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
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
        : 'Pendiente de pago';
    final bool isReserved = t.estado.toLowerCase() == 'reserved';
    final statusText = isReserved ? "Reservado" : "Pago verificado";
    final statusColor = isReserved ? Colors.amberAccent : Colors.white;
    final statusIcon = isReserved ? Icons.lock_clock : Icons.check_circle;
    final bg = t.sorteoImagenUrl;

    final key = _ticketKeys[_ticketKeyId(t)] ?? GlobalKey();
    _ticketKeys.putIfAbsent(_ticketKeyId(t), () => key);

    // ======== ENMASCARAR DATOS SENSIBLES ========
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
              color: Colors.black.withOpacity(0.08),
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
                          Colors.black.withOpacity(0.55),
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
                          color: statusColor.withOpacity(0.2),
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
                            backgroundColor: kPrimaryColor.withOpacity(0.9),
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
    );
  }

  Widget _buildMetodoItem(
    String icon,
    String titulo,
    String desc, {
    bool isWhatsapp = false,
  }) {
    return Container(
      width: 330,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 40)),
          const SizedBox(height: 10),
          Text(
            titulo.toUpperCase(),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: kPrimaryColor,
            ),
          ),
          const SizedBox(height: 12),
          if (!isWhatsapp)
            Text(
              desc,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 15),
            ),
          if (isWhatsapp) ...[
            whatsappButton("WhatsApp Vendedor #1", "18496285498"),
            const SizedBox(height: 12),
            whatsappButton("WhatsApp Vendedor #2", "18495395025"),
          ],
        ],
      ),
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
    );
  }

  Widget _buildContactoItem(
    String icon,
    String titulo,
    String desc, {
    bool isWhatsapp = false,
  }) {
    return Container(
      width: 330,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 40)),
          const SizedBox(height: 10),
          Text(
            titulo.toUpperCase(),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: kPrimaryColor,
            ),
          ),
          const SizedBox(height: 12),
          if (!isWhatsapp)
            Text(
              desc,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 15),
            ),
          if (isWhatsapp) ...[
            whatsappButton("WhatsApp Vendedor #1", "18496285498"),
            const SizedBox(height: 12),
            whatsappButton("WhatsApp Vendedor #2", "18495395025"),
          ],
        ],
      ),
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
              "Síguenos en Instagram como @multisorteosrd para noticias, lanzamientos y ganadores.",
            ),
          ],
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
          colors: [Color(0xFF0F172A), Color(0xFF020617)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 50),
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
                      "Plataforma especializada en rifas, dinámicas y sorteos transparentes.",
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
                  FooterText("WhatsApp: 849-628-5498"),
                  FooterText("WhatsApp: 849-539-5025"),
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
