-- BLNK customer identity QR + full delivery profile
alter table public.profiles add column if not exists address text;
alter table public.profiles add column if not exists whatsapp text;

create or replace function public.customer_public_card(p_code text)
returns jsonb language sql security definer set search_path=public as $$
 select jsonb_build_object(
  'customer_code',p.customer_code,'full_name',p.full_name,'phone',p.phone,
  'whatsapp',coalesce(p.whatsapp,p.phone),'city',p.city,'address',p.address,
  'club_tier',p.club_tier,'style_profile',p.style_profile
 ) from public.profiles p where p.customer_code=p_code
$$;
grant execute on function public.customer_public_card(text) to anon,authenticated;

create or replace function public.update_my_contact(p_city text,p_address text,p_whatsapp text)
returns void language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null then raise exception 'LOGIN_REQUIRED'; end if;
 update public.profiles set city=p_city,address=p_address,whatsapp=p_whatsapp,updated_at=now() where id=auth.uid();
end $$;
grant execute on function public.update_my_contact(text,text,text) to authenticated;
