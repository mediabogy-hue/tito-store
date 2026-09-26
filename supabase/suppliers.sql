-- BLNK Supplier Center v1
create table if not exists public.suppliers(
 id uuid primary key default gen_random_uuid(),
 business_name text not null, contact_name text not null, phone text not null, whatsapp text,
 address text, category text, payment_method text, payment_details text,
 status text not null default 'pending' check(status in ('pending','approved','suspended')),
 created_at timestamptz not null default now()
);
create table if not exists public.supplier_products(
 id uuid primary key default gen_random_uuid(), supplier_id uuid not null references public.suppliers(id) on delete cascade,
 name text not null, description text, image_url text, sizes text, colors text,
 supplier_price numeric(12,2) not null check(supplier_price>=0), selling_price numeric(12,2) check(selling_price>=0),
 stock integer not null default 0 check(stock>=0),
 status text not null default 'pending' check(status in ('pending','approved','rejected','inactive')),
 created_at timestamptz not null default now()
);
create table if not exists public.supplier_settlements(
 id uuid primary key default gen_random_uuid(), supplier_id uuid not null references public.suppliers(id),
 amount numeric(12,2) not null check(amount>=0), status text not null default 'pending' check(status in ('pending','paid')),
 note text, created_at timestamptz not null default now(), paid_at timestamptz
);
alter table public.suppliers enable row level security;
alter table public.supplier_products enable row level security;
alter table public.supplier_settlements enable row level security;
revoke all on public.suppliers,public.supplier_products,public.supplier_settlements from anon,authenticated;

create or replace function public.admin_suppliers()
returns table(id uuid,business_name text,contact_name text,phone text,whatsapp text,address text,category text,status text,created_at timestamptz)
language sql security definer set search_path=public as $$
 select s.id,s.business_name,s.contact_name,s.phone,s.whatsapp,s.address,s.category,s.status,s.created_at from public.suppliers s where public.is_admin() order by s.created_at desc
$$;
grant execute on function public.admin_suppliers() to authenticated;

create or replace function public.admin_create_supplier(p_business_name text,p_contact_name text,p_phone text,p_whatsapp text default null,p_address text default null,p_category text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v uuid; begin if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
insert into public.suppliers(business_name,contact_name,phone,whatsapp,address,category) values(trim(p_business_name),trim(p_contact_name),trim(p_phone),nullif(trim(p_whatsapp),''),nullif(trim(p_address),''),nullif(trim(p_category),'')) returning id into v; return v; end $$;
grant execute on function public.admin_create_supplier(text,text,text,text,text,text) to authenticated;

create or replace function public.admin_set_supplier_status(p_id uuid,p_status text)
returns void language plpgsql security definer set search_path=public as $$ begin
if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
if p_status not in ('pending','approved','suspended') then raise exception 'INVALID_STATUS'; end if;
update public.suppliers set status=p_status where id=p_id; end $$;
grant execute on function public.admin_set_supplier_status(uuid,text) to authenticated;

create or replace function public.admin_supplier_products()
returns table(id uuid,supplier_id uuid,supplier_name text,name text,supplier_price numeric,selling_price numeric,stock integer,status text,created_at timestamptz)
language sql security definer set search_path=public as $$
select p.id,p.supplier_id,s.business_name,p.name,p.supplier_price,p.selling_price,p.stock,p.status,p.created_at
from public.supplier_products p join public.suppliers s on s.id=p.supplier_id where public.is_admin() order by p.created_at desc
$$;
grant execute on function public.admin_supplier_products() to authenticated;

create or replace function public.admin_add_supplier_product(p_supplier_id uuid,p_name text,p_supplier_price numeric,p_selling_price numeric,p_stock integer)
returns uuid language plpgsql security definer set search_path=public as $$ declare v uuid; begin
if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
insert into public.supplier_products(supplier_id,name,supplier_price,selling_price,stock) values(p_supplier_id,trim(p_name),p_supplier_price,p_selling_price,p_stock) returning id into v; return v; end $$;
grant execute on function public.admin_add_supplier_product(uuid,text,numeric,numeric,integer) to authenticated;

create or replace function public.admin_set_supplier_product_status(p_id uuid,p_status text)
returns void language plpgsql security definer set search_path=public as $$ begin
if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
if p_status not in ('pending','approved','rejected','inactive') then raise exception 'INVALID_STATUS'; end if;
update public.supplier_products set status=p_status where id=p_id; end $$;
grant execute on function public.admin_set_supplier_product_status(uuid,text) to authenticated;
