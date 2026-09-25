-- BLNK Try-On wallet reservation functions
create or replace function public.reserve_tryon(p_product_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_uid uuid:=auth.uid(); v_price numeric(12,2); v_balance numeric(12,2); v_id uuid;
begin
 if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select coalesce((value #>> '{}')::numeric,5) into v_price from public.app_settings where key='tryon_price';
 select balance into v_balance from public.profiles where id=v_uid for update;
 if v_balance is null then raise exception 'PROFILE_NOT_FOUND'; end if;
 if v_balance < v_price then raise exception 'INSUFFICIENT_BALANCE'; end if;
 update public.profiles set balance=balance-v_price,updated_at=now() where id=v_uid;
 insert into public.tryon_transactions(customer_id,product_id,charge,status) values(v_uid,p_product_id,v_price,'reserved') returning id into v_id;
 insert into public.wallet_transactions(customer_id,amount,type,description,reference_type,reference_id)
 values(v_uid,-v_price,'tryon','تجربة المنتج بالذكاء الاصطناعي','tryon',v_id::text);
 return jsonb_build_object('transaction_id',v_id,'charge',v_price,'balance',v_balance-v_price);
end $$;
revoke all on function public.reserve_tryon(text) from public;
grant execute on function public.reserve_tryon(text) to authenticated;

create or replace function public.complete_tryon(p_transaction_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
 update public.tryon_transactions set status='completed'
 where id=p_transaction_id and customer_id=auth.uid() and status='reserved';
end $$;
revoke all on function public.complete_tryon(uuid) from public;
grant execute on function public.complete_tryon(uuid) to authenticated;

create or replace function public.refund_tryon(p_transaction_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v public.tryon_transactions%rowtype;
begin
 select * into v from public.tryon_transactions where id=p_transaction_id and customer_id=auth.uid() for update;
 if v.id is null or v.status<>'reserved' then return; end if;
 update public.tryon_transactions set status='refunded' where id=v.id;
 update public.profiles set balance=balance+v.charge,updated_at=now() where id=v.customer_id;
 insert into public.wallet_transactions(customer_id,amount,type,description,reference_type,reference_id)
 values(v.customer_id,v.charge,'tryon_refund','استرجاع تكلفة تجربة لم تكتمل','tryon',v.id::text);
end $$;
revoke all on function public.refund_tryon(uuid) from public;
grant execute on function public.refund_tryon(uuid) to authenticated;