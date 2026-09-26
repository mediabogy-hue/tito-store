-- BLNK POS v1
create or replace function public.pos_checkout(p_customer_id uuid,p_items jsonb,p_discount numeric default 0,p_payment_method text default 'cash')
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_invoice uuid:=gen_random_uuid(); v_number text:='BLNK-'||to_char(now(),'YYYYMMDD-HH24MISS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,4)); v_sub numeric:=0; v_total numeric; x jsonb;
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 if jsonb_array_length(p_items)=0 then raise exception 'EMPTY_CART'; end if;
 for x in select * from jsonb_array_elements(p_items) loop v_sub:=v_sub+(x->>'price')::numeric*(x->>'qty')::integer; end loop;
 v_total:=greatest(0,v_sub-greatest(0,coalesce(p_discount,0)));
 if p_payment_method='wallet' then
  update public.profiles set balance=balance-v_total,updated_at=now() where id=p_customer_id and balance>=v_total;
  if not found then raise exception 'INSUFFICIENT_BALANCE'; end if;
  insert into public.wallet_transactions(customer_id,amount,type,description,reference_type,reference_id) values(p_customer_id,-v_total,'purchase','BLNK POS purchase','invoice',v_invoice::text);
 end if;
 insert into public.invoices(id,invoice_number,customer_id,pos_reference,subtotal,discount,total,payment_method,store) values(v_invoice,v_number,p_customer_id,'POS-'||v_invoice,v_sub,greatest(0,coalesce(p_discount,0)),v_total,p_payment_method,'BLNK');
 for x in select * from jsonb_array_elements(p_items) loop
  insert into public.invoice_items(invoice_id,product_id,product_name,size,color,quantity,unit_price) values(v_invoice,x->>'id',x->>'name',x->>'size',x->>'color',(x->>'qty')::integer,(x->>'price')::numeric);
 end loop;
 update public.profiles set points=points+floor(v_total/100)::integer,updated_at=now() where id=p_customer_id;
 return jsonb_build_object('invoice_id',v_invoice,'invoice_number',v_number,'total',v_total,'points_earned',floor(v_total/100)::integer);
end $$;
revoke all on function public.pos_checkout(uuid,jsonb,numeric,text) from public;
grant execute on function public.pos_checkout(uuid,jsonb,numeric,text) to authenticated;

-- Inventory ledger. Stock movements are recorded in Supabase so POS sales are atomic/auditable.
create table if not exists public.inventory (
 product_id text primary key,
 stock integer not null default 0 check(stock>=0),
 updated_at timestamptz not null default now()
);
create table if not exists public.inventory_movements (
 id uuid primary key default gen_random_uuid(),
 product_id text not null,
 quantity integer not null,
 movement_type text not null,
 reference_id text,
 created_at timestamptz not null default now()
);
alter table public.inventory enable row level security;
alter table public.inventory_movements enable row level security;
revoke all on public.inventory,public.inventory_movements from anon,authenticated;

create or replace function public.admin_sync_inventory(p_products jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare x jsonb;
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 for x in select * from jsonb_array_elements(p_products) loop
  insert into public.inventory(product_id,stock,updated_at)
  values(x->>'id',greatest(0,coalesce((x->>'stock')::integer,0)),now())
  on conflict(product_id) do nothing;
 end loop;
end $$;
grant execute on function public.admin_sync_inventory(jsonb) to authenticated;

create or replace function public.admin_inventory()
returns table(product_id text,stock integer)
language sql security definer set search_path=public as $$
 select i.product_id,i.stock from public.inventory i where public.is_admin()
$;
grant execute on function public.admin_inventory() to authenticated;

create or replace function public.pos_checkout(p_customer_id uuid,p_items jsonb,p_discount numeric default 0,p_payment_method text default 'cash')
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 v_invoice uuid:=gen_random_uuid();
 v_number text:='BLNK-'||to_char(now(),'YYYYMMDD-HH24MISS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,4));
 v_sub numeric:=0; v_total numeric; x jsonb; v_stock integer;
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 if p_items is null or jsonb_array_length(p_items)=0 then raise exception 'EMPTY_CART'; end if;
 for x in select * from jsonb_array_elements(p_items) loop
  if (x->>'qty')::integer < 1 or (x->>'price')::numeric < 0 then raise exception 'INVALID_ITEM'; end if;
  select stock into v_stock from public.inventory where product_id=x->>'id' for update;
  if v_stock is null then raise exception 'INVENTORY_NOT_SYNCED: %',x->>'name'; end if;
  if v_stock < (x->>'qty')::integer then raise exception 'OUT_OF_STOCK: %',x->>'name'; end if;
  v_sub:=v_sub+(x->>'price')::numeric*(x->>'qty')::integer;
 end loop;
 v_total:=greatest(0,v_sub-greatest(0,coalesce(p_discount,0)));
 if p_payment_method='wallet' then
  update public.profiles set balance=balance-v_total,updated_at=now() where id=p_customer_id and balance>=v_total;
  if not found then raise exception 'INSUFFICIENT_BALANCE'; end if;
 end if;
 insert into public.invoices(id,invoice_number,customer_id,pos_reference,subtotal,discount,total,payment_method,store)
 values(v_invoice,v_number,p_customer_id,'POS-'||v_invoice,v_sub,greatest(0,coalesce(p_discount,0)),v_total,p_payment_method,'BLNK');
 for x in select * from jsonb_array_elements(p_items) loop
  insert into public.invoice_items(invoice_id,product_id,product_name,size,color,quantity,unit_price)
  values(v_invoice,x->>'id',x->>'name',x->>'size',x->>'color',(x->>'qty')::integer,(x->>'price')::numeric);
  update public.inventory set stock=stock-(x->>'qty')::integer,updated_at=now() where product_id=x->>'id';
  insert into public.inventory_movements(product_id,quantity,movement_type,reference_id)
  values(x->>'id',-(x->>'qty')::integer,'sale',v_invoice::text);
 end loop;
 if p_payment_method='wallet' then
  insert into public.wallet_transactions(customer_id,amount,type,description,reference_type,reference_id)
  values(p_customer_id,-v_total,'purchase','BLNK POS purchase','invoice',v_invoice::text);
 end if;
 update public.profiles set points=points+floor(v_total/100)::integer,updated_at=now() where id=p_customer_id;
 return jsonb_build_object('invoice_id',v_invoice,'invoice_number',v_number,'total',v_total,'points_earned',floor(v_total/100)::integer);
end $$;
revoke all on function public.pos_checkout(uuid,jsonb,numeric,text) from public;
grant execute on function public.pos_checkout(uuid,jsonb,numeric,text) to authenticated;

-- POS dashboard metrics
create or replace function public.admin_pos_dashboard()
returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb;
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 select jsonb_build_object(
  'sales_today',coalesce((select sum(total) from public.invoices where created_at>=date_trunc('day',now())),0),
  'invoices_today',(select count(*) from public.invoices where created_at>=date_trunc('day',now())),
  'items_today',coalesce((select sum(ii.quantity) from public.invoice_items ii join public.invoices i on i.id=ii.invoice_id where i.created_at>=date_trunc('day',now())),0),
  'atv',coalesce((select avg(total) from public.invoices where created_at>=date_trunc('day',now())),0),
  'upt',coalesce((select sum(ii.quantity)::numeric/nullif(count(distinct i.id),0) from public.invoice_items ii join public.invoices i on i.id=ii.invoice_id where i.created_at>=date_trunc('day',now())),0),
  'asp',coalesce((select sum(i.total)/nullif(sum(ii.quantity),0) from public.invoice_items ii join public.invoices i on i.id=ii.invoice_id where i.created_at>=date_trunc('day',now())),0),
  'low_stock',coalesce((select jsonb_agg(jsonb_build_object('product_id',product_id,'stock',stock) order by stock) from public.inventory where stock<=3),'[]'::jsonb),
  'top_products',coalesce((select jsonb_agg(t) from (select ii.product_name,sum(ii.quantity) qty,sum(ii.quantity*ii.unit_price) sales from public.invoice_items ii join public.invoices i on i.id=ii.invoice_id where i.created_at>=date_trunc('day',now()) group by ii.product_name order by qty desc limit 5)t),'[]'::jsonb)
 ) into r;
 return r;
end $$;
revoke all on function public.admin_pos_dashboard() from public;
grant execute on function public.admin_pos_dashboard() to authenticated;


-- BLNK POS phase 3: targets, shifts and period reports
create table if not exists public.sales_targets(
 id uuid primary key default gen_random_uuid(), period_start date not null, period_end date not null,
 target_amount numeric(12,2) not null check(target_amount>=0), created_at timestamptz not null default now()
);
create table if not exists public.pos_shifts(
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id),
 opened_at timestamptz not null default now(), closed_at timestamptz, opening_cash numeric(12,2) not null default 0,
 closing_cash numeric(12,2), status text not null default 'open'
);
alter table public.sales_targets enable row level security; alter table public.pos_shifts enable row level security;
revoke all on public.sales_targets,public.pos_shifts from anon,authenticated;

create or replace function public.admin_set_sales_target(p_start date,p_end date,p_target numeric)
returns void language plpgsql security definer set search_path=public as $$
begin if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 insert into public.sales_targets(period_start,period_end,target_amount) values(p_start,p_end,greatest(0,p_target)); end $$;
grant execute on function public.admin_set_sales_target(date,date,numeric) to authenticated;

create or replace function public.pos_open_shift(p_opening_cash numeric default 0)
returns uuid language plpgsql security definer set search_path=public as $$
declare v uuid;
begin if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 if exists(select 1 from public.pos_shifts where user_id=auth.uid() and status='open') then raise exception 'SHIFT_ALREADY_OPEN'; end if;
 insert into public.pos_shifts(user_id,opening_cash) values(auth.uid(),greatest(0,p_opening_cash)) returning id into v; return v; end $$;
grant execute on function public.pos_open_shift(numeric) to authenticated;

create or replace function public.pos_close_shift(p_closing_cash numeric)
returns void language plpgsql security definer set search_path=public as $$
begin if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 update public.pos_shifts set closing_cash=p_closing_cash,closed_at=now(),status='closed' where user_id=auth.uid() and status='open';
 if not found then raise exception 'NO_OPEN_SHIFT'; end if; end $$;
grant execute on function public.pos_close_shift(numeric) to authenticated;

create or replace function public.admin_sales_report(p_from timestamptz,p_to timestamptz)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb; v_target numeric;
begin if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 select coalesce(sum(target_amount),0) into v_target from public.sales_targets where period_start>=p_from::date and period_end<=p_to::date;
 select jsonb_build_object(
 'sales',coalesce(sum(total),0),'invoices',count(*),'atv',coalesce(avg(total),0),'target',v_target,
 'achievement',case when v_target>0 then coalesce(sum(total),0)/v_target*100 else 0 end
 ) into r from public.invoices where created_at>=p_from and created_at<p_to; return r; end $$;
grant execute on function public.admin_sales_report(timestamptz,timestamptz) to authenticated;


-- Reporting v2: reliable date-based reporting including POS + app orders
create or replace function public.admin_sales_report_v2(p_from date,p_to date)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_pos numeric:=0; v_app numeric:=0; v_inv bigint:=0; v_orders bigint:=0; v_items numeric:=0; v_target numeric:=0;
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 if p_from is null or p_to is null or p_to<p_from then raise exception 'INVALID_DATE_RANGE'; end if;
 select coalesce(sum(total),0),count(*) into v_pos,v_inv from public.invoices where created_at::date between p_from and p_to;
 select coalesce(sum(total),0),count(*) into v_app,v_orders from public.orders where created_at::date between p_from and p_to and status<>'cancelled';
 select coalesce(sum(ii.quantity),0) into v_items from public.invoice_items ii join public.invoices i on i.id=ii.invoice_id where i.created_at::date between p_from and p_to;
 select v_items+coalesce((select sum(oi.quantity) from public.order_items oi join public.orders o on o.id=oi.order_id where o.created_at::date between p_from and p_to and o.status<>'cancelled'),0) into v_items;
 select coalesce(sum(target_amount),0) into v_target from public.sales_targets where period_start<=p_to and period_end>=p_from;
 return jsonb_build_object('sales',v_pos+v_app,'pos_sales',v_pos,'app_sales',v_app,'transactions',v_inv+v_orders,'pos_invoices',v_inv,'app_orders',v_orders,'items',v_items,'atv',case when v_inv+v_orders>0 then (v_pos+v_app)/(v_inv+v_orders) else 0 end,'asp',case when v_items>0 then (v_pos+v_app)/v_items else 0 end,'upt',case when v_inv+v_orders>0 then v_items/(v_inv+v_orders) else 0 end,'target',v_target,'achievement',case when v_target>0 then (v_pos+v_app)/v_target*100 else 0 end);
end $$;
revoke all on function public.admin_sales_report_v2(date,date) from public;
grant execute on function public.admin_sales_report_v2(date,date) to authenticated;
