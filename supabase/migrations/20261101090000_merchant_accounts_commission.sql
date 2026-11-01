-- BLNK merchant accounts, branches, direct payment channels and 2.5% retail commission
create table if not exists public.merchant_accounts (
 id uuid primary key default gen_random_uuid(),
 owner_user_id uuid not null unique references auth.users(id) on delete cascade,
 legal_name text not null,
 contact_name text,
 phone text,
 status text not null default 'active' check(status in ('active','restricted','suspended')),
 commission_rate numeric(6,5) not null default 0.025 check(commission_rate >= 0 and commission_rate <= 0.25),
 late_fee_rate numeric(6,5) not null default 0 check(late_fee_rate >= 0 and late_fee_rate <= 0.25),
 grace_days integer not null default 3 check(grace_days between 0 and 30),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.merchant_members (
 id uuid primary key default gen_random_uuid(),
 merchant_id uuid not null references public.merchant_accounts(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 role text not null default 'staff' check(role in ('owner','manager','staff')),
 created_at timestamptz not null default now(),
 unique(merchant_id,user_id)
);
create table if not exists public.merchant_branches (
 id uuid primary key default gen_random_uuid(),
 merchant_id uuid not null references public.merchant_accounts(id) on delete cascade,
 branch_name text not null,
 address text,
 phone text,
 is_active boolean not null default true,
 created_at timestamptz not null default now()
);
create table if not exists public.merchant_payment_channels (
 id uuid primary key default gen_random_uuid(),
 merchant_id uuid not null references public.merchant_accounts(id) on delete cascade,
 branch_id uuid references public.merchant_branches(id) on delete cascade,
 channel_type text not null check(channel_type in ('wallet','instapay','cash_on_delivery','bank_transfer','cash','other')),
 label text not null,
 account_details text,
 instructions text,
 is_active boolean not null default true,
 created_at timestamptz not null default now()
);
create table if not exists public.merchant_sales (
 id uuid primary key default gen_random_uuid(),
 merchant_id uuid not null references public.merchant_accounts(id),
 branch_id uuid references public.merchant_branches(id),
 payment_channel_id uuid references public.merchant_payment_channels(id),
 sale_number text not null,
 external_reference text,
 seller_user_id uuid references auth.users(id),
 buyer_name text,
 buyer_phone text,
 buyer_address text,
 items jsonb not null default '[]'::jsonb,
 subtotal numeric(12,2) not null check(subtotal >= 0),
 discount numeric(12,2) not null default 0 check(discount >= 0),
 total numeric(12,2) not null check(total >= 0),
 commission_rate numeric(6,5) not null default 0.025,
 commission_amount numeric(12,2) not null,
 status text not null default 'completed' check(status in ('completed','cancelled','refunded')),
 payment_status text not null default 'unverified' check(payment_status in ('unverified','paid','cod_pending','refunded')),
 created_at timestamptz not null default now(),
 unique(merchant_id,sale_number),
 unique(merchant_id,external_reference)
);
create table if not exists public.merchant_statements (
 id uuid primary key default gen_random_uuid(),
 merchant_id uuid not null references public.merchant_accounts(id),
 period_start date not null,
 period_end date not null,
 sales_total numeric(12,2) not null default 0,
 commission_total numeric(12,2) not null default 0,
 penalties_total numeric(12,2) not null default 0,
 payments_total numeric(12,2) not null default 0,
 amount_due numeric(12,2) not null default 0,
 due_at timestamptz not null,
 status text not null default 'unpaid' check(status in ('unpaid','partially_paid','paid','overdue')),
 created_at timestamptz not null default now(),
 unique(merchant_id,period_start,period_end)
);
create table if not exists public.merchant_commission_payments (
 id uuid primary key default gen_random_uuid(),
 merchant_id uuid not null references public.merchant_accounts(id),
 statement_id uuid references public.merchant_statements(id),
 amount numeric(12,2) not null check(amount > 0),
 method text not null,
 reference text,
 proof_url text,
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 reviewed_by uuid references auth.users(id),
 reviewed_at timestamptz,
 created_at timestamptz not null default now()
);
create table if not exists public.merchant_penalties (
 id uuid primary key default gen_random_uuid(),
 merchant_id uuid not null references public.merchant_accounts(id),
 statement_id uuid references public.merchant_statements(id),
 amount numeric(12,2) not null check(amount >= 0),
 reason text not null,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now()
);

create index if not exists merchant_sales_period_idx on public.merchant_sales(merchant_id,created_at);
create index if not exists merchant_statements_due_idx on public.merchant_statements(merchant_id,due_at,status);
create index if not exists merchant_members_user_idx on public.merchant_members(user_id,merchant_id);
alter table public.merchant_accounts enable row level security;
alter table public.merchant_members enable row level security;
alter table public.merchant_branches enable row level security;
alter table public.merchant_payment_channels enable row level security;
alter table public.merchant_sales enable row level security;
alter table public.merchant_statements enable row level security;
alter table public.merchant_commission_payments enable row level security;
alter table public.merchant_penalties enable row level security;
revoke all on public.merchant_accounts,public.merchant_members,public.merchant_branches,public.merchant_payment_channels,public.merchant_sales,public.merchant_statements,public.merchant_commission_payments,public.merchant_penalties from anon,authenticated;

create or replace function public.current_merchant_id()
returns uuid language sql stable security definer set search_path=public as $$
 select merchant_id from public.merchant_members where user_id=auth.uid() order by case role when 'owner' then 0 when 'manager' then 1 else 2 end limit 1
$$;
grant execute on function public.current_merchant_id() to authenticated;

create or replace function public.merchant_create_account(p_legal_name text,p_contact_name text,p_phone text,p_branch_name text,p_address text)
returns uuid language plpgsql security definer set search_path=public as $$
declare mid uuid; bid uuid;
begin
 if auth.uid() is null then raise exception 'LOGIN_REQUIRED'; end if;
 if exists(select 1 from public.merchant_members where user_id=auth.uid()) then raise exception 'MERCHANT_ALREADY_EXISTS'; end if;
 if nullif(trim(p_legal_name),'') is null or nullif(trim(p_branch_name),'') is null then raise exception 'REQUIRED_FIELDS'; end if;
 insert into public.merchant_accounts(owner_user_id,legal_name,contact_name,phone) values(auth.uid(),trim(p_legal_name),nullif(trim(p_contact_name),''),nullif(trim(p_phone),'')) returning id into mid;
 insert into public.merchant_members(merchant_id,user_id,role) values(mid,auth.uid(),'owner');
 insert into public.merchant_branches(merchant_id,branch_name,address) values(mid,trim(p_branch_name),nullif(trim(p_address),'')) returning id into bid;
 return mid;
end $$;
grant execute on function public.merchant_create_account(text,text,text,text,text) to authenticated;

create or replace function public.merchant_add_branch(p_branch_name text,p_address text,p_phone text)
returns uuid language plpgsql security definer set search_path=public as $$
declare mid uuid; bid uuid;
begin
 mid:=public.current_merchant_id();
 if mid is null or not exists(select 1 from public.merchant_members where merchant_id=mid and user_id=auth.uid() and role in ('owner','manager')) then raise exception 'FORBIDDEN'; end if;
 insert into public.merchant_branches(merchant_id,branch_name,address,phone) values(mid,trim(p_branch_name),nullif(trim(p_address),''),nullif(trim(p_phone),'')) returning id into bid;
 return bid;
end $$;
grant execute on function public.merchant_add_branch(text,text,text) to authenticated;

create or replace function public.merchant_add_payment_channel(p_branch_id uuid,p_channel_type text,p_label text,p_account_details text,p_instructions text)
returns uuid language plpgsql security definer set search_path=public as $$
declare mid uuid; cid uuid;
begin
 mid:=public.current_merchant_id();
 if mid is null or not exists(select 1 from public.merchant_members where merchant_id=mid and user_id=auth.uid() and role in ('owner','manager')) then raise exception 'FORBIDDEN'; end if;
 if p_branch_id is not null and not exists(select 1 from public.merchant_branches where id=p_branch_id and merchant_id=mid) then raise exception 'BRANCH_NOT_FOUND'; end if;
 insert into public.merchant_payment_channels(merchant_id,branch_id,channel_type,label,account_details,instructions)
 values(mid,p_branch_id,p_channel_type,trim(p_label),nullif(trim(p_account_details),''),nullif(trim(p_instructions),'')) returning id into cid;
 return cid;
end $$;
grant execute on function public.merchant_add_payment_channel(uuid,text,text,text,text) to authenticated;

create or replace function public.merchant_record_sale(
 p_branch_id uuid,p_payment_channel_id uuid,p_sale_number text,p_external_reference text,
 p_buyer_name text,p_buyer_phone text,p_buyer_address text,p_items jsonb,
 p_subtotal numeric,p_discount numeric,p_total numeric,p_payment_status text default 'unverified'
) returns jsonb language plpgsql security definer set search_path=public as $$
declare mid uuid; rate numeric; sid uuid; commission numeric;
begin
 mid:=public.current_merchant_id();
 if mid is null then raise exception 'MERCHANT_NOT_LINKED'; end if;
 if not exists(select 1 from public.merchant_branches where id=p_branch_id and merchant_id=mid and is_active) then raise exception 'INVALID_BRANCH'; end if;
 if p_payment_channel_id is not null and not exists(select 1 from public.merchant_payment_channels where id=p_payment_channel_id and merchant_id=mid and is_active) then raise exception 'INVALID_PAYMENT_CHANNEL'; end if;
 if p_subtotal<0 or p_discount<0 or p_total<0 or p_total>p_subtotal then raise exception 'INVALID_TOTALS'; end if;
 if p_payment_status not in ('unverified','paid','cod_pending') then raise exception 'INVALID_PAYMENT_STATUS'; end if;
 select commission_rate into rate from public.merchant_accounts where id=mid and status='active';
 if rate is null then raise exception 'MERCHANT_ACCOUNT_RESTRICTED'; end if;
 commission:=round(p_total*rate,2);
 insert into public.merchant_sales(merchant_id,branch_id,payment_channel_id,sale_number,external_reference,seller_user_id,buyer_name,buyer_phone,buyer_address,items,subtotal,discount,total,commission_rate,commission_amount,payment_status)
 values(mid,p_branch_id,p_payment_channel_id,trim(p_sale_number),nullif(trim(p_external_reference),''),auth.uid(),nullif(trim(p_buyer_name),''),nullif(trim(p_buyer_phone),''),nullif(trim(p_buyer_address),''),coalesce(p_items,'[]'::jsonb),p_subtotal,p_discount,p_total,rate,commission,p_payment_status)
 returning id into sid;
 return jsonb_build_object('sale_id',sid,'commission_rate',rate,'commission_amount',commission);
end $$;
grant execute on function public.merchant_record_sale(uuid,uuid,text,text,text,text,text,jsonb,numeric,numeric,numeric,text) to authenticated;

create or replace function public.merchant_dashboard()
returns jsonb language plpgsql security definer set search_path=public as $$
declare mid uuid; r jsonb;
begin
 mid:=public.current_merchant_id(); if mid is null then return jsonb_build_object('has_account',false); end if;
 select jsonb_build_object(
  'has_account',true,'merchant',to_jsonb(m),
  'branches',coalesce((select jsonb_agg(to_jsonb(b) order by b.created_at) from public.merchant_branches b where b.merchant_id=mid),'[]'::jsonb),
  'channels',coalesce((select jsonb_agg(to_jsonb(c) order by c.created_at desc) from public.merchant_payment_channels c where c.merchant_id=mid),'[]'::jsonb),
  'sales',coalesce((select jsonb_agg(to_jsonb(s) order by s.created_at desc) from (select * from public.merchant_sales where merchant_id=mid order by created_at desc limit 100) s),'[]'::jsonb),
  'statements',coalesce((select jsonb_agg(to_jsonb(st) order by st.period_start desc) from public.merchant_statements st where st.merchant_id=mid),'[]'::jsonb),
  'penalties',coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at desc) from public.merchant_penalties p where p.merchant_id=mid),'[]'::jsonb),
  'payments',coalesce((select jsonb_agg(to_jsonb(cp) order by cp.created_at desc) from public.merchant_commission_payments cp where cp.merchant_id=mid),'[]'::jsonb)
 ) into r from public.merchant_accounts m where m.id=mid;
 return r;
