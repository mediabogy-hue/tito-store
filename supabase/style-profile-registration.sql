-- Run once in Supabase SQL Editor to add registration style profile fields
alter table public.profiles add column if not exists style_profile jsonb not null default '{}'::jsonb;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into public.profiles(id,full_name,phone,city,style_profile)
 values(
  new.id,
  new.raw_user_meta_data->>'full_name',
  nullif(new.raw_user_meta_data->>'phone',''),
  new.raw_user_meta_data->>'city',
  coalesce(new.raw_user_meta_data->'style_profile','{}'::jsonb)
 )
 on conflict(id) do update set
  full_name=excluded.full_name,
  phone=coalesce(excluded.phone,public.profiles.phone),
  city=excluded.city,
  style_profile=excluded.style_profile,
  updated_at=now();
 return new;
end $$;