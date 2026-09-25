-- Secure self-service style-profile update. Keeps wallet/points/tier server-controlled.
revoke update on public.profiles from authenticated;

create or replace function public.update_my_style_profile(p_style_profile jsonb)
returns void language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 update public.profiles
 set style_profile=coalesce(p_style_profile,'{}'::jsonb), updated_at=now()
 where id=auth.uid();
end $$;

revoke all on function public.update_my_style_profile(jsonb) from public;
grant execute on function public.update_my_style_profile(jsonb) to authenticated;