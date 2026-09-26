-- BLNK Supplier Orders & Settlements v3
-- Run after suppliers.sql and supplier-portal.sql

alter table public.supplier_products add column if not exists store_product_id text;
create unique index if not exists supplier_products_store_product_uidx on public.supplier_products(store_product_id) where store_product_id is not null;

create table if not exists public.supplier_order_items(
 id uuid primary key default gen_random_uuid(),
 supplier_id uuid not null references public.suppliers(id),
 supplier_product_id uuid not null references public.supplier_products(id),
 order_id uuid references public.orders(id) on delete set null,
 invoice_id uuid references public.invoices(id) on delete set null,
 quantity integer not null check(quantity>0),
 supplier_unit_price numeric(12,2) not null check(supplier_unit_price>=0),
 selling_unit_price numeric(12,2) not null check(selling_unit_price>=0),
 supplier_amount numeric(12,2) not null,
 blnk_gross_margin numeric(12,2) not null,
 status text not null default 'pending' check(status in ('pending','confirmed','delivered','cancelled','payable','paid')),
 created_at timestamptz not null default now()
);
alter table public.supplier_order_items enable row level security;
revoke all on public.supplier_order_items from anon,authenticated;

create or replace function public.admin_link_supplier_product(p_supplier_product_id uuid,p_store_product_id text)
returns void language plpgsql security definer set search_path=public as $$
begin if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 if not exists(select 1 from public.store_products where id=p_store_product_id) then raise exception 'STORE_PRODUCT_NOT_FOUND'; end if;
 update public.supplier_products set store_product_id=p_store_product_id where id=p_supplier_product_id;
end $$;
grant execute on function public.admin_link_supplier_product(uuid,text) to authenticated;

create or replace function public.admin_capture_supplier_order(p_order_id uuid)
returns integer language plpgsql security definer set search_path=public as $$
declare n integer:=0;
begin if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 insert into public.supplier_order_items(supplier_id,supplier_product_id,order_id,quantity,supplier_unit_price,selling_unit_price,supplier_amount,blnk_gross_margin,status)
 select sp.supplier_id,sp.id,oi.order_id,oi.quantity,sp.supplier_price,oi.unit_price,sp.supplier_price*oi.quantity,(oi.unit_price-sp.supplier_price)*oi.quantity,'confirmed'
 from public.order_items oi join public.supplier_products sp on sp.store_product_id=oi.product_id and sp.status='approved'
 where oi.order_id=p_order_id and not exists(select 1 from public.supplier_order_items soi where soi.order_id=oi.order_id and soi.supplier_product_id=sp.id);
 get diagnostics n=row_count; return n;
end $$;
grant execute on function public.admin_capture_supplier_order(uuid) to authenticated;

create or replace function public.admin_supplier_finance()
returns table(supplier_id uuid,business_name text,orders bigint,units bigint,supplier_due numeric,blnk_margin numeric,paid numeric,pending numeric)
language sql security definer set search_path=public as $$
 select s.id,s.business_name,count(distinct soi.order_id),coalesce(sum(soi.quantity),0)::bigint,
 coalesce(sum(case when soi.status<>'cancelled' then soi.supplier_amount else 0 end),0),
 coalesce(sum(case when soi.status<>'cancelled' then soi.blnk_gross_margin else 0 end),0),
 coalesce(sum(case when soi.status='paid' then soi.supplier_amount else 0 end),0),
 coalesce(sum(case when soi.status not in ('paid','cancelled') then soi.supplier_amount else 0 end),0)
 from public.suppliers s left join public.supplier_order_items soi on soi.supplier_id=s.id
 where public.is_admin() group by s.id,s.business_name order by s.business_name
$$;
grant execute on function public.admin_supplier_finance() to authenticated;

create or replace function public.admin_supplier_order_items()
returns table(id uuid,supplier_id uuid,business_name text,order_number text,product_name text,quantity integer,supplier_amount numeric,blnk_margin numeric,status text,created_at timestamptz)
language sql security definer set search_path=public as $$
 select soi.id,soi.supplier_id,s.business_name,o.order_number,sp.name,soi.quantity,soi.supplier_amount,soi.blnk_gross_margin,soi.status,soi.created_at
 from public.supplier_order_items soi join public.suppliers s on s.id=soi.supplier_id join public.supplier_products sp on sp.id=soi.supplier_product_id left join public.orders o on o.id=soi.order_id
 where public.is_admin() order by soi.created_at desc
$$;
grant execute on function public.admin_supplier_order_items() to authenticated;

create or replace function public.admin_set_supplier_order_status(p_id uuid,p_status text)
returns void language plpgsql security definer set search_path=public as $$
begin if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 if p_status not in ('pending','confirmed','delivered','cancelled','payable','paid') then raise exception 'INVALID_STATUS'; end if;
 update public.supplier_order_items set status=p_status where id=p_id;
end $$;
grant execute on function public.admin_set_supplier_order_status(uuid,text) to authenticated;

create or replace function public.supplier_my_finance()
returns jsonb language plpgsql security definer set search_path=public as $$
declare sid uuid; r jsonb; begin select id into sid from public.suppliers where user_id=auth.uid();
if sid is null then raise exception 'SUPPLIER_NOT_LINKED'; end if;
select jsonb_build_object('orders',count(distinct order_id),'units',coalesce(sum(quantity),0),'total_due',coalesce(sum(case when status<>'cancelled' then supplier_amount else 0 end),0),'paid',coalesce(sum(case when status='paid' then supplier_amount else 0 end),0),'pending',coalesce(sum(case when status not in ('paid','cancelled') then supplier_amount else 0 end),0)) into r from public.supplier_order_items where supplier_id=sid; return r; end $$;
grant execute on function public.supplier_my_finance() to authenticated;

create or replace function public.supplier_my_orders()
returns table(order_number text,product_name text,quantity integer,supplier_amount numeric,status text,created_at timestamptz)
language sql security definer set search_path=public as $$
 select coalesce(o.order_number,'POS'),sp.name,soi.quantity,soi.supplier_amount,soi.status,soi.created_at
 from public.supplier_order_items soi join public.supplier_products sp on sp.id=soi.supplier_product_id left join public.orders o on o.id=soi.order_id
 join public.suppliers s on s.id=soi.supplier_id where s.user_id=auth.uid() order by soi.created_at desc
$$;
grant execute on function public.supplier_my_orders() to authenticated;
