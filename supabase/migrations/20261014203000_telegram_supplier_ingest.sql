-- Secure Telegram channel-to-supplier mapping and review inbox.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('blnk-supplier-products','blnk-supplier-products',true,10485760,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true,file_size_limit=10485760,allowed_mime_types=array['image/jpeg','image/png','image/webp'];

create table if not exists public.telegram_supplier_channels(
  telegram_chat_id text primary key,
  supplier_id uuid not null references public.suppliers(id),
  channel_title text,
  username text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.telegram_webhook_updates(
  update_id bigint primary key,
  status text not null default 'processing' check(status in ('processing','processed','failed')),
  error text,
  created_at timestamptz not null default now(),
  processed_at timestamptz
);
create table if not exists public.telegram_supplier_intake(
  id uuid primary key default gen_random_uuid(),
  update_id bigint not null unique references public.telegram_webhook_updates(update_id),
  supplier_id uuid references public.suppliers(id),
  telegram_chat_id text not null,
  channel_title text,
  username text,
  message_id bigint not null,
  source_message_url text,
  source_message text,
  image_url text,
  parsed_name text,
  parsed_supplier_price numeric(12,2),
  parsed_stock integer,
  product_id uuid references public.supplier_products(id),
  status text not null default 'needs_review' check(status in ('unmapped','needs_review','imported','ignored')),
  created_at timestamptz not null default now()
);
alter table public.supplier_products add column if not exists telegram_update_id bigint;
create unique index if not exists supplier_products_telegram_update_id_uq on public.supplier_products(telegram_update_id) where telegram_update_id is not null;
create index if not exists telegram_intake_created_idx on public.telegram_supplier_intake(created_at desc);
create index if not exists telegram_intake_supplier_idx on public.telegram_supplier_intake(supplier_id,created_at desc);
alter table public.telegram_supplier_channels enable row level security;
alter table public.telegram_webhook_updates enable row level security;
alter table public.telegram_supplier_intake enable row level security;
revoke all on public.telegram_supplier_channels,public.telegram_webhook_updates,public.telegram_supplier_intake from anon,authenticated;

create or replace function public.admin_telegram_channels()
returns table(telegram_chat_id text,supplier_id uuid,supplier_name text,channel_title text,username text,active boolean,created_at timestamptz)
language sql security definer set search_path=public as $$
 select c.telegram_chat_id,c.supplier_id,s.business_name,c.channel_title,c.username,c.active,c.created_at
 from public.telegram_supplier_channels c join public.suppliers s on s.id=c.supplier_id
 where public.is_admin() order by c.created_at desc
$$;
revoke all on function public.admin_telegram_channels() from public,anon;
grant execute on function public.admin_telegram_channels() to authenticated;

create or replace function public.admin_map_telegram_channel(p_supplier_id uuid,p_chat_id text,p_title text,p_username text)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 if p_chat_id is null or length(p_chat_id)<5 or length(p_chat_id)>25 or p_chat_id !~ '^-?[0-9]+$' then raise exception 'INVALID_TELEGRAM_CHAT_ID'; end if;
 if not exists(select 1 from public.suppliers where id=p_supplier_id and status='approved') then raise exception 'APPROVED_SUPPLIER_REQUIRED'; end if;
 insert into public.telegram_supplier_channels(telegram_chat_id,supplier_id,channel_title,username,active,updated_at)
 values(p_chat_id,p_supplier_id,nullif(trim(p_title),''),nullif(trim(leading '@' from p_username),''),true,now())
 on conflict(telegram_chat_id) do update set supplier_id=excluded.supplier_id,channel_title=excluded.channel_title,username=excluded.username,active=true,updated_at=now();
end $$;
revoke all on function public.admin_map_telegram_channel(uuid,text,text,text) from public,anon;
grant execute on function public.admin_map_telegram_channel(uuid,text,text,text) to authenticated;

create or replace function public.admin_telegram_intake()
returns table(id uuid,supplier_id uuid,supplier_name text,telegram_chat_id text,channel_title text,username text,message_id bigint,source_message_url text,source_message text,image_url text,parsed_name text,parsed_supplier_price numeric,parsed_stock integer,product_id uuid,status text,created_at timestamptz)
language sql security definer set search_path=public as $$
 select i.id,i.supplier_id,s.business_name,i.telegram_chat_id,i.channel_title,i.username,i.message_id,i.source_message_url,i.source_message,i.image_url,i.parsed_name,i.parsed_supplier_price,i.parsed_stock,i.product_id,i.status,i.created_at
 from public.telegram_supplier_intake i left join public.suppliers s on s.id=i.supplier_id
 where public.is_admin() order by i.created_at desc limit 100
$$;
revoke all on function public.admin_telegram_intake() from public,anon;
grant execute on function public.admin_telegram_intake() to authenticated;

create or replace function public.admin_mark_telegram_intake_imported(p_intake_id uuid,p_product_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 if not exists(select 1 from public.telegram_supplier_intake where id=p_intake_id) then raise exception 'INTAKE_NOT_FOUND'; end if;
 update public.telegram_supplier_intake set status='imported',product_id=p_product_id
 where id=p_intake_id and status<>'imported';
 if not found then raise exception 'INTAKE_ALREADY_IMPORTED'; end if;
end $$;
revoke all on function public.admin_mark_telegram_intake_imported(uuid,uuid) from public,anon;
grant execute on function public.admin_mark_telegram_intake_imported(uuid,uuid) to authenticated;
