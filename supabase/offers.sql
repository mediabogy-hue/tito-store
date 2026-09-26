-- BLNK Offers Center
create table if not exists public.offers_campaigns(
 id uuid primary key default gen_random_uuid(),
 title text not null,
 message text not null,
 template_name text,
 template_language text not null default 'ar',
 audience text not null default 'all',
 status text not null default 'draft',
 total_recipients integer not null default 0,
 sent_count integer not null default 0,
 failed_count integer not null default 0,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 sent_at timestamptz
);
alter table public.offers_campaigns enable row level security;
revoke all on public.offers_campaigns from anon,authenticated;

create or replace function public.admin_offer_recipients()
returns table(customer_id uuid,full_name text,whatsapp text)
language sql security definer set search_path=public as $$
 select p.id,p.full_name,coalesce(nullif(p.whatsapp,''),nullif(p.phone,''))
 from public.profiles p
 where public.is_admin() and coalesce(nullif(p.whatsapp,''),nullif(p.phone,'')) is not null
 order by p.full_name
$$;
revoke all on function public.admin_offer_recipients() from public;
grant execute on function public.admin_offer_recipients() to authenticated;

create or replace function public.admin_create_offer(p_title text,p_message text,p_template_name text default null,p_template_language text default 'ar')
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_count integer;
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 select count(*) into v_count from public.profiles where coalesce(nullif(whatsapp,''),nullif(phone,'')) is not null;
 insert into public.offers_campaigns(title,message,template_name,template_language,total_recipients,created_by)
 values(trim(p_title),trim(p_message),nullif(trim(p_template_name),''),coalesce(nullif(trim(p_template_language),''),'ar'),v_count,auth.uid())
 returning id into v_id;
 return v_id;
end $$;
revoke all on function public.admin_create_offer(text,text,text,text) from public;
grant execute on function public.admin_create_offer(text,text,text,text) to authenticated;

create or replace function public.admin_offers()
returns setof public.offers_campaigns language sql security definer set search_path=public as $$
 select * from public.offers_campaigns where public.is_admin() order by created_at desc
$$;
revoke all on function public.admin_offers() from public;
grant execute on function public.admin_offers() to authenticated;
