-- Seasonal loyalty points convert to BLNK purchase credit at season close.
-- Legacy profile.points are preserved and are not included in historical settlements.
create table if not exists public.loyalty_seasons (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  starts_on date not null,
  ends_on date not null,
  status text not null default 'draft' check (status in ('draft','active','closed')),
  created_at timestamptz not null default now(),
  closed_at timestamptz,
  check (ends_on >= starts_on)
);
create unique index if not exists loyalty_one_active_season on public.loyalty_seasons(status) where status='active';

create table if not exists public.loyalty_events (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.loyalty_seasons(id),
  customer_id uuid not null references public.profiles(id),
  reference_type text not null check(reference_type in ('invoice','order')),
  reference_id text not null,
  eligible_spend numeric(12,2) not null check(eligible_spend>=0),
  points_delta integer not null check(points_delta>=0),
  reversed boolean not null default false,
  created_at timestamptz not null default now(),
  unique(reference_type,reference_id)
);
create table if not exists public.loyalty_settlements (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.loyalty_seasons(id),
  customer_id uuid not null references public.profiles(id),
  points integer not null check(points>0),
  credit_amount numeric(12,2) not null check(credit_amount>0),
  created_at timestamptz not null default now(),
  unique(season_id,customer_id)
);
create index if not exists loyalty_events_customer_id_idx on public.loyalty_events(customer_id);
create index if not exists loyalty_events_season_id_idx on public.loyalty_events(season_id);
create index if not exists loyalty_settlements_customer_id_idx on public.loyalty_settlements(customer_id);
alter table public.loyalty_seasons enable row level security;
alter table public.loyalty_events enable row level security;
alter table public.loyalty_settlements enable row level security;
revoke all on public.loyalty_seasons,public.loyalty_events,public.loyalty_settlements from anon,authenticated;

create or replace function public.loyalty_award(p_customer_id uuid,p_reference_type text,p_reference_id text,p_spend numeric)
returns integer language plpgsql security definer set search_path=public as $$
declare s public.loyalty_seasons%rowtype; n integer;
begin
  if p_reference_type not in ('invoice','order') or p_spend is null or p_spend<=0 then return 0; end if;
  select * into s from public.loyalty_seasons where status='active' and current_date between starts_on and ends_on for share;
  if not found then return 0; end if;
  n:=floor(p_spend/100)::integer;
  if n<1 then return 0; end if;
  insert into public.loyalty_events(season_id,customer_id,reference_type,reference_id,eligible_spend,points_delta)
  values(s.id,p_customer_id,p_reference_type,p_reference_id,p_spend,n)
  on conflict(reference_type,reference_id) do nothing;
  if found then update public.profiles set points=points+n,updated_at=now() where id=p_customer_id; return n; end if;
  return 0;
end $$;
revoke all on function public.loyalty_award(uuid,text,text,numeric) from public,anon,authenticated;

create or replace function public.loyalty_order_status_trigger()
returns trigger language plpgsql security definer set search_path=public as $$
declare n integer;
begin
  if new.status='delivered' and old.status is distinct from new.status then
    perform public.loyalty_award(new.customer_id,'order',new.id::text,new.total);
  elsif new.status='cancelled' and old.status is distinct from new.status then
    update public.loyalty_events e set reversed=true
    from public.loyalty_seasons s
    where e.reference_type='order' and e.reference_id=new.id::text and e.reversed=false
      and e.season_id=s.id and s.status<>'closed';
    get diagnostics n = row_count;
    if n>0 then update public.profiles p set points=greatest(0,p.points-x.points),updated_at=now()
      from (select customer_id,sum(points_delta)::integer points from public.loyalty_events where reference_type='order' and reference_id=new.id::text and reversed=true group by customer_id) x
      where p.id=x.customer_id; end if;
  end if;
  return new;
end $$;
drop trigger if exists loyalty_order_status on public.orders;
create trigger loyalty_order_status after update of status on public.orders for each row execute function public.loyalty_order_status_trigger();

create or replace function public.admin_loyalty_seasons()
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'starts_on',s.starts_on,'ends_on',s.ends_on,'status',s.status,'created_at',s.created_at,'closed_at',s.closed_at,'points',coalesce(e.points,0),'customers',coalesce(e.customers,0),'credit',coalesce(e.credit,0)) order by s.created_at desc)
 from public.loyalty_seasons s left join lateral (select sum(case when not reversed then points_delta else 0 end)::integer points,count(distinct customer_id) filter(where not reversed) customers,coalesce(sum(case when not reversed then points_delta else 0 end),0)::numeric credit from public.loyalty_events where season_id=s.id) e on true),'[]'::jsonb);
end $$;
grant execute on function public.admin_loyalty_seasons() to authenticated;

create or replace function public.admin_create_loyalty_season(p_name text,p_start date,p_end date)
returns uuid language plpgsql security definer set search_path=public as $$ declare v uuid;
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 if nullif(trim(p_name),'') is null or p_start is null or p_end<p_start then raise exception 'INVALID_SEASON'; end if;
 insert into public.loyalty_seasons(name,starts_on,ends_on) values(trim(p_name),p_start,p_end) returning id into v; return v;
