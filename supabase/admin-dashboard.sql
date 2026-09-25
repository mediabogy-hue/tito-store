-- BLNK admin security + dashboard RPCs
create table if not exists public.admin_users(user_id uuid primary key references auth.users(id) on delete cascade,created_at timestamptz not null default now());
alter table public.admin_users enable row level security;
revoke all on public.admin_users from anon,authenticated;

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.admin_users where user_id=auth.uid()) $$;
grant execute on function public.is_admin() to authenticated;

create or replace function public.admin_search_customers(p_query text)
returns table(id uuid,customer_code text,full_name text,phone text,balance numeric,points integer,club_tier text)
language sql security definer set search_path=public as $$
 select p.id,p.customer_code,p.full_name,p.phone,p.balance,p.points,p.club_tier from public.profiles p
 where public.is_admin() and (p.customer_code ilike '%'||p_query||'%' or p.phone ilike '%'||p_query||'%' or p.full_name ilike '%'||p_query||'%')
 order by p.updated_at desc limit 30 $$;
grant execute on function public.admin_search_customers(text) to authenticated;

create or replace function public.admin_customer_detail(p_customer_id uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb; begin if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
select jsonb_build_object('profile',to_jsonb(p),'invoices',coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at desc) from public.invoices i where i.customer_id=p.id),'[]'::jsonb),'wallet',coalesce((select jsonb_agg(to_jsonb(w) order by w.created_at desc) from (select * from public.wallet_transactions where customer_id=p.id order by created_at desc limit 50) w),'[]'::jsonb)) into r from public.profiles p where p.id=p_customer_id; return r; end $$;
grant execute on function public.admin_customer_detail(uuid) to authenticated;

create or replace function public.admin_adjust_customer(p_customer_id uuid,p_kind text,p_amount numeric,p_note text) returns void language plpgsql security definer set search_path=public as $$
begin if not public.is_admin() then raise exception 'FORBIDDEN'; end if; if p_amount=0 then raise exception 'ZERO_AMOUNT'; end if;
if p_kind='balance' then update public.profiles set balance=balance+p_amount,updated_at=now() where id=p_customer_id; if (select balance from public.profiles where id=p_customer_id)<0 then raise exception 'NEGATIVE_BALANCE'; end if; insert into public.wallet_transactions(customer_id,amount,type,description,reference_type) values(p_customer_id,p_amount,'admin_adjustment',p_note,'admin');
elsif p_kind='points' then update public.profiles set points=points+p_amount::integer,updated_at=now() where id=p_customer_id; if (select points from public.profiles where id=p_customer_id)<0 then raise exception 'NEGATIVE_POINTS'; end if; else raise exception 'INVALID_KIND'; end if; end $$;
grant execute on function public.admin_adjust_customer(uuid,text,numeric,text) to authenticated;

-- IMPORTANT: after creating your own Supabase Auth account, add it as admin:
-- insert into public.admin_users(user_id) select id from auth.users where email='YOUR-ADMIN-EMAIL';