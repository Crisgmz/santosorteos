# Sistema de Chat - SantoSorteos

## Descripción

Sistema de chat en tiempo real integrado en la aplicación SantoSorteos que permite a los usuarios comunicarse directamente con el equipo de soporte mediante un **widget flotante compacto** que se expande al hacer clic.

## Características

- ✅ **Chat compacto flotante** que no cubre toda la pantalla
- ✅ **Expansión suave** al hacer clic en el botón
- ✅ **Chat en tiempo real** usando Supabase Realtime
- ✅ **Diseño moderno** con animaciones y efectos visuales
- ✅ **Ventana de 360x500px** perfecta para conversaciones
- ✅ **Gestión de sesiones** automática
- ✅ **Información de contacto** opcional del usuario
- ✅ **Historial de mensajes** persistente
- ✅ **Indicadores de lectura** para mensajes

## Componentes

### 1. Base de Datos (`chat_database.sql`)

Estructura de tablas:

- **`chat_sessions`**: Almacena las sesiones de chat de los usuarios
  - `id`: UUID único de la sesión
  - `user_id`: Referencia al usuario autenticado (opcional)
  - `user_name`: Nombre del usuario
  - `user_phone`: Teléfono del usuario
  - `user_email`: Email del usuario
  - `status`: Estado de la sesión (active, closed, archived)
  - `created_at`, `updated_at`, `last_message_at`: Timestamps

- **`chat_messages`**: Almacena los mensajes del chat
  - `id`: UUID único del mensaje
  - `session_id`: Referencia a la sesión
  - `sender_type`: Tipo de remitente (user, admin)
  - `sender_id`: ID del usuario que envía
  - `sender_name`: Nombre del remitente
  - `message`: Contenido del mensaje
  - `is_read`: Indicador de lectura
  - `created_at`: Timestamp

### 2. Widget Compacto (`chat_widget.dart`)

Widget principal que maneja todo el chat:
- **Estado colapsado**: Botón flotante con texto "Chatea con nosotros"
- **Estado expandido**: Ventana de chat de 360x500px con:
  - Header verde con título, estado en línea y botones
  - Área de mensajes con scroll automático
  - Input de mensaje con botón de envío
- Animaciones suaves de expansión/colapso
- Gestión completa de la sesión y mensajes en tiempo real

### 3. Widget Wrapper (`chat_popup_widget.dart`)

Wrapper simple que integra el ChatWidget en la aplicación.

## Instalación

### 1. Ejecutar el script SQL en Supabase

```bash
# Conectarse a tu proyecto de Supabase y ejecutar:
psql -h [tu-host] -U postgres -d postgres -f chat_database.sql
```

O copiar y pegar el contenido de `chat_database.sql` en el SQL Editor de Supabase.

### 2. Verificar las funciones RPC

Asegúrate de que las siguientes funciones estén creadas:

- `get_or_create_chat_session()`
- `send_chat_message()`
- `mark_messages_as_read()`
- `get_chat_messages()`

### 3. Configurar Realtime en Supabase

1. Ve a Database → Replication
2. Habilita Realtime para las tablas:
   - `chat_sessions`
   - `chat_messages`

### 4. Integración en la App

El widget ya está integrado en `MultisorteosPage.dart`. Si necesitas agregarlo en otras páginas:

```dart
import 'chat_popup_widget.dart';

// En el build method, dentro de un Stack:
Stack(
  children: [
    // Tu contenido aquí
    const ChatPopupWidget(),
  ],
)
```

## Uso

### Para Usuarios

1. El botón "Chatea con nosotros" aparece en la esquina inferior izquierda
2. Al hacer clic, se expande una ventana de chat compacta (360x500px)
3. Se crea automáticamente una sesión de chat
4. Los usuarios pueden enviar mensajes inmediatamente
5. La ventana permanece flotante sin cubrir toda la pantalla
6. Pueden cerrar el chat haciendo clic en la X o en el botón nuevamente
7. Opcionalmente, pueden agregar su información de contacto haciendo clic en el icono de persona

### Para Administradores

Para responder a los mensajes, necesitarás crear una interfaz de administración que:

1. Liste todas las sesiones activas
2. Permita ver los mensajes de cada sesión
3. Permita enviar mensajes como admin

Ejemplo de consulta para obtener sesiones activas:

```dart
final sessions = await supabase
  .from('chat_sessions')
  .select('*')
  .eq('status', 'active')
  .order('last_message_at', ascending: false);
```

Ejemplo de envío de mensaje como admin:

```dart
await supabase.rpc('send_chat_message', params: {
  'p_session_id': sessionId,
  'p_message': 'Hola, ¿en qué puedo ayudarte?',
  'p_sender_type': 'admin',
  'p_sender_name': 'Soporte',
});
```

## Funciones RPC Disponibles

### `get_or_create_chat_session()`

Obtiene la sesión activa del usuario o crea una nueva.

**Parámetros:**
- `p_user_name` (opcional): Nombre del usuario
- `p_user_phone` (opcional): Teléfono del usuario
- `p_user_email` (opcional): Email del usuario

**Retorna:** Objeto de sesión

### `send_chat_message()`

Envía un mensaje en una sesión.

**Parámetros:**
- `p_session_id`: ID de la sesión
- `p_message`: Contenido del mensaje
- `p_sender_type`: 'user' o 'admin'
- `p_sender_name`: Nombre del remitente

**Retorna:** Objeto del mensaje creado

### `mark_messages_as_read()`

Marca todos los mensajes de admin como leídos en una sesión.

**Parámetros:**
- `p_session_id`: ID de la sesión

**Retorna:** Número de mensajes marcados

### `get_chat_messages()`

Obtiene los mensajes de una sesión.

**Parámetros:**
- `p_session_id`: ID de la sesión
- `p_limit` (opcional, default: 50): Límite de mensajes

**Retorna:** Lista de mensajes

## Personalización

### Cambiar Colores

En `chat_widget.dart`, busca:

```dart
const Color(0xFF00C853)  // Verde principal
const Color(0xFF00E676)  // Verde claro
```

### Cambiar Posición del Popup

En `chat_widget.dart`, en el método `build()`, modifica el `Positioned`:

```dart
Positioned(
  left: 20,   // Cambiar a right: 20 para moverlo a la derecha
  bottom: 20, // Ajustar altura
  child: ...
)
```

### Cambiar Tamaño de la Ventana

En `chat_widget.dart`, busca:

```dart
Container(
  width: 360,  // Ancho de la ventana
  height: 500, // Alto de la ventana
  ...
)
```

### Modificar Límite de Mensajes

En `chat_widget.dart`, en el método `_loadMessages()`:

```dart
params: {'p_session_id': _sessionId, 'p_limit': 50}, // Cambiar 50
```

## Seguridad

- ✅ Row Level Security (RLS) habilitado en todas las tablas
- ✅ Los usuarios solo pueden ver sus propias sesiones
- ✅ Las funciones RPC usan `SECURITY DEFINER` para control de acceso
- ✅ Validación de mensajes vacíos
- ✅ Autenticación opcional (funciona con usuarios anónimos)

## Próximas Mejoras

- [ ] Panel de administración para gestionar chats
- [ ] Notificaciones push para nuevos mensajes
- [ ] Soporte para archivos adjuntos
- [ ] Indicador de "escribiendo..."
- [ ] Búsqueda en historial de mensajes
- [ ] Exportar conversaciones
- [ ] Chatbot automático para respuestas frecuentes

## Soporte

Para preguntas o problemas, contacta al equipo de desarrollo.
