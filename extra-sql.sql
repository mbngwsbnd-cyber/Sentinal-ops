-- Run this in Supabase SQL Editor to add the pay_rates table
-- (in addition to the previous SQL you already ran)

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

alter table public.pay_rates enable row level security;

create policy "Accountant read pay_rates" on public.pay_rates
  for select using (
    exists(select 1 from public.profiles where id=auth.uid()
      and org_id=(select org_id from public.profiles where id=auth.uid())
      and role in ('admin','accountant'))
  );

create policy "Accountant write pay_rates" on public.pay_rates
  for all using (
    exists(select 1 from public.profiles where id=auth.uid()
      and role in ('admin','accountant'))
  );

-- Also add email column to profiles if not already there
alter table public.profiles add column if not exists email text;
