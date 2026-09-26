-- BLNK Supplier Portal v2 (run after suppliers.sql)
alter table public.suppliers add column if not exists user_id uuid references auth.users(id);
alter table public.suppliers add column if not exists email text;
create unique index if not exists suppliers_user_id_uidx on public.suppliers(user_id) where user_id is not null;

create or replace function public.claim_supplier_account()
returns uuid language plpgsql security definer set search_path=public as $$
declare v uuid; v_email text;
begin
 v_email:=lower(coalesce(auth.jwt()->>'email',''));
 if auth.uid() is null then raise exception 'LOGIN_REQUIRED'; end if;
 select id into v from public.suppliers where user_id=auth.uid() limit 1;
 if v is not null then return v; end if;
 select id into v from public.suppliers where lower(coalesce(email,''))=v_email and status='approved' and user_id is null limit 1;
 if v is null then raise exception 'SUPPLIER_NOT_APPROVED'; end if;
 update public.suppliers set user_id=auth.uid() where id=v; return v;
end $$;
grant execute on function public.claim_supplier_account() to authenticated;

create or replace function public.supplier_my_profile()
returns table(id uuid,business_name text,contact_name text,phone text,whatsapp text,address text,category text,status text)
language sql security definer set search_path=public as $$
 select s.id,s.business_name,s.contact_name,s.phone,s.whatsapp,s.address,s.category,s.status
 from public.suppliers s where s.user_id=auth.uid()
$$;
grant execute on function public.supplier_my_profile() to authenticated;

create or replace function public.supplier_my_products()
returns table(id uuid,name text,supplier_price numeric,selling_price numeric,stock integer,status text,created_at timestamptz)
language sql security definer set search_path=public as $$
 select p.id,p.name,p.supplier_price,p.selling_price,p.stock,p.status,p.created_at
 from public.supplier_products p join public.suppliers s on s.id=p.supplier_id where s.user_id=auth.uid() order by p.created_at desc
$$;
grant execute on function public.supplier_my_products() to authenticated;

create or replace function public.supplier_add_product(p_name text,p_supplier_price numeric,p_stock integer)
returns uuid language plpgsql security definer set search_path=public as $$
declare sid uuid; v uuid; begin
 select id into sid from public.suppliers where user_id=auth.uid() and status='approved';
 if sid is null then raise exception 'SUPPLIER_NOT_APPROVED'; end if;
 insert into public.supplier_products(supplier_id,name,supplier_price,stock,status) values(sid,trim(p_name),p_supplier_price,p_stock,'pending') returning id into v; return v;
end $$;
grant execute on function public.supplier_add_product(text,numeric,integer) to authenticated;

create or replace function public.admin_create_supplier_v2(p_business_name text,p_contact_name text,p_phone text,p_email text,p_whatsapp text default null,p_address text default null,p_category text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v uuid; begin if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
insert into public.suppliers(business_name,contact_name,phone,email,whatsapp,address,category) values(trim(p_business_name),trim(p_contact_name),trim(p_phone),lower(trim(p_email)),nullif(trim(p_whatsapp),''),nullif(trim(p_address),''),nullif(trim(p_category),'')) returning id into v; return v; end $$;
grant execute on function public.admin_create_supplier_v2(text,text,text,text,text,text,text) to authenticated;
