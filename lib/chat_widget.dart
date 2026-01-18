import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async'; // Necesario para Timer y Future
import 'dart:typed_data';

/// Widget de chat compacto que se muestra como popup flotante
class ChatWidget extends StatefulWidget {
  const ChatWidget({super.key});

  @override
  State<ChatWidget> createState() => _ChatWidgetState();
}

class _ChatWidgetState extends State<ChatWidget>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  String? _sessionId;
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;
  bool _isSending = false;
  bool _isExpanded = false;
  bool _hasUserInfo = false; // Nueva bandera para verificar si tiene info
  RealtimeChannel? _channel;
  bool _isUploadingImage = false; // Estado para subida de imagen

  String _userName = '';
  String _userPhone = '';
  String _userEmail = '';
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _channel?.unsubscribe();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    if (_sessionId != null) return; // Ya inicializado

    setState(() => _isLoading = true);

    try {
      final response = await _supabase.rpc(
        'get_or_create_chat_session',
        params: {
          'p_user_name': _userName,
          'p_user_phone': _userPhone,
          'p_user_email': _userEmail.isEmpty ? null : _userEmail,
        },
      );

      if (response != null) {
        setState(() {
          _sessionId = response['id'];
          _hasUserInfo = true;
        });

        await _loadMessages();
        _subscribeToMessages();
        await _markMessagesAsRead();
      }
    } catch (e) {
      debugPrint('Error inicializando chat: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMessages() async {
    if (_sessionId == null) return;

    try {
      debugPrint('🔍 Cargando mensajes para sesión: $_sessionId');

      final response =
          await _supabase.rpc(
                'get_chat_messages',
                params: {'p_session_id': _sessionId, 'p_limit': 50},
              )
              as List<dynamic>;

      debugPrint('✅ Mensajes cargados: ${response.length}');

      setState(() {
        _messages = response.map((e) => e as Map<String, dynamic>).toList();
      });

      _scrollToBottom();
    } catch (e) {
      debugPrint('❌ Error cargando mensajes: $e');
    }
  }

  void _subscribeToMessages() {
    if (_sessionId == null) return;

    debugPrint('📡 Suscribiéndose a mensajes para sesión: $_sessionId');

    _channel = _supabase
        .channel('chat_messages_$_sessionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'session_id',
            value: _sessionId,
          ),
          callback: (payload) {
            debugPrint('💬 Nuevo mensaje recibido en tiempo real!');
            debugPrint('📨 Datos del mensaje: ${payload.newRecord}');

            final newMessage = payload.newRecord;

            // Evitar duplicados - no agregar si ya existe un mensaje con el mismo ID
            final messageId = newMessage['id'];
            final exists = _messages.any((m) => m['id'] == messageId);

            if (!exists && mounted) {
              setState(() {
                _messages.add(newMessage);
              });

              debugPrint(
                '✅ Mensaje agregado a la lista. Total mensajes: ${_messages.length}',
              );
              _scrollToBottom();

              // Si es del admin, marcar como leído y mostrar notificación
              if (newMessage['sender_type'] == 'admin') {
                _markMessagesAsRead();
                _showNewMessageNotification(newMessage['message']);
              }
            } else {
              debugPrint('⚠️ Mensaje duplicado o widget no montado, ignorando');
            }
          },
        )
        .subscribe((status, error) {
          debugPrint('📡 Estado de suscripción: $status');

          if (status == RealtimeSubscribeStatus.subscribed) {
            debugPrint('✅ Suscrito exitosamente a mensajes en tiempo real');
          } else if (status == RealtimeSubscribeStatus.closed) {
            debugPrint(
              '❌ Canal cerrado, intentando reconectar en 3 segundos...',
            );
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted && _sessionId != null) {
                debugPrint('🔄 Reintentando suscripción...');
                _subscribeToMessages();
              }
            });
          } else if (status == RealtimeSubscribeStatus.channelError) {
            debugPrint('❌ Error en el canal: $error');
          } else if (status == RealtimeSubscribeStatus.timedOut) {
            debugPrint('⏱️ Timeout en la suscripción');
          }
        });
  }

  Future<void> _markMessagesAsRead() async {
    if (_sessionId == null) return;

    try {
      await _supabase.rpc(
        'mark_messages_as_read',
        params: {'p_session_id': _sessionId},
      );
    } catch (e) {
      debugPrint('Error marcando mensajes como leídos: $e');
    }
  }

  Future<void> _pickImage() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true, // Importante para web
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes != null) {
          final fileName = file.name;
          final mimeType = 'image/${file.extension ?? "jpg"}';
          await _uploadImage(file.bytes!, fileName, mimeType);
        }
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al seleccionar imagen')),
        );
      }
    }
  }

  Future<void> _uploadImage(
    Uint8List bytes,
    String fileName,
    String mimeType,
  ) async {
    setState(() => _isUploadingImage = true);

    try {
      final ext = fileName.split('.').last;
      final uniqueName =
          '${DateTime.now().millisecondsSinceEpoch}_$_sessionId.$ext';

      // Subir archivo
      await _supabase.storage
          .from('chat-attachments')
          .uploadBinary(
            uniqueName,
            bytes,
            fileOptions: FileOptions(contentType: mimeType),
          );

      // Obtener URL pública
      final imageUrl = _supabase.storage
          .from('chat-attachments')
          .getPublicUrl(uniqueName);

      debugPrint('📸 Imagen subida: $imageUrl');

      // Enviar mensaje con adjunto
      await _sendMessage(attachmentUrl: imageUrl, attachmentType: 'image');
    } catch (e) {
      debugPrint('❌ Error uploading image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al subir imagen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Future<void> _sendMessage({
    String? attachmentUrl,
    String? attachmentType,
  }) async {
    final messageText = _messageController.text.trim();

    // Permitir enviar si hay texto O si hay adjunto
    if ((messageText.isEmpty && attachmentUrl == null) || _sessionId == null) {
      return;
    }

    if (messageText.isNotEmpty) _messageController.clear();

    debugPrint(
      '📤 Enviando mensaje: "${attachmentUrl != null ? '[IMAGEN]' : messageText}"',
    );

    // Agregar mensaje localmente de inmediato para mejor UX
    final tempMessage = {
      'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
      'session_id': _sessionId,
      'sender_type': 'user',
      'sender_name': _userName,
      'message': messageText,
      'attachment_url': attachmentUrl,
      'attachment_type': attachmentType,
      'is_read': false,
      'created_at': DateTime.now().toIso8601String(),
    };

    setState(() {
      _messages.add(tempMessage);
      _isSending = true;
    });

    debugPrint(
      '✅ Mensaje agregado localmente. Total mensajes: ${_messages.length}',
    );
    _scrollToBottom();

    try {
      final response = await _supabase.rpc(
        'send_chat_message',
        params: {
          'p_session_id': _sessionId,
          'p_message': messageText,
          'p_sender_type': 'user',
          'p_sender_name': _userName,
          'p_attachment_url': attachmentUrl,
          'p_attachment_type': attachmentType,
        },
      );

      debugPrint('✅ Respuesta del servidor: $response');

      // Actualizar el mensaje temporal con el real
      if (response != null && mounted) {
        setState(() {
          final index = _messages.indexWhere(
            (m) => m['id'] == tempMessage['id'],
          );
          if (index != -1) {
            _messages[index] = response as Map<String, dynamic>;
            debugPrint('✅ Mensaje actualizado en índice $index');
          }
        });
      }
    } catch (e) {
      debugPrint('❌ Error enviando mensaje: $e');
      // Remover el mensaje temporal si hubo error
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m['id'] == tempMessage['id']);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al enviar mensaje. Intenta de nuevo.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toggleChat() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  void _endChat() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finalizar Chat'),
        content: const Text(
          '¿Estás seguro de que deseas finalizar esta conversación?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _hasUserInfo = false;
                _sessionId = null;
                _messages.clear();
                _nameController.clear();
                _phoneController.clear();
                _emailController.clear();
                _userName = '';
                _userPhone = '';
                _userEmail = '';
              });
              _channel?.unsubscribe();
              debugPrint('🔚 Chat finalizado');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
  }

  void _submitUserInfo() {
    // Validar que nombre y teléfono no estén vacíos
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor ingresa tu nombre'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor ingresa tu teléfono'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Guardar la información
    setState(() {
      _userName = _nameController.text.trim();
      _userPhone = _phoneController.text.trim();
      _userEmail = _emailController.text.trim();
    });

    debugPrint('✅ Información guardada: $_userName, $_userPhone');

    // Inicializar el chat con la información
    _initializeChat();
  }

  void _showNewMessageNotification(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.message, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Nuevo mensaje de Soporte',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message.length > 50
                        ? '${message.substring(0, 50)}...'
                        : message,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF00C853),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showUserInfoForm() {
    showDialog(
      context: context,
      barrierDismissible: false, // No permitir cerrar haciendo clic afuera
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF00C853).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline,
                color: Color(0xFF00C853),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Información de contacto',
                style: TextStyle(fontSize: 20),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Para brindarte un mejor servicio, necesitamos algunos datos:',
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Nombre *',
                  hintText: 'Ingresa tu nombre completo',
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Color(0xFF00C853),
                      width: 2,
                    ),
                  ),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _phoneController,
                decoration: InputDecoration(
                  labelText: 'Teléfono *',
                  hintText: 'Ej: 809-555-1234',
                  prefixIcon: const Icon(Icons.phone),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Color(0xFF00C853),
                      width: 2,
                    ),
                  ),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Email (opcional)',
                  hintText: 'tu@email.com',
                  prefixIcon: const Icon(Icons.email),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Color(0xFF00C853),
                      width: 2,
                    ),
                  ),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              const Text(
                '* Campos requeridos',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.black45,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Limpiar los controladores
              _nameController.clear();
              _phoneController.clear();
              _emailController.clear();
            },
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              // Validar que nombre y teléfono no estén vacíos
              if (_nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Por favor ingresa tu nombre'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              if (_phoneController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Por favor ingresa tu teléfono'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              // Guardar la información
              setState(() {
                _userName = _nameController.text.trim();
                _userPhone = _phoneController.text.trim();
                _userEmail = _emailController.text.trim();
                _isExpanded = true;
              });

              Navigator.pop(context);

              // Inicializar el chat con la información
              _initializeChat();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C853),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Iniciar Chat',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineUserInfoForm() {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF00C853), Color(0xFF00E676)],
            ),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chat_bubble_outline,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Información de contacto',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Formulario
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Para brindarte un mejor servicio, necesitamos algunos datos:',
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Nombre *',
                    hintText: 'Ingresa tu nombre completo',
                    prefixIcon: const Icon(
                      Icons.person,
                      color: Color(0xFF00C853),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFF00C853),
                        width: 2,
                      ),
                    ),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _phoneController,
                  decoration: InputDecoration(
                    labelText: 'Teléfono *',
                    hintText: 'Ej: 809-555-1234',
                    prefixIcon: const Icon(
                      Icons.phone,
                      color: Color(0xFF00C853),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFF00C853),
                        width: 2,
                      ),
                    ),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'Email (opcional)',
                    hintText: 'tu@email.com',
                    prefixIcon: const Icon(
                      Icons.email,
                      color: Color(0xFF00C853),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFF00C853),
                        width: 2,
                      ),
                    ),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                const Text(
                  '* Campos requeridos',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black45,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitUserInfo,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00C853),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Iniciar Chat',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 20, // Cambiado de left a right
      bottom: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end, // Cambiado de start a end
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ventana de chat expandida
          if (_isExpanded)
            Container(
              width: 360,
              height: 500,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: !_hasUserInfo
                  ? _buildInlineUserInfoForm()
                  : Column(
                      children: [
                        // Header del chat
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF00C853), Color(0xFF00E676)],
                            ),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                            ),
                          ),
                          child: Row(
                            children: [
                              const CircleAvatar(
                                backgroundColor: Colors.white,
                                radius: 20,
                                child: Icon(
                                  Icons.support_agent,
                                  color: Color(0xFF00C853),
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Chat de Soporte',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'En línea',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.person,
                                  color: Colors.white,
                                ),
                                onPressed: _showUserInfoForm,
                                tooltip: 'Información de contacto',
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.logout,
                                  color: Colors.white,
                                ),
                                onPressed: _endChat,
                                tooltip: 'Finalizar Chat',
                              ),
                            ],
                          ),
                        ),

                        // Mensajes
                        Expanded(
                          child: _isLoading
                              ? const Center(child: CircularProgressIndicator())
                              : _messages.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.chat_bubble_outline,
                                        size: 48,
                                        color: Colors.grey[400],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        '¡Hola! ¿En qué podemos ayudarte?',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.all(12),
                                  itemCount: _messages.length,
                                  itemBuilder: (context, index) {
                                    final message = _messages[index];
                                    final isUser =
                                        message['sender_type'] == 'user';
                                    final timestamp = DateTime.parse(
                                      message['created_at'].toString(),
                                    );

                                    return _buildMessageBubble(
                                      message['message'] ?? '',
                                      isUser,
                                      timestamp,
                                      attachmentUrl: message['attachment_url'],
                                      attachmentType:
                                          message['attachment_type'],
                                    );
                                  },
                                ),
                        ),

                        // Input de mensaje
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(16),
                              bottomRight: Radius.circular(16),
                            ),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                icon: _isUploadingImage
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.grey,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.attach_file,
                                        color: Colors.grey,
                                      ),
                                onPressed: _isUploadingImage
                                    ? null
                                    : _pickImage,
                                tooltip: 'Adjuntar imagen',
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _messageController,
                                  decoration: InputDecoration(
                                    hintText: 'Escribe un mensaje...',
                                    hintStyle: TextStyle(
                                      color: Colors.grey[500],
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      borderSide: BorderSide.none,
                                    ),
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                  ),
                                  maxLines: null,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => _sendMessage(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0xFF00C853),
                                      Color(0xFF00E676),
                                    ],
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: _isSending
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.send,
                                          color: Colors.white,
                                        ),
                                  onPressed: _isSending ? null : _sendMessage,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),

          // Botón flotante
          MouseRegion(
            onEnter: (_) {
              setState(() => _isHovered = true);
              _animationController.forward();
            },
            onExit: (_) {
              setState(() => _isHovered = false);
              _animationController.reverse();
            },
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: GestureDetector(
                onTap: _toggleChat,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00C853), Color(0xFF00E676)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00C853).withOpacity(0.4),
                        blurRadius: _isHovered ? 20 : 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isExpanded ? Icons.close : Icons.chat_bubble_outline,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _isExpanded ? 'Cerrar chat' : 'Chatea con nosotros',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
    String message,
    bool isUser,
    DateTime timestamp, {
    String? attachmentUrl,
    String? attachmentType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              backgroundColor: const Color(0xFF00C853),
              radius: 14,
              child: const Icon(
                Icons.support_agent,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: isUser
                        ? const LinearGradient(
                            colors: [Color(0xFF00C853), Color(0xFF00E676)],
                          )
                        : null,
                    color: isUser ? null : Colors.grey[200],
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (attachmentUrl != null && attachmentType == 'image')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              attachmentUrl,
                              width: 200,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const SizedBox(
                                  width: 200,
                                  height: 150,
                                  child: Center(
                                    child: Icon(
                                      Icons.broken_image,
                                      size: 40,
                                      color: Colors.white70,
                                    ),
                                  ),
                                );
                              },
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return SizedBox(
                                      width: 200,
                                      height: 150,
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          value:
                                              loadingProgress
                                                      .expectedTotalBytes !=
                                                  null
                                              ? loadingProgress
                                                        .cumulativeBytesLoaded /
                                                    loadingProgress
                                                        .expectedTotalBytes!
                                              : null,
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    );
                                  },
                            ),
                          ),
                        ),
                      if (message.isNotEmpty)
                        Text(
                          message,
                          style: TextStyle(
                            color: isUser ? Colors.white : Colors.black87,
                            fontSize: 14,
                            height: 1.3,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('HH:mm').format(timestamp),
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 6),
            CircleAvatar(
              backgroundColor: Colors.grey[300],
              radius: 14,
              child: Icon(Icons.person, color: Colors.grey[700], size: 16),
            ),
          ],
        ],
      ),
    );
  }
}
