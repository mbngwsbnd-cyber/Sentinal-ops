-- ============================================================
-- SENTINEL OPS — COMPLETE DATABASE SETUP
-- Run this entire script in Supabase SQL Editor
-- ============================================================

-- ORGANISATIONS
create table if not exists public.organisations (
  id uuid primary key default gen_random_uuid(),
  name text unique not null,
  logo text,
  created_at timestamptz default now()
);

-- PROFILES (one per user)
create table if not exists public.profiles (
  id uuid references auth.users on delete cascade primary key,
  org_id uuid references public.organisations(id) on delete cascade,
  username text not null,
  display_name text,
  gender text,
  role text default 'user' check (role in ('admin','user','accountant')),
  status text default 'pending' check (status in ('approved','pending','rejected')),
  email text,
  created_at timestamptz default now(),
  unique(org_id, username)
);

-- OFFICERS
create table if not exists public.officers (
  id bigint primary key generated always as identity,
  org_id uuid references public.organisations(id) on delete cascade,
  name text not null,
  gender text,
  role text,
  shift text,
  status text default 'Off Duty',
  depzone text default 'field',
  zone text default '—',
  avatar text,
  armed boolean default false,
  weapon_type text,
  weapon_serial text,
  ammo_type text,
  ammo_count integer default 0,
  daily_rate numeric default 0,
  overtime_rate numeric default 0,
  created_at timestamptz default now()
);

-- TASKS
create table if not exists public.tasks (
  id bigint primary key generated always as identity,
  org_id uuid references public.organisations(id) on delete cascade,
  title text not null,
  priority text default 'Medium',
  status text default 'Pending',
  assigned_to bigint references public.officers(id) on delete set null,
  due text,
  category text,
  created_at timestamptz default now()
);

-- DEPLOYMENTS
create table if not exists public.deployments (
  id bigint primary key generated always as identity,
  org_id uuid references public.organisations(id) on delete cascade,
  title text not null,
  officer_id bigint references public.officers(id) on delete set null,
  officer_name text,
  gender text,
  location text,
  date text,
  time text,
  depzone text,
  status text default 'pending',
  notes text,
  created_at timestamptz default now()
);

-- DUTY LOGS (officer check-in)
create table if not exists public.duty_logs (
  id bigint primary key generated always as identity,
  org_id uuid references public.organisations(id) on delete cascade,
  officer_id bigint references public.officers(id) on delete cascade,
  confirmed_at timestamptz default now(),
  shift text,
  notes text,
  patrol_count integer default 0
);

-- PATROL LOGS (contator rounds)
create table if not exists public.patrol_logs (
  id bigint primary key generated always as identity,
  org_id uuid references public.organisations(id) on delete cascade,
  officer_id bigint references public.officers(id) on delete cascade,
  duty_log_id bigint references public.duty_logs(id) on delete cascade,
  logged_at timestamptz default now(),
  location text,
  notes text
);

-- ATTENDANCE
create table if not exists public.attendance (
  id bigint primary key generated always as identity,
  org_id uuid references public.organisations(id) on delete cascade,
  officer_id bigint references public.officers(id) on delete cascade,
  work_date date not null,
  shift text,
  hours_worked numeric default 8,
  overtime_hours numeric default 0,
  status text default 'present',
  unique(officer_id, work_date)
);

-- PAY RATES
create table if not exists public.pay_rates (
  id bigint primary key generated always as identity,
  org_id uuid references public.organisations(id) on delete cascade,
  officer_id bigint references public.officers(id) on delete cascade,
  scale text default 'daily' check (scale in ('hourly','daily','monthly','yearly')),
  base_rate numeric default 0,
  overtime_rate numeric default 0,
  currency text default 'USD',
  payday_date integer default 25,
  effective_from date default current_date,
  created_at timestamptz default now(),
  unique(org_id, officer_id)
);

-- NOTIFICATIONS
create table if not exists public.notifications (
  id bigint primary key generated always as identity,
  org_id uuid references public.organisations(id) on delete cascade,
  message text,
  type text,
  read boolean default false,
  created_at timestamptz default now()
);

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================
alter table public.organisations enable row level security;
alter table public.profiles enable row level security;
alter table public.officers enable row level security;
alter table public.tasks enable row level security;
alter table public.deployments enable row level security;
alter table public.duty_logs enable row level security;
alter table public.patrol_logs enable row level security;
alter table public.attendance enable row level security;
alter table public.pay_rates enable row level security;
alter table public.notifications enable row level security;

