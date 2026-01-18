-- ============================================================================
-- POLÍTICAS RLS PARA CHAT - EJECUTAR EN SUPABASE SQL EDITOR
-- ============================================================================

-- IMPORTANTE: Ejecuta estas políticas UNA POR UNA en el SQL Editor de Supabase
-- Si alguna ya existe, simplemente ignora el error y continúa con la siguiente

-- ============================================================================
-- PASO 1: Eliminar políticas existentes (si las hay)
-- ============================================================================

DROP POLICY IF EXISTS "users_can_read_messages" ON chat_messages;
DROP POLICY IF EXISTS "users_can_insert_messages" ON chat_messages;
DROP POLICY IF EXISTS "admins_can_insert_messages" ON chat_messages;
DROP POLICY IF EXISTS "users_can_read_own_sessions" ON chat_sessions;
DROP POLICY IF EXISTS "users_can_update_own_sessions" ON chat_sessions;

-- ============================================================================
-- PASO 2: Crear nuevas políticas
-- ============================================================================

-- Permitir a todos leer mensajes
CREATE POLICY "users_can_read_messages" 
ON chat_messages FOR SELECT
TO authenticated, anon
USING (true);

-- Permitir a usuarios insertar mensajes como 'user'
CREATE POLICY "users_can_insert_messages" 
ON chat_messages FOR INSERT
TO authenticated, anon
WITH CHECK (sender_type = 'user');

-- Permitir a usuarios autenticados insertar mensajes como 'admin'
-- (esto se controlará en tu app, solo usuarios admin podrán hacerlo)
CREATE POLICY "admins_can_insert_messages" 
ON chat_messages FOR INSERT
TO authenticated
WITH CHECK (sender_type = 'admin');

-- Permitir a todos leer sesiones
CREATE POLICY "users_can_read_own_sessions" 
ON chat_sessions FOR SELECT
TO authenticated, anon
USING (true);

-- Permitir actualizar sesiones
CREATE POLICY "users_can_update_own_sessions" 
ON chat_sessions FOR UPDATE
TO authenticated, anon
USING (true);

-- ============================================================================
-- PASO 3: Verificar que las políticas se crearon correctamente
-- ============================================================================

-- Ejecuta esta query para ver todas las políticas:
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd
FROM pg_policies
WHERE tablename IN ('chat_messages', 'chat_sessions')
ORDER BY tablename, policyname;

-- Deberías ver 5 políticas en total:
-- 3 para chat_messages
-- 2 para chat_sessions

-- ============================================================================
-- FIN
-- ============================================================================
