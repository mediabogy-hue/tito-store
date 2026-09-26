-- BLNK Supplier Marketplace automation v4
-- Run after supplier-orders.sql

create or replace function public.admin_publish_supplier_product(p_supplier_product_id uuid,p_store_product_id text)
returns void language plpgsql security definer set search_path=public as $$
declare sp public.supplier_products%rowtype;
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 select * into sp from public.supplier_products where id=p_supplier_product_id;
 if sp.id is null then raise exception 'SUPPLIER_PRODUCT_NOT_FOUND'; end if;
 if sp.status<>'approved' then raise exception 'APPROVE_PRODUCT_FIRST'; end if;
 if sp.selling_price is null then raise exception 'SELLING_PRICE_REQUIRED'; end if;
 insert into public.store_products(id,name,price,active,updated_at)
 values(p_store_product_id,sp.name,sp.selling_price,true,now())
 on conflict(id) do update set name=excluded.name,price=excluded.price,active=true,updated_at=now();
 insert into public.inventory(product_id,stock,updated_at) values(p_store_product_id,sp.stock,now())
 on conflict(product_id) do update set stock=excluded.stock,updated_at=now();
 update public.supplier_products set store_product_id=p_store_product_id where id=p_supplier_product_id;
end $$;
grant execute on function public.admin_publish_supplier_product(uuid,text) to authenticated;

create or replace function public.capture_supplier_order_auto()
returns trigger language plpgsql security definer set search_path=public as $$
declare sp public.supplier_products%rowtype;
begin
 select * into sp from public.supplier_products where store_product_id=new.product_id and status='approved' limit 1;
 if sp.id is not null then
  insert into public.supplier_order_items(supplier_id,supplier_product_id,order_id,quantity,supplier_unit_price,selling_unit_price,supplier_amount,blnk_gross_margin,status)
  values(sp.supplier_id,sp.id,new.order_id,new.quantity,sp.supplier_price,new.unit_price,sp.supplier_price*new.quantity,(new.unit_price-sp.supplier_price)*new.quantity,'confirmed')
  on conflict do nothing;
 end if;
 return new;
end $$;
drop trigger if exists trg_capture_supplier_order on public.order_items;
create trigger trg_capture_supplier_order after insert on public.order_items for each row execute function public.capture_supplier_order_auto();

create or replace function public.sync_supplier_status_from_order()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.status='cancelled' then update public.supplier_order_items set status='cancelled' where order_id=new.id and status<>'paid';
 elsif new.status='delivered' then update public.supplier_order_items set status='payable' where order_id=new.id and status in ('pending','confirmed','delivered');
 end if;
 return new;
end $$;
drop trigger if exists trg_supplier_order_status on public.orders;
create trigger trg_supplier_order_status after update of status on public.orders for each row execute function public.sync_supplier_status_from_order();
