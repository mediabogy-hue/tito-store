-- BLNK customer platform foundation
create extension if not exists pgcrypto;
create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 customer_code text unique not null default ('BLNK-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10))),
 full_name text, phone text unique, city text, avatar_url text,
 club_tier text not null default 'Member', balance numeric(12,2) not null default 0 check(balance>=0),
 points integer not null default 0 check(points>=0), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.invoices (
 id uuid primary key default gen_random_uuid(), invoice_number text unique not null,
 customer_id uuid not null references public.profiles(id), pos_reference text unique,
 subtotal numeric(12,2) not null default 0, discount numeric(12,2) not null default 0,
 total numeric(12,2) not null default 0, payment_method text, store text, created_at timestamptz not null default now()
);
create table if not exists public.invoice_items (
 id uuid primary key default gen_random_uuid(), invoice_id uuid not null references public.invoices(id) on delete cascade,
 product_id text, sku text, product_name text not null, size text, color text,
 quantity integer not null default 1 check(quantity>0), unit_price numeric(12,2) not null default 0
);
create table if not exists public.wallet_transactions (
 id uuid primary key default gen_random_uuid(), customer_id uuid not null references public.profiles(id),
 amount numeric(12,2) not null, type text not null, description text, reference_type text, reference_id text,
 created_at timestamptz not null default now()
);
create table if not exists public.tryon_transactions (
 id uuid primary key default gen_random_uuid(), customer_id uuid not null references public.profiles(id),
 product_id text, charge numeric(12,2) not null default 0, status text not null default 'pending',
 created_at timestamptz not null default now()
);
create table if not exists public.app_settings (key text primary key,value jsonb not null,updated_at timestamptz not null default now());
insert into public.app_settings(key,value) values ('tryon_price','5'::jsonb) on conflict(key) do nothing;
alter table public.profiles enable row level security; alter table public.invoices enable row level security;
alter table public.invoice_items enable row level security; alter table public.wallet_transactions enable row level security; alter table public.tryon_transactions enable row level security;
create policy "profile self read" on public.profiles for select to authenticated using(auth.uid()=id);
create policy "profile self update" on public.profiles for update to authenticated using(auth.uid()=id) with check(auth.uid()=id);
create policy "invoice self read" on public.invoices for select to authenticated using(auth.uid()=customer_id);
create policy "invoice items self read" on public.invoice_items for select to authenticated using(exists(select 1 from public.invoices i where i.id=invoice_id and i.customer_id=auth.uid()));
create policy "wallet self read" on public.wallet_transactions for select to authenticated using(auth.uid()=customer_id);
create policy "tryon self read" on public.tryon_transactions for select to authenticated using(auth.uid()=customer_id);
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$ begin insert into public.profiles(id,full_name,phone) values(new.id,new.raw_user_meta_data->>'full_name',new.phone) on conflict(id) do nothing; return new; end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();
grant select,update on public.profiles to authenticated; grant select on public.invoices,public.invoice_items,public.wallet_transactions,public.tryon_transactions to authenticated;