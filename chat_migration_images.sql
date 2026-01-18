-- Migración para soporte de imágenes en chat
-- Fecha: 2026-01-18

--------------------------------------------------------------------------------
-- 1. Modificar tabla chat_messages
--------------------------------------------------------------------------------

-- Agregar columnas para adjuntos si no existen
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'chat_messages' AND column_name = 'attachment_url') THEN
        ALTER TABLE chat_messages ADD COLUMN attachment_url TEXT;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'chat_messages' AND column_name = 'attachment_type') THEN
        ALTER TABLE chat_messages ADD COLUMN attachment_type TEXT CHECK (attachment_type IN ('image', 'file', 'video', 'audio'));
    END IF;
END $$;

--------------------------------------------------------------------------------
-- 2. Configurar Storage Bucket
--------------------------------------------------------------------------------

-- Insertar bucket 'chat-attachments' si no existe
INSERT INTO storage.buckets (id, name, public)
VALUES ('chat-attachments', 'chat-attachments', true)
ON CONFLICT (id) DO NOTHING;

--------------------------------------------------------------------------------
-- 3. Políticas de Acceso a Storage (RLS)
--------------------------------------------------------------------------------

-- Eliminar políticas antiguas si existen para evitar conflictos
DROP POLICY IF EXISTS "Public Chat Images Access" ON storage.objects;
DROP POLICY IF EXISTS "Allow Upload Chat Images" ON storage.objects;
DROP POLICY IF EXISTS "Allow Update Chat Images" ON storage.objects;

-- POLÍTICA 1: Permitir ver imágenes (SELECT) a todos
CREATE POLICY "Public Chat Images Access"
ON storage.objects FOR SELECT
USING ( bucket_id = 'chat-attachments' );

-- POLÍTICA 2: Permitir subir imágenes (INSERT) a todos (auth y anon)
CREATE POLICY "Allow Upload Chat Images"
ON storage.objects FOR INSERT
WITH CHECK ( bucket_id = 'chat-attachments' );

-- POLÍTICA 3: Permitir actualizar (UPDATE)
CREATE POLICY "Allow Update Chat Images"
ON storage.objects FOR UPDATE
USING ( bucket_id = 'chat-attachments' );

--------------------------------------------------------------------------------
-- 4. Actualizar funciones RPC para incluir nuevos campos
--------------------------------------------------------------------------------

-- Eliminar funciones antiguas para evitar conflictos de firma
DROP FUNCTION IF EXISTS public.get_chat_messages(UUID, INT);
DROP FUNCTION IF EXISTS public.send_chat_message(UUID, TEXT, TEXT, TEXT, UUID);
DROP FUNCTION IF EXISTS public.send_chat_message(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, UUID);

-- Actualizar get_chat_messages
CREATE OR REPLACE FUNCTION public.get_chat_messages(
  p_session_id UUID,
  p_limit INT DEFAULT 50
) RETURNS TABLE(
  id UUID,
  session_id UUID,
  sender_type TEXT,
  sender_id UUID,
  sender_name TEXT,
  message TEXT,
  is_read BOOLEAN,
  created_at TIMESTAMPTZ,
  attachment_url TEXT,
  attachment_type TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    cm.id,
    cm.session_id,
    cm.sender_type,
    cm.sender_id,
    cm.sender_name,
    cm.message,
    cm.is_read,
    cm.created_at,
    cm.attachment_url,
    cm.attachment_type
  FROM public.chat_messages cm
  WHERE cm.session_id = p_session_id
  ORDER BY cm.created_at ASC
  LIMIT p_limit;
END;
$$;

-- Actualizar send_chat_message
CREATE OR REPLACE FUNCTION public.send_chat_message(
  p_session_id UUID,
  p_message TEXT,
  p_sender_type TEXT,
  p_sender_name TEXT,
  p_attachment_url TEXT DEFAULT NULL,
  p_attachment_type TEXT DEFAULT NULL,
  p_sender_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_message_id UUID;
  v_message_json JSONB;
  v_sender_id UUID;
BEGIN
  -- Determinar sender_id
  v_sender_id := COALESCE(p_sender_id, auth.uid());

  -- Insertar mensaje
  INSERT INTO public.chat_messages (
    session_id,
    sender_type,
    sender_id,
    sender_name,
    message,
    attachment_url,
    attachment_type
  ) VALUES (
    p_session_id,
    p_sender_type,
    v_sender_id,
    p_sender_name,
    p_message,
    p_attachment_url,
    p_attachment_type
  ) RETURNING id INTO v_message_id;

  -- Actualizar sesión
  UPDATE public.chat_sessions
  SET 
    last_message_at = NOW(),
    updated_at = NOW(),
    unread_count = CASE WHEN p_sender_type != 'admin' THEN unread_count + 1 ELSE unread_count END
  WHERE id = p_session_id;

  -- Retornar mensaje
  SELECT to_jsonb(cm.*) INTO v_message_json
  FROM public.chat_messages cm
  WHERE id = v_message_id;

  RETURN v_message_json;
END;
$$;

-- Permisos
GRANT EXECUTE ON FUNCTION public.get_chat_messages(UUID, INT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.send_chat_message(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, UUID) TO authenticated, anon;
