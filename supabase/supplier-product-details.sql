-- BLNK supplier product publishing details v5
alter table public.supplier_products add column if not exists image_url text;
alter table public.supplier_products add column if not exists description text;
alter table public.supplier_products add column if not exists sizes text;
alter table public.supplier_products add column if not exists colors text;

create or replace function public.admin_update_supplier_product(p_id uuid,p_selling_price numeric,p_stock integer,p_description text,p_image_url text,p_sizes text,p_colors text)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 update public.supplier_products set selling_price=greatest(0,p_selling_price),stock=greatest(0,p_stock),description=nullif(trim(p_description),''),image_url=nullif(trim(p_image_url),''),sizes=nullif(trim(p_sizes),''),colors=nullif(trim(p_colors),'') where id=p_id;
end $$;
grant execute on function public.admin_update_supplier_product(uuid,numeric,integer,text,text,text,text) to authenticated;

drop function if exists public.admin_supplier_products();
create function public.admin_supplier_products()
returns table(id uuid,supplier_id uuid,supplier_name text,name text,supplier_price numeric,selling_price numeric,stock integer,status text,store_product_id text,description text,image_url text,sizes text,colors text,created_at timestamptz)
language sql security definer set search_path=public as $$
select p.id,p.supplier_id,s.business_name,p.name,p.supplier_price,p.selling_price,p.stock,p.status,p.store_product_id,p.description,p.image_url,p.sizes,p.colors,p.created_at
from public.supplier_products p join public.suppliers s on s.id=p.supplier_id where public.is_admin() order by p.created_at desc
$$;
grant execute on function public.admin_supplier_products() to authenticated;
