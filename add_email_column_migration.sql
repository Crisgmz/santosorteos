-- 🚨 CORRECCIÓN URGENTE: ERROR "sorteo_id"
-- Ejecuta este script nuevamente para arreglar el error de "null value in column sorteo_id"

-- Actualizamos la función reserve_tickets para incluir el sorteo_id al crear la orden
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

    -- Crear orden (CORREGIDO: Ahora incluimos sorteo_id)
    INSERT INTO ordenes (sorteo_id, buyer_nombre, buyer_cedula, buyer_telefono, buyer_email, status, created_at)
    VALUES (p_sorteo_id, p_buyer_nombre, p_buyer_cedula, p_buyer_telefono, p_buyer_email, 'pending', NOW())
    RETURNING id INTO v_order_id;

    -- Reservar boletos
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
