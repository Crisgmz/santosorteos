-- Tabla para comprobantes de reservas
create table if not exists public.reservados (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.ordenes(id) on delete cascade,
  sorteo_id uuid not null references public.sorteos(id) on delete cascade,
  buyer_nombre text not null,
  buyer_cedula text not null,
  buyer_telefono text not null,
  numeros int[] not null,
  banco text,
  monto_total numeric(12,2),
  comprobante_url text not null,
  comprobante_nombre text,
  created_at timestamptz not null default now()
);

-- RLS
alter table public.reservados enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'reservados'
      and policyname = 'reservados_insert_public'
  ) then
    create policy "reservados_insert_public" on public.reservados
      for insert
      to anon, authenticated
      with check (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'reservados'
      and policyname = 'reservados_select_auth'
  ) then
    create policy "reservados_select_auth" on public.reservados
      for select
      to authenticated
      using (true);
  end if;
end $$;

grant select, insert on public.reservados to anon, authenticated;

-- Bucket publico en Supabase Storage para comprobantes
insert into storage.buckets (id, name, public)
values ('reservados', 'reservados', true)
on conflict (id) do update set public = true;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'reservados_read_public'
  ) then
    create policy "reservados_read_public" on storage.objects
      for select
      to anon, authenticated
      using (bucket_id = 'reservados');
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'reservados_insert_public'
  ) then
    create policy "reservados_insert_public" on storage.objects
      for insert
      to anon, authenticated
      with check (bucket_id = 'reservados');
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'reservados_update_public'
  ) then
    create policy "reservados_update_public" on storage.objects
      for update
      to anon, authenticated
      using (bucket_id = 'reservados')
      with check (bucket_id = 'reservados');
  end if;
end $$;
