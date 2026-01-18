-- ============================================================================
-- SCRIPT PARA CORREGIR AMBIGÜEDAD DE LA FUNCIÓN SEND_CHAT_MESSAGE
-- ============================================================================

-- 1. Eliminar AMBAS versiones conflictivas de la función
DROP FUNCTION IF EXISTS public.send_chat_message(uuid, text, text, text);
DROP FUNCTION IF EXISTS public.send_chat_message(uuid, text, text, text, text, text, uuid);

-- 2. Asegurar que las columnas opcionales existan en la tabla (para evitar errores futuros)
ALTER TABLE public.chat_messages ADD COLUMN IF NOT EXISTS sender_id uuid;
ALTER TABLE public.chat_messages ADD COLUMN IF NOT EXISTS attachment_url text;
ALTER TABLE public.chat_messages ADD COLUMN IF NOT EXISTS attachment_type text;

-- 3. Crear la función ÚNICA con parámetros opcionales
-- Esto permite llamar la función con 4 argumentos (como hace Flutter ahora)
-- O con 7 argumentos (como haría una versión futura con adjuntos)
CREATE OR REPLACE FUNCTION public.send_chat_message(
    p_session_id uuid,
    p_message text,
    p_sender_type text,      -- 'user' o 'admin'
    p_sender_name text,
    p_attachment_url text DEFAULT NULL,   -- Valor por defecto NULL
    p_attachment_type text DEFAULT NULL,  -- Valor por defecto NULL
    p_sender_id uuid DEFAULT NULL         -- Valor por defecto NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_message_id uuid;
    v_message_json jsonb;
BEGIN
    -- Insertar el mensaje
    INSERT INTO public.chat_messages (
        session_id,
        sender_type,
        sender_name,
        sender_id,
        message,
        attachment_url,
        attachment_type
    ) VALUES (
        p_session_id,
        p_sender_type,
        p_sender_name,
        p_sender_id,
        p_message,
        p_attachment_url,
        p_attachment_type
    )
    RETURNING id INTO v_message_id;

    -- Actualizar la sesión para que suba en la lista
    UPDATE public.chat_sessions
    SET last_message_at = NOW(),
        updated_at = NOW()
    WHERE id = p_session_id;

    -- Retornar el objeto mensaje completo
    SELECT to_jsonb(cm.*) INTO v_message_json
    FROM public.chat_messages cm
    WHERE cm.id = v_message_id;

    RETURN v_message_json;
END;
$$;
