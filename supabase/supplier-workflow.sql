-- BLNK supplier end-to-end workflow v7
-- Run after supplier-product-upload.sql and supplier-marketplace.sql

create or replace function public.admin_approve_publish_supplier_product(p_id uuid,p_selling_price numeric,p_store_product_id text)
returns void language plpgsql security definer set search_path=public as $$
declare sp public.supplier_products%rowtype;
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 update public.supplier_products set status='approved',selling_price=greatest(0,p_selling_price) where id=p_id returning * into sp;
 if sp.id is null then raise exception 'PRODUCT_NOT_FOUND'; end if;
 if greatest(0,p_selling_price)<sp.supplier_price then raise exception 'SELLING_PRICE_BELOW_SUPPLIER_COST'; end if;
 insert into public.store_products(id,name,price,active,updated_at) values(p_store_product_id,sp.name,greatest(0,p_selling_price),true,now())
 on conflict(id) do update set name=excluded.name,price=excluded.price,active=true,updated_at=now();
 insert into public.inventory(product_id,stock,updated_at) values(p_store_product_id,sp.stock,now())
 on conflict(product_id) do update set stock=excluded.stock,updated_at=now();
 update public.supplier_products set store_product_id=p_store_product_id where id=p_id;
end $$;
grant execute on function public.admin_approve_publish_supplier_product(uuid,numeric,text) to authenticated;

create or replace function public.admin_supplier_workflow_overview()
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 return jsonb_build_object(
 'pending_suppliers',(select count(*) from public.suppliers where status='pending'),
 'approved_suppliers',(select count(*) from public.suppliers where status='approved'),
 'pending_products',(select count(*) from public.supplier_products where status='pending'),
 'published_products',(select count(*) from public.supplier_products where status='approved' and store_product_id is not null),
 'supplier_orders',(select count(*) from public.supplier_order_items where status<>'cancelled'),
 'payable',coalesce((select sum(supplier_amount) from public.supplier_order_items where status='payable'),0),
 'paid',coalesce((select sum(supplier_amount) from public.supplier_order_items where status='paid'),0),
 'blnk_margin',coalesce((select sum(blnk_gross_margin) from public.supplier_order_items where status<>'cancelled'),0)
 );
end $$;
grant execute on function public.admin_supplier_workflow_overview() to authenticated;