end $$;
grant execute on function public.admin_create_loyalty_season(text,date,date) to authenticated;

create or replace function public.admin_activate_loyalty_season(p_season_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 if not exists(select 1 from public.loyalty_seasons where id=p_season_id and status='draft' and current_date between starts_on and ends_on) then raise exception 'SEASON_NOT_STARTABLE'; end if;
 if exists(select 1 from public.loyalty_seasons where status='active') then raise exception 'ACTIVE_SEASON_EXISTS'; end if;
 update public.loyalty_seasons set status='active' where id=p_season_id;
end $$;
grant execute on function public.admin_activate_loyalty_season(uuid) to authenticated;

create or replace function public.admin_close_loyalty_season(p_season_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare s public.loyalty_seasons%rowtype; x record; v_points integer; v_credit numeric; v_count integer:=0;
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 select * into s from public.loyalty_seasons where id=p_season_id for update;
 if not found or s.status<>'active' or current_date<=s.ends_on then raise exception 'SEASON_NOT_CLOSABLE'; end if;
 for x in select customer_id,sum(points_delta)::integer n from public.loyalty_events where season_id=s.id and reversed=false group by customer_id having sum(points_delta)>0 loop
   v_points:=least(x.n,(select points from public.profiles where id=x.customer_id));
   if v_points>0 then
     v_credit:=v_points::numeric;
     update public.profiles set points=points-v_points,balance=balance+v_credit,updated_at=now() where id=x.customer_id;
     insert into public.wallet_transactions(customer_id,amount,type,description,reference_type,reference_id)
       values(x.customer_id,v_credit,'loyalty_credit','BLNK season points converted to purchase credit','loyalty_season',s.id::text);
     insert into public.loyalty_settlements(season_id,customer_id,points,credit_amount) values(s.id,x.customer_id,v_points,v_credit);
     v_count:=v_count+1;
   end if;
 end loop;
 update public.loyalty_seasons set status='closed',closed_at=now() where id=s.id;
 return jsonb_build_object('settled_customers',v_count);
end $$;
grant execute on function public.admin_close_loyalty_season(uuid) to authenticated;

-- New in-store sales accrue points into the currently open season only.
create or replace function public.pos_checkout(p_customer_id uuid,p_items jsonb,p_discount numeric default 0,p_payment_method text default 'cash')
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_invoice uuid:=gen_random_uuid(); v_number text:='BLNK-'||to_char(now(),'YYYYMMDD-HH24MISS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,4)); v_sub numeric:=0; v_total numeric; x jsonb; v_stock integer; v_points integer:=0;
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 if p_items is null or jsonb_array_length(p_items)=0 then raise exception 'EMPTY_CART'; end if;
 for x in select * from jsonb_array_elements(p_items) loop
  if (x->>'qty')::integer<1 or (x->>'price')::numeric<0 then raise exception 'INVALID_ITEM'; end if;
  select stock into v_stock from public.inventory where product_id=x->>'id' for update;
  if v_stock is null then raise exception 'INVENTORY_NOT_SYNCED: %',x->>'name'; end if;
  if v_stock<(x->>'qty')::integer then raise exception 'OUT_OF_STOCK: %',x->>'name'; end if;
  v_sub:=v_sub+(x->>'price')::numeric*(x->>'qty')::integer;
 end loop;
 v_total:=greatest(0,v_sub-greatest(0,coalesce(p_discount,0)));
 if p_payment_method='wallet' then
  update public.profiles set balance=balance-v_total,updated_at=now() where id=p_customer_id and balance>=v_total;
  if not found then raise exception 'INSUFFICIENT_BALANCE'; end if;
 end if;
 insert into public.invoices(id,invoice_number,customer_id,pos_reference,subtotal,discount,total,payment_method,store) values(v_invoice,v_number,p_customer_id,'POS-'||v_invoice,v_sub,greatest(0,coalesce(p_discount,0)),v_total,p_payment_method,'BLNK');
 for x in select * from jsonb_array_elements(p_items) loop
  insert into public.invoice_items(invoice_id,product_id,product_name,size,color,quantity,unit_price) values(v_invoice,x->>'id',x->>'name',x->>'size',x->>'color',(x->>'qty')::integer,(x->>'price')::numeric);
  update public.inventory set stock=stock-(x->>'qty')::integer,updated_at=now() where product_id=x->>'id';
  insert into public.inventory_movements(product_id,quantity,movement_type,reference_id) values(x->>'id',-(x->>'qty')::integer,'sale',v_invoice::text);
 end loop;
 if p_payment_method='wallet' then insert into public.wallet_transactions(customer_id,amount,type,description,reference_type,reference_id) values(p_customer_id,-v_total,'purchase','BLNK POS purchase','invoice',v_invoice::text); end if;
 v_points:=public.loyalty_award(p_customer_id,'invoice',v_invoice::text,v_total);
 return jsonb_build_object('invoice_id',v_invoice,'invoice_number',v_number,'total',v_total,'points_earned',v_points);
end $$;
revoke all on function public.pos_checkout(uuid,jsonb,numeric,text) from public;
grant execute on function public.pos_checkout(uuid,jsonb,numeric,text) to authenticated;
