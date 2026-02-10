-- 🚨 FIX FOR AMBIGUOUS FUNCTION ERROR 🚨
-- This script drops all variations of reserve_tickets to ensure a clean slate
-- and then recreates the correct version with the 'email' parameter.

-- 1. Drop the old version (without email parameter) which causes the ambiguity
DROP FUNCTION IF EXISTS public.reserve_tickets(uuid, int[], text, text, text, int);

-- 2. Drop the new version (with email parameter) just to be sure we can recreate it clean
DROP FUNCTION IF EXISTS public.reserve_tickets(uuid, int[], text, text, text, int, text);

-- 3. Recreate the Correct Function
CREATE OR REPLACE FUNCTION public.reserve_tickets(
    p_sorteo_id UUID,
    p_numbers INT[],
    p_buyer_nombre TEXT,
    p_buyer_cedula TEXT,
    p_buyer_telefono TEXT,
    p_hold_minutes INT DEFAULT 30,
    p_buyer_email TEXT DEFAULT NULL
) 
RETURNS TABLE (order_id UUID, status TEXT) 
LANGUAGE plpgsql 
SECURITY DEFINER 
AS $$
DECLARE
    v_order_id UUID;
    v_unavailable INT[];
BEGIN
    -- Verificar disponibilidad
    SELECT array_agg(numero)
    INTO v_unavailable
    FROM boletos
    WHERE sorteo_id = p_sorteo_id
      AND numero = ANY(p_numbers)
      AND estado != 'available';

    IF v_unavailable IS NOT NULL THEN
        RETURN QUERY SELECT NULL::UUID, 'unavailable';
        RETURN;
    END IF;

    -- Crear orden
    INSERT INTO ordenes (sorteo_id, buyer_nombre, buyer_cedula, buyer_telefono, buyer_email, status, created_at, hold_minutes)
    VALUES (p_sorteo_id, p_buyer_nombre, p_buyer_cedula, p_buyer_telefono, p_buyer_email, 'pending', NOW(), p_hold_minutes)
    RETURNING id INTO v_order_id;

    -- Reservar boletos
    -- Nota: 'sold_at' se dejaba en NULL en la versión original de reserva, 
    -- pero si la lógica actual lo requiere así, se mantiene. 
    -- Idealmente sold_at debería ser al confirmar, pero respetamos la lógica de add_email_column_migration.sql
    UPDATE boletos
    SET estado = 'reserved',
        order_id = v_order_id,
        buyer_nombre = p_buyer_nombre,
        buyer_cedula = p_buyer_cedula,
        buyer_telefono = p_buyer_telefono,
        sold_at = NOW() 
    WHERE sorteo_id = p_sorteo_id
      AND numero = ANY(p_numbers);

    -- Retornar éxito
    RETURN QUERY SELECT v_order_id, 'success';
END;
$$;

-- 4. Grant permissions
GRANT EXECUTE ON FUNCTION public.reserve_tickets(uuid, int[], text, text, text, int, text) TO authenticated, service_role, anon;

-- 5. Notify to reload schema cache
NOTIFY pgrst, 'reload schema';
