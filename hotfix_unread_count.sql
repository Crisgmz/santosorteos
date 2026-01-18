-- HOTFIX: Agregar columna faltante unread_count y corregir función
-- Ejecutar en Supabase SQL Editor

-- 1. Asegurar que las columnas existan en chat_sessions
ALTER TABLE public.chat_sessions 
ADD COLUMN IF NOT EXISTS unread_count INT DEFAULT 0;

ALTER TABLE public.chat_sessions 
ADD COLUMN IF NOT EXISTS last_message_at TIMESTAMPTZ DEFAULT NOW();

-- 2. Asegurar que las columnas para adjuntos existan (por si acaso falló el anterior)
ALTER TABLE public.chat_messages 
ADD COLUMN IF NOT EXISTS attachment_url TEXT;

ALTER TABLE public.chat_messages 
ADD COLUMN IF NOT EXISTS attachment_type TEXT;

-- 3. Recrear bucket si no existe
INSERT INTO storage.buckets (id, name, public)
VALUES ('chat-attachments', 'chat-attachments', true)
ON CONFLICT (id) DO NOTHING;

-- 4. Crear o Reemplazar la función send_chat_message
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
BEGIN
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
    COALESCE(p_sender_id, auth.uid()),
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
    unread_count = CASE 
      WHEN p_sender_type != 'admin' THEN COALESCE(unread_count, 0) + 1 
      ELSE COALESCE(unread_count, 0) 
    END
  WHERE id = p_session_id;

  -- Retornar mensaje
  SELECT to_jsonb(cm.*) INTO v_message_json
  FROM public.chat_messages cm
  WHERE id = v_message_id;

  RETURN v_message_json;
END;
$$;
