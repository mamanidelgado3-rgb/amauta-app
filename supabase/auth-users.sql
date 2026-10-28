create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  phone text not null unique,
  full_name text not null check (char_length(full_name) between 1 and 120),
  role text not null check (role in ('pasajero', 'conductor', 'admin')),
  status text not null check (status in ('activo', 'pendiente', 'aprobado', 'bloqueado')),
  dni text check (dni is null or dni ~ '^[0-9]{8}$'),
  vehicle_type text,
  vehicle_model text,
  plate text,
  license_number text,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
revoke all on table public.profiles from anon, authenticated;
grant select on table public.profiles to authenticated;

drop policy if exists "Users can read their own profile" on public.profiles;
create policy "Users can read their own profile"
  on public.profiles
  for select
  to authenticated
  using ((select auth.uid()) = id);

create or replace function public.create_profile_for_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_role text := coalesce(new.raw_user_meta_data ->> 'role', '');
begin
  insert into public.profiles (
    id,
    phone,
    full_name,
    role,
    status,
    dni,
    vehicle_type,
    vehicle_model,
    plate,
    license_number
  )
  values (
    new.id,
    new.phone,
    coalesce(nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''), 'Usuario'),
    case when requested_role = 'conductor' then 'conductor' else 'pasajero' end,
    case when requested_role = 'conductor' then 'pendiente' else 'activo' end,
    case when requested_role = 'conductor' then nullif(new.raw_user_meta_data ->> 'dni', '') end,
    case when requested_role = 'conductor' then nullif(new.raw_user_meta_data ->> 'vehicle_type', '') end,
    case when requested_role = 'conductor' then nullif(new.raw_user_meta_data ->> 'vehicle_model', '') end,
    case when requested_role = 'conductor' then nullif(new.raw_user_meta_data ->> 'plate', '') end,
    case when requested_role = 'conductor' then nullif(new.raw_user_meta_data ->> 'license_number', '') end
  );
  return new;
end;
$$;

revoke all on function public.create_profile_for_new_auth_user() from public, anon, authenticated;

drop trigger if exists create_profile_after_auth_signup on auth.users;
create trigger create_profile_after_auth_signup
  after insert on auth.users
  for each row execute function public.create_profile_for_new_auth_user();
