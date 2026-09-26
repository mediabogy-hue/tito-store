-- BLNK Balance manual top-up requests
create table if not exists public.balance_topup_requests(
 id uuid primary key default gen_random_uuid(),
 customer_id uuid not null references auth.users(id),
 method text not null check(method in ('instapay','vodafone_cash','orange_cash')),
 destination_number text not null,
 amount numeric(12,2) not null check(amount>0),
 sender_number text not null,
 transaction_reference text not null,
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 created_at timestamptz not null default now(),
 reviewed_at timestamptz
);
alter table public.balance_topup_requests enable row level security;
drop policy if exists "topups self select" on public.balance_topup_requests;
create policy "topups self select" on public.balance_topup_requests for select to authenticated using(customer_id=auth.uid());
create or replace function public.request_balance_topup(p_method text,p_amount numeric,p_sender_number text,p_transaction_reference text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid:=gen_random_uuid(); v_dest text;
begin
 if auth.uid() is null then raise exception 'LOGIN_REQUIRED'; end if;
 if p_method='instapay' then v_dest:='01062292012';
 elsif p_method='vodafone_cash' then v_dest:='01062292012';
 elsif p_method='orange_cash' then
  if p_sender_number like '012%' then v_dest:='01222583477'; else v_dest:='01204107338'; end if;
 else raise exception 'INVALID_METHOD'; end if;
 if p_amount<=0 or trim(p_sender_number)='' or trim(p_transaction_reference)='' then raise exception 'INVALID_REQUEST'; end if;
 insert into public.balance_topup_requests(id,customer_id,method,destination_number,amount,sender_number,transaction_reference)
 values(v_id,auth.uid(),p_method,v_dest,p_amount,trim(p_sender_number),trim(p_transaction_reference));
 return v_id;
end $$;
revoke all on function public.request_balance_topup(text,numeric,text,text) from public;
grant execute on function public.request_balance_topup(text,numeric,text,text) to authenticated;

create or replace function public.admin_topup_requests()
returns table(id uuid,customer_id uuid,customer_name text,phone text,customer_code text,method text,destination_number text,amount numeric,sender_number text,transaction_reference text,status text,created_at timestamptz)
language sql security definer set search_path=public as $$
 select r.id,r.customer_id,p.full_name,p.phone,p.customer_code,r.method,r.destination_number,r.amount,r.sender_number,r.transaction_reference,r.status,r.created_at
 from public.balance_topup_requests r join public.profiles p on p.id=r.customer_id
 where public.is_admin() order by r.created_at desc
$$;
grant execute on function public.admin_topup_requests() to authenticated;

create or replace function public.admin_review_topup(p_request_id uuid,p_action text)
returns void language plpgsql security definer set search_path=public as $$
declare r public.balance_topup_requests%rowtype;
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 select * into r from public.balance_topup_requests where id=p_request_id for update;
 if r.id is null then raise exception 'NOT_FOUND'; end if;
 if r.status<>'pending' then raise exception 'ALREADY_REVIEWED'; end if;
 if p_action='approved' then
  update public.profiles set balance=balance+r.amount,updated_at=now() where id=r.customer_id;
  insert into public.wallet_transactions(customer_id,amount,type,description,reference_type,reference_id)
  values(r.customer_id,r.amount,'topup','BLNK Balance top-up','topup',r.id::text);
 elsif p_action<>'rejected' then raise exception 'INVALID_ACTION';
 end if;
 update public.balance_topup_requests set status=p_action,reviewed_at=now() where id=r.id;
end $$;
revoke all on function public.admin_review_topup(uuid,text) from public;
grant execute on function public.admin_review_topup(uuid,text) to authenticated;
