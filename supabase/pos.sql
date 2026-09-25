-- BLNK POS v1
create or replace function public.pos_checkout(p_customer_id uuid,p_items jsonb,p_discount numeric default 0,p_payment_method text default 'cash')
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_invoice uuid:=gen_random_uuid(); v_number text:='BLNK-'||to_char(now(),'YYYYMMDD-HH24MISS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,4)); v_sub numeric:=0; v_total numeric; x jsonb;
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 if jsonb_array_length(p_items)=0 then raise exception 'EMPTY_CART'; end if;
 for x in select * from jsonb_array_elements(p_items) loop v_sub:=v_sub+(x->>'price')::numeric*(x->>'qty')::integer; end loop;
 v_total:=greatest(0,v_sub-greatest(0,coalesce(p_discount,0)));
 if p_payment_method='wallet' then
  update public.profiles set balance=balance-v_total,updated_at=now() where id=p_customer_id and balance>=v_total;
  if not found then raise exception 'INSUFFICIENT_BALANCE'; end if;
  insert into public.wallet_transactions(customer_id,amount,type,description,reference_type,reference_id) values(p_customer_id,-v_total,'purchase','BLNK POS purchase','invoice',v_invoice::text);
 end if;
 insert into public.invoices(id,invoice_number,customer_id,pos_reference,subtotal,discount,total,payment_method,store) values(v_invoice,v_number,p_customer_id,'POS-'||v_invoice,v_sub,greatest(0,coalesce(p_discount,0)),v_total,p_payment_method,'BLNK');
 for x in select * from jsonb_array_elements(p_items) loop
  insert into public.invoice_items(invoice_id,product_id,product_name,quantity,unit_price) values(v_invoice,x->>'id',x->>'name',(x->>'qty')::integer,(x->>'price')::numeric);
 end loop;
 return jsonb_build_object('invoice_id',v_invoice,'invoice_number',v_number,'total',v_total);
end $$;
revoke all on function public.pos_checkout(uuid,jsonb,numeric,text) from public;
grant execute on function public.pos_checkout(uuid,jsonb,numeric,text) to authenticated;