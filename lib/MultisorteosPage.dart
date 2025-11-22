import 'package:flutter/material.dart';

class MultisorteosPage extends StatefulWidget {
  const MultisorteosPage({super.key});

  @override
  State<MultisorteosPage> createState() => _MultisorteosPageState();
}

class _MultisorteosPageState extends State<MultisorteosPage> {
  final ScrollController _scrollController = ScrollController();

  // Keys para cada sección
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
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // bg-gray-50
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          children: [
            _buildHeader(),
            _buildHero(),
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
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------------
  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // LOGO
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.green.shade600,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text(
                    "M",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                "Multisorteos",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),

          // MENU
          Row(
            children: [
              _menuItem(
                "Acerca de Nosotros",
                () => _scrollToSection(acercaKey),
              ),
              _menuItem(
                "Ganadores Anteriores",
                () => _scrollToSection(ganadoresKey),
              ),
              _menuItem("Verificador", () => _scrollToSection(verificadorKey)),
              _menuItem("Métodos de Pago", () => _scrollToSection(metodosKey)),
              _menuItem("Contacto", () => _scrollToSection(contactoKey)),
              _menuItem("Preguntas", () => _scrollToSection(preguntasKey)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _menuItem(String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.blueGrey.shade600,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HERO
  // ---------------------------------------------------------------------------
  Widget _buildHero() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      child: Column(
        children: const [
          Text(
            "Muy pronto podrás ordenar tus tickets con nosotros via nuestra web",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 12),
          Text(
            "Multisorteos será tu plataforma para participar de forma segura y sencilla en los mejores sorteos de República Dominicana.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SORTEOS ACTUALES
  // ---------------------------------------------------------------------------
  Widget _buildSorteos() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 30),
      child: Column(
        children: [
          const Text(
            "Sorteos actuales",
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),

          // GRID ITEMS
          Wrap(
            spacing: 20,
            runSpacing: 20,
            children: [
              _buildSorteoItem(
                "MONTAO EN NAVIDAD",
                "RD\$2,000",
                "assets/imagenes/montaoennavidad.jpeg",
              ),
              _buildSorteoItem(
                "MONTAO RACING",
                "RD\$250",
                "assets/imagenes/montaoracing.jpeg",
              ),
              _buildSorteoItem(
                "Diciembre MONTAO",
                "RD\$500",
                "assets/imagenes/diciembremontao.jpeg",
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSorteoItem(String titulo, String precio, String imagen) {
    return Container(
      width: 330,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
                child: Image.asset(
                  imagen,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade600,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    "Activo",
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Valor del ticket",
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    Text(
                      precio,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ACERCA DE NOSOTROS
  // ---------------------------------------------------------------------------
  Widget _buildAcerca() {
    return Container(
      key: acercaKey,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
        child: Column(
          children: const [
            Text(
              "Acerca de Nosotros",
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text(
              "Multisorteos es una plataforma especializada en sorteos de todo tipo, con total seguridad y transparencia. Desde rifas de vehículos hasta otras experiencias y premios, concentramos la información oficial en un solo lugar para que puedas participar con confianza.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // GANADORES
  // ---------------------------------------------------------------------------
  Widget _buildGanadores() {
    return Container(
      key: ganadoresKey,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: const [
            Text(
              "Ganadores Anteriores",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              "Esta sección estará disponible próximamente con los resultados oficiales de los sorteos.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // VERIFICADOR
  // ---------------------------------------------------------------------------
  Widget _buildVerificador() {
    return Container(
      key: verificadorKey,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: const [
            Text(
              "Verificador",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text(
              "Muy pronto podrás verificar tus boletos en línea desde esta misma página.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MÉTODOS DE PAGO
  // ---------------------------------------------------------------------------
  Widget _buildMetodosPago() {
    return Container(
      key: metodosKey,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
        child: Column(
          children: [
            const Text(
              "Métodos de Pago Disponibles",
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),

            Wrap(
              spacing: 20,
              runSpacing: 20,
              children: [
                _buildMetodoItem(
                  "💵",
                  "Efectivo",
                  "Disponible inmediatamente a través de nuestros vendedores autorizados.",
                ),
                _buildMetodoItem(
                  "🏦",
                  "Transferencia Bancaria",
                  "Realiza tu pago mediante transferencia.\n\nWhatsapp: 849-628-5498\nWhatsapp: 849-539-5025\nTeléfono / Telegram: 809-979-3224",
                ),
                _buildMetodoItem(
                  "💳",
                  "Pago con Tarjeta",
                  "Aceptamos tarjetas de crédito y débito mediante link seguro.",
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetodoItem(String icon, String titulo, String descripcion) {
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
            titulo,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            descripcion,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CONTACTO
  // ---------------------------------------------------------------------------
  Widget _buildContacto() {
    return Container(
      key: contactoKey,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
        child: Column(
          children: [
            const Text(
              "Contáctanos",
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            Wrap(
              spacing: 20,
              runSpacing: 20,
              children: [
                _buildContactoItem("🌐", "Sitio Web", "Próximamente"),
                _buildContactoItem("📍", "Ubicación", "República Dominicana"),
                _buildContactoItem(
                  "📞",
                  "Teléfonos",
                  "Whatsapp: 849-628-5498\nWhatsapp: 849-539-5025\nTelegram / Teléfono: 809-979-3224",
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactoItem(String icon, String titulo, String desc) {
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
          Text(icon, style: const TextStyle(fontSize: 36)),
          const SizedBox(height: 10),
          Text(
            titulo,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            desc,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PREGUNTAS FRECUENTES
  // ---------------------------------------------------------------------------
  Widget _buildPreguntas() {
    return Container(
      key: preguntasKey,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
        child: Column(
          children: [
            const Text(
              "Preguntas Frecuentes",
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            _buildFAQ(
              "¿Cuándo podré comprar boletos en línea?",
              "Estamos preparando la plataforma de pagos. Tan pronto esté lista, avisaremos por nuestras redes sociales y en esta misma página.",
            ),

            _buildFAQ(
              "¿Los sorteos de Montao se gestionan aquí?",
              "Sí, Multisorteos concentrará la información oficial y los enlaces relacionados con los sorteos como Montao en Navidad, Montao Racing y Diciembre Montao.",
            ),

            _buildFAQ(
              "¿Dónde puedo ver más información y anuncios?",
              "Puedes seguir las cuentas oficiales: @adajetravel, @santotejadard, @2025montao y @multisorteosrd.",
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
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(respuesta, style: const TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // FOOTER
  // ---------------------------------------------------------------------------
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
              // Columna 1
              SizedBox(
                width: 250,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.green.shade500,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: Text(
                              "M",
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          "Multisorteos",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "Plataforma especializada en sorteos de todo tipo, con total seguridad y transparencia.",
                      style: TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        "Instagram",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),

              // Columna 2 - Secciones
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    "Secciones",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 10),
                  FooterText("Inicio"),
                  FooterText("Sorteos actuales"),
                  FooterText("Verificador"),
                  FooterText("Métodos de pago"),
                  FooterText("Preguntas frecuentes"),
                ],
              ),

              // Columna 3 - Contacto
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    "Contacto",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 10),
                  FooterText("Sitio web: Próximamente"),
                  FooterText("Ubicación: República Dominicana"),
                  FooterText("Whatsapp: 849-628-5498"),
                  FooterText("Whatsapp: 849-539-5025"),
                  FooterText("Teléfono / Telegram: 809-979-3224"),
                ],
              ),

              // Columna 4 - Síguenos
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    "Síguenos",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
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

// Widget auxiliar para el texto del footer
class FooterText extends StatelessWidget {
  final String text;
  const FooterText(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white70, fontSize: 13),
      ),
    );
  }
}