-- Anyone can read organisations (needed for login org search)
create policy "Anyone read orgs" on public.organisations
  for select using (true);

-- Anyone can insert organisations (needed for admin signup)
create policy "Anyone insert orgs" on public.organisations
  for insert with check (true);

-- Admin can update their own org
create policy "Admin update org" on public.organisations
  for update using (
    id = (select org_id from public.profiles where id = auth.uid())
    and exists(select 1 from public.profiles where id = auth.uid() and role = 'admin')
  );

-- Profiles: own profile
create policy "Insert own profile" on public.profiles
  for insert with check (auth.uid() = id);
create policy "Read own profile" on public.profiles
  for select using (auth.uid() = id);
create policy "Update own profile" on public.profiles
  for update using (auth.uid() = id);

-- Admin can read all profiles in their org
create policy "Admin read org profiles" on public.profiles
  for select using (
    org_id = (select org_id from public.profiles where id = auth.uid())
    and exists(select 1 from public.profiles where id = auth.uid() and role = 'admin')
  );

-- Admin can update profiles in their org (approve/reject)
create policy "Admin update org profiles" on public.profiles
  for update using (
    org_id = (select org_id from public.profiles where id = auth.uid())
    and exists(select 1 from public.profiles where id = auth.uid() and role = 'admin')
  );

-- Org data isolation helper function
create or replace function public.my_org_id()
returns uuid language sql stable
as $$ select org_id from public.profiles where id = auth.uid() $$;

-- Officers
create policy "Org read officers" on public.officers
  for select using (org_id = public.my_org_id());
create policy "Admin write officers" on public.officers
  for insert with check (
    org_id = public.my_org_id()
    and exists(select 1 from public.profiles where id = auth.uid() and role = 'admin')
  );
create policy "Admin update officers" on public.officers
  for update using (
    org_id = public.my_org_id()
    and exists(select 1 from public.profiles where id = auth.uid() and role = 'admin')
  );
create policy "Admin delete officers" on public.officers
  for delete using (
    org_id = public.my_org_id()
    and exists(select 1 from public.profiles where id = auth.uid() and role = 'admin')
  );

-- Tasks
create policy "Org read tasks" on public.tasks
  for select using (org_id = public.my_org_id());
create policy "Admin write tasks" on public.tasks
  for all using (
    org_id = public.my_org_id()
    and exists(select 1 from public.profiles where id = auth.uid() and role = 'admin')
  );

-- Deployments
create policy "Org read deployments" on public.deployments
  for select using (org_id = public.my_org_id());
create policy "Admin write deployments" on public.deployments
  for all using (
    org_id = public.my_org_id()
    and exists(select 1 from public.profiles where id = auth.uid() and role = 'admin')
  );

-- Duty logs
create policy "Org read duty_logs" on public.duty_logs
  for select using (org_id = public.my_org_id());
create policy "Org write duty_logs" on public.duty_logs
  for insert with check (org_id = public.my_org_id());

-- Patrol logs
create policy "Org read patrol_logs" on public.patrol_logs
  for select using (org_id = public.my_org_id());
create policy "Org write patrol_logs" on public.patrol_logs
  for insert with check (org_id = public.my_org_id());

-- Attendance
create policy "Org read attendance" on public.attendance
  for select using (org_id = public.my_org_id());
create policy "Acct write attendance" on public.attendance
  for all using (
    org_id = public.my_org_id()
    and exists(select 1 from public.profiles where id = auth.uid() and role in ('admin','accountant'))
  );

-- Pay rates (accountant only)
create policy "Acct read pay_rates" on public.pay_rates
  for select using (
    org_id = public.my_org_id()
    and exists(select 1 from public.profiles where id = auth.uid() and role in ('admin','accountant'))
  );
create policy "Acct write pay_rates" on public.pay_rates
  for all using (
    org_id = public.my_org_id()
    and exists(select 1 from public.profiles where id = auth.uid() and role in ('admin','accountant'))
  );

-- Notifications
create policy "Org read notifications" on public.notifications
  for select using (org_id = public.my_org_id());
create policy "Org write notifications" on public.notifications
  for insert with check (org_id = public.my_org_id());
create policy "Admin update notifications" on public.notifications
  for update using (
    org_id = public.my_org_id()
    and exists(select 1 from public.profiles where id = auth.uid() and role = 'admin')
  );