end $$;
grant execute on function public.merchant_dashboard() to authenticated;

create or replace function public.merchant_submit_commission_payment(p_statement_id uuid,p_amount numeric,p_method text,p_reference text,p_proof_url text)
returns uuid language plpgsql security definer set search_path=public as $$
declare mid uuid; pid uuid;
begin
 mid:=public.current_merchant_id();
 if mid is null or p_amount<=0 then raise exception 'INVALID_PAYMENT'; end if;
 if p_statement_id is not null and not exists(select 1 from public.merchant_statements where id=p_statement_id and merchant_id=mid) then raise exception 'INVALID_STATEMENT'; end if;
 insert into public.merchant_commission_payments(merchant_id,statement_id,amount,method,reference,proof_url)
 values(mid,p_statement_id,p_amount,trim(p_method),nullif(trim(p_reference),''),nullif(trim(p_proof_url),'')) returning id into pid;
 return pid;
end $$;
grant execute on function public.merchant_submit_commission_payment(uuid,numeric,text,text,text) to authenticated;

create or replace function public.admin_generate_merchant_statements(p_period_start date,p_period_end date,p_due_days integer default 7)
returns integer language plpgsql security definer set search_path=public as $$
declare n integer;
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 if p_period_end<=p_period_start or p_due_days<0 then raise exception 'INVALID_PERIOD'; end if;
 insert into public.merchant_statements(merchant_id,period_start,period_end,sales_total,commission_total,penalties_total,payments_total,amount_due,due_at)
 select m.id,p_period_start,p_period_end,
 coalesce(sum(s.total) filter(where s.status='completed'),0),
 coalesce(sum(s.commission_amount) filter(where s.status='completed'),0),
 coalesce((select sum(p.amount) from public.merchant_penalties p where p.merchant_id=m.id and p.created_at::date>=p_period_start and p.created_at::date<p_period_end),0),
 0,
 coalesce(sum(s.commission_amount) filter(where s.status='completed'),0)+coalesce((select sum(p.amount) from public.merchant_penalties p where p.merchant_id=m.id and p.created_at::date>=p_period_start and p.created_at::date<p_period_end),0),
 (p_period_end::timestamptz + make_interval(days=>p_due_days))
 from public.merchant_accounts m left join public.merchant_sales s on s.merchant_id=m.id and s.created_at::date>=p_period_start and s.created_at::date<p_period_end
 group by m.id on conflict(merchant_id,period_start,period_end) do nothing;
 get diagnostics n=row_count; return n;
