-- Actualiza create_raffle para aceptar p_imagen_url
-- y guardarlo en la tabla public.sorteos

create or replace function public.create_raffle(
  p_titulo text,
  p_descripcion text,
  p_precio numeric,
  p_total_tickets int,
  p_fecha_sorteo timestamptz,
  p_premios text[] default array[]::text[],
  p_imagen_url text default null
) returns public.sorteos
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sorteo public.sorteos;
begin
  insert into public.sorteos (
    titulo, 
    descripcion, 
    precio_ticket, 
    total_tickets, 
    fecha_sorteo, 
    estado, 
    created_by,
    imagen_url
  )
  values (
    p_titulo, 
    p_descripcion, 
    p_precio, 
    p_total_tickets, 
    p_fecha_sorteo, 
    'active', 
    auth.uid(),
    p_imagen_url
  )
  returning * into v_sorteo;

  -- insertar premios si fueron provistos
  insert into public.premios (sorteo_id, posicion, titulo)
  select v_sorteo.id, ord::int, val
  from unnest(coalesce(p_premios, array[]::text[])) with ordinality as t(val, ord)
  where nullif(trim(val), '') is not null;

  -- generar boletos
  perform public.generate_boletos(v_sorteo.id);

  return v_sorteo;
end;
$$;

grant execute on function public.create_raffle(text, text, numeric, int, timestamptz, text[], text) to authenticated;
