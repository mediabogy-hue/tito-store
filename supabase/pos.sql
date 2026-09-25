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
returns void language plpgsql security definer set search_path=public as $
declare x jsonb;
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 for x in select * from jsonb_array_elements(p_products) loop
  insert into public.inventory(product_id,stock,updated_at)
  values(x->>'id',greatest(0,coalesce((x->>'stock')::integer,0)),now())
  on conflict(product_id) do nothing;
 end loop;
end $;
grant execute on function public.admin_sync_inventory(jsonb) to authenticated;

create or replace function public.admin_inventory()
returns table(product_id text,stock integer)
language sql security definer set search_path=public as $
 select i.product_id,i.stock from public.inventory i where public.is_admin()
$;
grant execute on function public.admin_inventory() to authenticated;

create or replace function public.pos_checkout(p_customer_id uuid,p_items jsonb,p_discount numeric default 0,p_payment_method text default 'cash')
returns jsonb language plpgsql security definer set search_path=public as $
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
end $;
revoke all on function public.pos_checkout(uuid,jsonb,numeric,text) from public;
grant execute on function public.pos_checkout(uuid,jsonb,numeric,text) to authenticated;