end $$;
grant execute on function public.admin_generate_merchant_statements(date,date,integer) to authenticated;

create or replace function public.admin_review_merchant_payment(p_payment_id uuid,p_status text)
returns void language plpgsql security definer set search_path=public as $$
declare p public.merchant_commission_payments%rowtype;
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 if p_status not in ('approved','rejected') then raise exception 'INVALID_STATUS'; end if;
 update public.merchant_commission_payments set status=p_status,reviewed_by=auth.uid(),reviewed_at=now() where id=p_payment_id returning * into p;
 if p.id is null then raise exception 'PAYMENT_NOT_FOUND'; end if;
 if p_status='approved' and p.statement_id is not null then
  update public.merchant_statements st set payments_total=payments_total+p.amount,amount_due=greatest(0,amount_due-p.amount),
   status=case when greatest(0,amount_due-p.amount)=0 then 'paid' else 'partially_paid' end where st.id=p.statement_id;
 end if;
end $$;
grant execute on function public.admin_review_merchant_payment(uuid,text) to authenticated;

create or replace function public.admin_add_merchant_penalty(p_merchant_id uuid,p_statement_id uuid,p_amount numeric,p_reason text)
returns uuid language plpgsql security definer set search_path=public as $$
declare pid uuid;
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 if p_amount<=0 or nullif(trim(p_reason),'') is null then raise exception 'INVALID_PENALTY'; end if;
 insert into public.merchant_penalties(merchant_id,statement_id,amount,reason,created_by) values(p_merchant_id,p_statement_id,p_amount,trim(p_reason),auth.uid()) returning id into pid;
 if p_statement_id is not null then update public.merchant_statements set penalties_total=penalties_total+p_amount,amount_due=amount_due+p_amount where id=p_statement_id and merchant_id=p_merchant_id; end if;
 return pid;
end $$;
grant execute on function public.admin_add_merchant_penalty(uuid,uuid,numeric,text) to authenticated;

create or replace function public.admin_set_merchant_status(p_merchant_id uuid,p_status text)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 if p_status not in ('active','restricted','suspended') then raise exception 'INVALID_STATUS'; end if;
 update public.merchant_accounts set status=p_status,updated_at=now() where id=p_merchant_id;
end $$;
grant execute on function public.admin_set_merchant_status(uuid,text) to authenticated;

create or replace function public.admin_merchant_overview()
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 return jsonb_build_object(
  'merchants',(select count(*) from public.merchant_accounts),
  'sales',(select count(*) from public.merchant_sales where status='completed'),
  'sales_total',coalesce((select sum(total) from public.merchant_sales where status='completed'),0),
  'commission_total',coalesce((select sum(commission_amount) from public.merchant_sales where status='completed'),0),
  'unpaid',coalesce((select sum(amount_due) from public.merchant_statements where status<>'paid'),0),
  'pending_payments',(select count(*) from public.merchant_commission_payments where status='pending')
 );
end $$;
grant execute on function public.admin_merchant_overview() to authenticated;
