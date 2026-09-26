-- BLNK Supplier Portal product details v6
drop function if exists public.supplier_add_product(text,numeric,integer);
create function public.supplier_add_product(p_name text,p_supplier_price numeric,p_stock integer,p_description text default null,p_image_url text default null,p_sizes text default null,p_colors text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare sid uuid; v uuid;
begin
 select id into sid from public.suppliers where user_id=auth.uid() and status='approved';
 if sid is null then raise exception 'SUPPLIER_NOT_APPROVED'; end if;
 if trim(coalesce(p_name,''))='' then raise exception 'PRODUCT_NAME_REQUIRED'; end if;
 insert into public.supplier_products(supplier_id,name,supplier_price,stock,status,description,image_url,sizes,colors)
 values(sid,trim(p_name),greatest(0,p_supplier_price),greatest(0,p_stock),'pending',nullif(trim(p_description),''),nullif(trim(p_image_url),''),nullif(trim(p_sizes),''),nullif(trim(p_colors),''))
 returning id into v;
 return v;
end $$;
grant execute on function public.supplier_add_product(text,numeric,integer,text,text,text,text) to authenticated;

drop function if exists public.supplier_my_products();
create function public.supplier_my_products()
returns table(id uuid,name text,supplier_price numeric,selling_price numeric,stock integer,status text,description text,image_url text,sizes text,colors text,store_product_id text,created_at timestamptz)
language sql security definer set search_path=public as $$
 select p.id,p.name,p.supplier_price,p.selling_price,p.stock,p.status,p.description,p.image_url,p.sizes,p.colors,p.store_product_id,p.created_at
 from public.supplier_products p join public.suppliers s on s.id=p.supplier_id where s.user_id=auth.uid() order by p.created_at desc
$$;
grant execute on function public.supplier_my_products() to authenticated;
