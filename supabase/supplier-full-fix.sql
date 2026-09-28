-- BLNK supplier full workflow fix v8
-- Self-registration, required product images, and public live supplier catalog.

alter table public.suppliers add column if not exists user_id uuid references auth.users(id);
alter table public.suppliers add column if not exists email text;
alter table public.supplier_products add column if not exists store_product_id text;
alter table public.supplier_products add column if not exists description text;
alter table public.supplier_products add column if not exists image_url text;
alter table public.supplier_products add column if not exists sizes text;
alter table public.supplier_products add column if not exists colors text;
create unique index if not exists suppliers_user_id_uidx on public.suppliers(user_id) where user_id is not null;
create unique index if not exists suppliers_email_uidx on public.suppliers(lower(email)) where email is not null;

create or replace function public.supplier_register_self(
 p_business_name text,p_contact_name text,p_phone text,p_whatsapp text default null,
 p_address text default null,p_category text default null
) returns uuid language plpgsql security definer set search_path=public as $$
declare v uuid; v_email text;
begin
 if auth.uid() is null then raise exception 'LOGIN_REQUIRED'; end if;
 v_email:=lower(coalesce(auth.jwt()->>'email',''));
 if v_email='' then raise exception 'EMAIL_REQUIRED'; end if;
 select id into v from public.suppliers where user_id=auth.uid() or lower(coalesce(email,''))=v_email limit 1;
 if v is not null then
   update public.suppliers set user_id=coalesce(user_id,auth.uid()),email=v_email,
     business_name=trim(p_business_name),contact_name=trim(p_contact_name),phone=trim(p_phone),
     whatsapp=nullif(trim(p_whatsapp),''),address=nullif(trim(p_address),''),category=nullif(trim(p_category),'')
   where id=v;
   return v;
 end if;
 insert into public.suppliers(user_id,email,business_name,contact_name,phone,whatsapp,address,category,status)
 values(auth.uid(),v_email,trim(p_business_name),trim(p_contact_name),trim(p_phone),
 nullif(trim(p_whatsapp),''),nullif(trim(p_address),''),nullif(trim(p_category),''),'pending')
 returning id into v;
 return v;
end $$;
grant execute on function public.supplier_register_self(text,text,text,text,text,text) to authenticated;

drop function if exists public.supplier_add_product(text,numeric,integer,text,text,text,text);
create function public.supplier_add_product(
 p_name text,p_supplier_price numeric,p_stock integer,p_description text default null,
 p_image_url text default null,p_sizes text default null,p_colors text default null
) returns uuid language plpgsql security definer set search_path=public as $$
declare sid uuid; v uuid;
begin
 select id into sid from public.suppliers where user_id=auth.uid() and status='approved';
 if sid is null then raise exception 'SUPPLIER_NOT_APPROVED'; end if;
 if trim(coalesce(p_name,''))='' then raise exception 'PRODUCT_NAME_REQUIRED'; end if;
 if trim(coalesce(p_image_url,''))='' then raise exception 'PRODUCT_IMAGE_REQUIRED'; end if;
 if coalesce(p_supplier_price,-1)<0 then raise exception 'VALID_SUPPLIER_PRICE_REQUIRED'; end if;
 if coalesce(p_stock,-1)<0 then raise exception 'VALID_STOCK_REQUIRED'; end if;
 insert into public.supplier_products(supplier_id,name,supplier_price,stock,status,description,image_url,sizes,colors)
 values(sid,trim(p_name),p_supplier_price,p_stock,'pending',nullif(trim(p_description),''),
 trim(p_image_url),nullif(trim(p_sizes),''),nullif(trim(p_colors),'')) returning id into v;
 return v;
end $$;
grant execute on function public.supplier_add_product(text,numeric,integer,text,text,text,text) to authenticated;

drop function if exists public.supplier_my_products();
create function public.supplier_my_products()
returns table(id uuid,name text,supplier_price numeric,selling_price numeric,stock integer,status text,
 description text,image_url text,sizes text,colors text,store_product_id text,created_at timestamptz)
language sql security definer set search_path=public as $$
 select p.id,p.name,p.supplier_price,p.selling_price,p.stock,p.status,p.description,p.image_url,
 p.sizes,p.colors,p.store_product_id,p.created_at
 from public.supplier_products p join public.suppliers s on s.id=p.supplier_id
 where s.user_id=auth.uid() order by p.created_at desc
$$;
grant execute on function public.supplier_my_products() to authenticated;

drop function if exists public.admin_supplier_products();
create function public.admin_supplier_products()
returns table(id uuid,supplier_id uuid,supplier_name text,name text,supplier_price numeric,selling_price numeric,
 stock integer,status text,store_product_id text,description text,image_url text,sizes text,colors text,created_at timestamptz)
language sql security definer set search_path=public as $$
 select p.id,p.supplier_id,s.business_name,p.name,p.supplier_price,p.selling_price,p.stock,p.status,
 p.store_product_id,p.description,p.image_url,p.sizes,p.colors,p.created_at
 from public.supplier_products p join public.suppliers s on s.id=p.supplier_id
 where public.is_admin() order by p.created_at desc
$$;
grant execute on function public.admin_supplier_products() to authenticated;

create or replace function public.admin_approve_publish_supplier_product(p_id uuid,p_selling_price numeric,p_store_product_id text)
returns void language plpgsql security definer set search_path=public as $$
declare sp public.supplier_products%rowtype;
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 select * into sp from public.supplier_products where id=p_id;
 if sp.id is null then raise exception 'PRODUCT_NOT_FOUND'; end if;
 if trim(coalesce(sp.image_url,''))='' then raise exception 'PRODUCT_IMAGE_REQUIRED'; end if;
 if p_selling_price is null or p_selling_price<sp.supplier_price then raise exception 'SELLING_PRICE_BELOW_SUPPLIER_COST'; end if;
 update public.supplier_products set status='approved',selling_price=p_selling_price,store_product_id=p_store_product_id where id=p_id;
 insert into public.store_products(id,name,price,active,updated_at)
 values(p_store_product_id,sp.name,p_selling_price,true,now())
 on conflict(id) do update set name=excluded.name,price=excluded.price,active=true,updated_at=now();
 insert into public.inventory(product_id,stock,updated_at) values(p_store_product_id,sp.stock,now())
 on conflict(product_id) do update set stock=excluded.stock,updated_at=now();
end $$;
grant execute on function public.admin_approve_publish_supplier_product(uuid,numeric,text) to authenticated;

create or replace function public.public_supplier_catalog()
returns table(id text,name text,category text,price numeric,stock integer,image text,note text,sizes text[],colors text[],active boolean)
language sql security definer set search_path=public stable as $$
 select coalesce(p.store_product_id,'supplier-'||left(p.id::text,8))::text,
 p.name,coalesce(nullif(s.category,''),'all')::text,p.selling_price,p.stock,p.image_url,
 coalesce(p.description,'')::text,
 case when nullif(trim(p.sizes),'') is null then array[]::text[] else string_to_array(p.sizes,',') end,
 case when nullif(trim(p.colors),'') is null then array[]::text[] else string_to_array(p.colors,',') end,
 true
 from public.supplier_products p join public.suppliers s on s.id=p.supplier_id
 where p.status='approved' and p.store_product_id is not null and p.selling_price is not null
 and p.stock>0 and trim(coalesce(p.image_url,''))<>''
 order by p.created_at desc
$$;
grant execute on function public.public_supplier_catalog() to anon,authenticated;
