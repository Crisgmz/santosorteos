-- ============================================
-- SISTEMA DE CHAT PARA SANTOSORTEOS
-- ============================================

-- Tabla de sesiones de chat
create table if not exists public.chat_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  user_name text,
  user_phone text,
  user_email text,
  status text not null default 'active' check (status in ('active', 'closed', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_message_at timestamptz
);

create index if not exists idx_chat_sessions_user on public.chat_sessions(user_id);
create index if not exists idx_chat_sessions_status on public.chat_sessions(status);
create index if not exists idx_chat_sessions_updated on public.chat_sessions(updated_at desc);

-- Tabla de mensajes
create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.chat_sessions(id) on delete cascade,
  sender_type text not null check (sender_type in ('user', 'admin')),
  sender_id uuid references auth.users(id) on delete set null,
  sender_name text,
  message text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists idx_chat_messages_session on public.chat_messages(session_id, created_at);
create index if not exists idx_chat_messages_unread on public.chat_messages(session_id, is_read) where is_read = false;

-- RLS
alter table public.chat_sessions enable row level security;
alter table public.chat_messages enable row level security;

-- Políticas para chat_sessions
do $$
begin
  -- Los usuarios pueden ver sus propias sesiones
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='chat_sessions' and policyname='chat_sessions_select_own') then
    create policy "chat_sessions_select_own" on public.chat_sessions
      for select using (
        auth.uid() = user_id 
        or auth.role() = 'authenticated'
      );
  end if;

  -- Los usuarios pueden crear sus propias sesiones
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='chat_sessions' and policyname='chat_sessions_insert_own') then
    create policy "chat_sessions_insert_own" on public.chat_sessions
      for insert with check (
        auth.uid() = user_id 
        or user_id is null
      );
  end if;

  -- Los usuarios pueden actualizar sus propias sesiones
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='chat_sessions' and policyname='chat_sessions_update_own') then
    create policy "chat_sessions_update_own" on public.chat_sessions
      for update using (
        auth.uid() = user_id 
        or auth.role() = 'authenticated'
      );
  end if;
end $$;

-- Políticas para chat_messages
do $$
begin
  -- Los usuarios pueden ver mensajes de sus sesiones
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='chat_messages' and policyname='chat_messages_select_own') then
    create policy "chat_messages_select_own" on public.chat_messages
      for select using (
        exists (
          select 1 from public.chat_sessions cs
          where cs.id = chat_messages.session_id
          and (cs.user_id = auth.uid() or auth.role() = 'authenticated')
        )
      );
  end if;

  -- Los usuarios pueden insertar mensajes en sus sesiones
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='chat_messages' and policyname='chat_messages_insert_own') then
    create policy "chat_messages_insert_own" on public.chat_messages
      for insert with check (
        exists (
          select 1 from public.chat_sessions cs
          where cs.id = chat_messages.session_id
          and (cs.user_id = auth.uid() or cs.user_id is null or auth.role() = 'authenticated')
        )
      );
  end if;

  -- Los usuarios pueden actualizar mensajes (marcar como leído)
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='chat_messages' and policyname='chat_messages_update_own') then
    create policy "chat_messages_update_own" on public.chat_messages
      for update using (
        exists (
          select 1 from public.chat_sessions cs
          where cs.id = chat_messages.session_id
          and (cs.user_id = auth.uid() or auth.role() = 'authenticated')
        )
      );
  end if;
end $$;

-- Trigger para actualizar updated_at en chat_sessions
create or replace function public.update_chat_session_timestamp()
returns trigger
language plpgsql
as $$
begin
  update public.chat_sessions
  set updated_at = now(),
      last_message_at = now()
  where id = new.session_id;
  return new;
end;
$$;

drop trigger if exists trg_chat_message_timestamp on public.chat_messages;
create trigger trg_chat_message_timestamp
after insert on public.chat_messages
for each row execute procedure public.update_chat_session_timestamp();

-- Función para crear o obtener sesión de chat
create or replace function public.get_or_create_chat_session(
  p_user_name text default null,
  p_user_phone text default null,
  p_user_email text default null
) returns public.chat_sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session public.chat_sessions;
  v_user_id uuid := auth.uid();
begin
  -- Buscar sesión activa existente
  if v_user_id is not null then
    select * into v_session
    from public.chat_sessions
    where user_id = v_user_id
      and status = 'active'
    order by updated_at desc
    limit 1;
  end if;

  -- Si no existe, crear nueva sesión
  if v_session.id is null then
    insert into public.chat_sessions (
      user_id,
      user_name,
      user_phone,
      user_email,
      status
    ) values (
      v_user_id,
      p_user_name,
      p_user_phone,
      p_user_email,
      'active'
    )
    returning * into v_session;
  end if;

  return v_session;
end;
$$;

grant execute on function public.get_or_create_chat_session(text, text, text) to authenticated, anon;

-- Función para enviar mensaje
create or replace function public.send_chat_message(
  p_session_id uuid,
  p_message text,
  p_sender_type text default 'user',
  p_sender_name text default null
) returns public.chat_messages
language plpgsql
security definer
set search_path = public
as $$
declare
  v_message public.chat_messages;
begin
  if trim(p_message) = '' then
    raise exception 'El mensaje no puede estar vacío';
  end if;

  insert into public.chat_messages (
    session_id,
    sender_type,
    sender_id,
    sender_name,
    message
  ) values (
    p_session_id,
    p_sender_type,
    auth.uid(),
    coalesce(p_sender_name, 'Usuario'),
    p_message
  )
  returning * into v_message;

  return v_message;
end;
$$;

grant execute on function public.send_chat_message(uuid, text, text, text) to authenticated, anon;

-- Función para marcar mensajes como leídos
create or replace function public.mark_messages_as_read(
  p_session_id uuid
) returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  update public.chat_messages
  set is_read = true
  where session_id = p_session_id
    and is_read = false
    and sender_type = 'admin';
  
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

grant execute on function public.mark_messages_as_read(uuid) to authenticated, anon;

-- Función para obtener mensajes de una sesión
create or replace function public.get_chat_messages(
  p_session_id uuid,
  p_limit int default 50
) returns table(
  id uuid,
  sender_type text,
  sender_name text,
  message text,
  is_read boolean,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select 
    cm.id,
    cm.sender_type,
    cm.sender_name,
    cm.message,
    cm.is_read,
    cm.created_at
  from public.chat_messages cm
  where cm.session_id = p_session_id
  order by cm.created_at asc
  limit p_limit;
end;
$$;

grant execute on function public.get_chat_messages(uuid, int) to authenticated, anon;

-- Permisos adicionales
grant select, insert, update on public.chat_sessions to authenticated, anon;
grant select, insert, update on public.chat_messages to authenticated, anon;

-- Notificar a PostgREST
notify pgrst, 'reload schema';
