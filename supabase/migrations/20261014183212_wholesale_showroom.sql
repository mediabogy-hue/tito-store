-- BLNK wholesale showroom: supplier Telegram intake, admin approval, and public catalog.
-- Prices are always calculated from supplier_price + the configured per-piece markup.

create table if not exists public.wholesale_settings (
  id integer primary key default 1 check (id = 1),
  markup_per_piece numeric(12,2) not null default 10 check (markup_per_piece >= 0),
  updated_at timestamptz not null default now()
);
insert into public.wholesale_settings(id, markup_per_piece)
values (1, 10) on conflict (id) do nothing;

alter table public.supplier_products
  add column if not exists category text,
  add column if not exists minimum_order_quantity integer not null default 1 check (minimum_order_quantity >= 1),
  add column if not exists source_channel text,
  add column if not exists source_message_url text,
  add column if not exists source_message text,
  add column if not exists updated_at timestamptz not null default now();

alter table public.wholesale_settings enable row level security;
revoke all on public.wholesale_settings from anon, authenticated;

create or replace function public.public_wholesale_catalog()
returns table (
  id uuid,
  name text,
  category text,
  supplier_name text,
  price numeric,
  stock integer,
  image text,
  note text,
  sizes text[],
  colors text[],
  minimum_order_quantity integer,
  updated_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  select p.id,
         p.name,
         coalesce(nullif(p.category, ''), nullif(s.category, ''), 'ملابس رجالي')::text,
         s.business_name,
         (p.supplier_price + coalesce(w.markup_per_piece, 10))::numeric,
         p.stock,
         p.image_url,
         coalesce(p.description, '')::text,
         case when nullif(trim(coalesce(p.sizes, '')), '') is null then array[]::text[] else string_to_array(p.sizes, ',') end,
         case when nullif(trim(coalesce(p.colors, '')), '') is null then array[]::text[] else string_to_array(p.colors, ',') end,
         p.minimum_order_quantity,
         p.updated_at
    from public.supplier_products p
    join public.suppliers s on s.id = p.supplier_id and s.status = 'approved'
    cross join public.wholesale_settings w
   where p.status = 'approved'
     and p.stock > 0
     and trim(coalesce(p.image_url, '')) <> ''
   order by p.updated_at desc;
$$;
revoke all on function public.public_wholesale_catalog() from public, anon, authenticated;
grant execute on function public.public_wholesale_catalog() to anon, authenticated;

create or replace function public.admin_wholesale_settings()
returns table(markup_per_piece numeric)
language sql security definer set search_path = '' as $$
  select w.markup_per_piece from public.wholesale_settings w
  where public.is_admin();
$$;
revoke all on function public.admin_wholesale_settings() from public, anon, authenticated;
grant execute on function public.admin_wholesale_settings() to authenticated;

create or replace function public.admin_set_wholesale_markup(p_markup numeric)
returns numeric
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  if p_markup is null or p_markup < 0 or p_markup > 100000 then raise exception 'INVALID_MARKUP'; end if;
  update public.wholesale_settings set markup_per_piece = round(p_markup, 2), updated_at = now() where id = 1;
  return round(p_markup, 2);
end;
$$;
revoke all on function public.admin_set_wholesale_markup(numeric) from public, anon, authenticated;
grant execute on function public.admin_set_wholesale_markup(numeric) to authenticated;

create or replace function public.admin_wholesale_intake()
returns table (
  id uuid, supplier_id uuid, supplier_name text, name text, category text,
  supplier_price numeric, listing_price numeric, stock integer, image_url text,
  description text, sizes text, colors text, minimum_order_quantity integer,
  status text, source_channel text, source_message_url text, source_message text,
  created_at timestamptz, updated_at timestamptz
)
language sql security definer set search_path = '' as $$
  select p.id, p.supplier_id, s.business_name, p.name,
         coalesce(nullif(p.category, ''), s.category, ''), p.supplier_price,
         p.supplier_price + coalesce(w.markup_per_piece, 10), p.stock, p.image_url,
         p.description, p.sizes, p.colors, p.minimum_order_quantity,
         p.status, p.source_channel, p.source_message_url, p.source_message,
         p.created_at, p.updated_at
    from public.supplier_products p
    join public.suppliers s on s.id = p.supplier_id
    cross join public.wholesale_settings w
   where public.is_admin()
   order by case when p.status = 'pending' then 0 else 1 end, p.updated_at desc;
$$;
revoke all on function public.admin_wholesale_intake() from public, anon, authenticated;
grant execute on function public.admin_wholesale_intake() to authenticated;

create or replace function public.admin_import_telegram_product(
  p_supplier_id uuid, p_name text, p_category text, p_supplier_price numeric,
  p_stock integer, p_image_url text, p_description text, p_sizes text,
  p_colors text, p_minimum_order_quantity integer, p_source_channel text,
  p_source_message_url text, p_source_message text
)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  if nullif(trim(coalesce(p_name, '')), '') is null then raise exception 'PRODUCT_NAME_REQUIRED'; end if;
  if p_supplier_price is null or p_supplier_price < 0 then raise exception 'INVALID_SUPPLIER_PRICE'; end if;
  if p_stock is null or p_stock < 0 then raise exception 'INVALID_STOCK'; end if;
  if p_minimum_order_quantity is null or p_minimum_order_quantity < 1 then raise exception 'INVALID_MINIMUM_ORDER'; end if;
  if not exists (select 1 from public.suppliers s where s.id = p_supplier_id and s.status = 'approved') then
    raise exception 'APPROVED_SUPPLIER_REQUIRED';
  end if;
  insert into public.supplier_products(
    supplier_id, name, description, image_url, sizes, colors, supplier_price,
    stock, status, category, minimum_order_quantity, source_channel,
    source_message_url, source_message, updated_at
  ) values (
    p_supplier_id, trim(p_name), nullif(trim(coalesce(p_description, '')), ''),
    nullif(trim(coalesce(p_image_url, '')), ''), nullif(trim(coalesce(p_sizes, '')), ''),
    nullif(trim(coalesce(p_colors, '')), ''), round(p_supplier_price, 2), p_stock,
    'pending', nullif(trim(coalesce(p_category, '')), ''), p_minimum_order_quantity,
    nullif(trim(coalesce(p_source_channel, '')), ''),
    nullif(trim(coalesce(p_source_message_url, '')), ''),
    nullif(trim(coalesce(p_source_message, '')), ''), now()
  ) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.admin_import_telegram_product(uuid,text,text,numeric,integer,text,text,text,text,integer,text,text,text) from public, anon, authenticated;
grant execute on function public.admin_import_telegram_product(uuid,text,text,numeric,integer,text,text,text,text,integer,text,text,text) to authenticated;

create or replace function public.admin_publish_wholesale_product(p_id uuid)
returns numeric
language plpgsql security definer set search_path = '' as $$
declare v_price numeric;
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  update public.supplier_products p
     set status = 'approved',
         selling_price = p.supplier_price + coalesce((select w.markup_per_piece from public.wholesale_settings w where w.id = 1), 10),
         updated_at = now()
    from public.suppliers s
   where p.id = p_id and s.id = p.supplier_id and s.status = 'approved'
     and p.stock > 0 and trim(coalesce(p.image_url, '')) <> ''
  returning p.selling_price into v_price;
  if v_price is null then raise exception 'PRODUCT_NEEDS_APPROVED_SUPPLIER_IMAGE_AND_STOCK'; end if;
  return v_price;
end;
$$;
revoke all on function public.admin_publish_wholesale_product(uuid) from public, anon, authenticated;
grant execute on function public.admin_publish_wholesale_product(uuid) to authenticated;

create or replace function public.admin_supplier_outreach_recipients()
returns table(supplier_id uuid, business_name text, contact_name text, whatsapp text)
language sql security definer set search_path = '' as $$
  select s.id, s.business_name, s.contact_name,
         coalesce(nullif(s.whatsapp, ''), nullif(s.phone, ''))
    from public.suppliers s
   where public.is_admin()
     and s.status <> 'suspended'
     and coalesce(nullif(s.whatsapp, ''), nullif(s.phone, '')) is not null
   order by s.business_name;
$$;
revoke all on function public.admin_supplier_outreach_recipients() from public, anon, authenticated;
grant execute on function public.admin_supplier_outreach_recipients() to authenticated;

create or replace function public.admin_create_supplier_outreach(p_title text, p_message text)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_count integer;
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  if nullif(trim(coalesce(p_title, '')), '') is null or nullif(trim(coalesce(p_message, '')), '') is null then
    raise exception 'TITLE_AND_MESSAGE_REQUIRED';
  end if;
  select count(*) into v_count from public.suppliers s
   where s.status <> 'suspended' and coalesce(nullif(s.whatsapp, ''), nullif(s.phone, '')) is not null;
  insert into public.offers_campaigns(title, message, audience, status, total_recipients, created_by)
  values(trim(p_title), trim(p_message), 'suppliers', 'draft', v_count, auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.admin_create_supplier_outreach(text,text) from public, anon, authenticated;
grant execute on function public.admin_create_supplier_outreach(text,text) to authenticated;
