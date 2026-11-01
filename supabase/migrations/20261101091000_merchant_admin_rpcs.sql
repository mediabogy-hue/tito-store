create or replace function public.admin_merchant_list()
returns table(id uuid,legal_name text,contact_name text,phone text,status text,sales_count bigint,sales_total numeric,commission_total numeric,amount_due numeric)
language sql security definer set search_path=public as $$
 select m.id,m.legal_name,m.contact_name,m.phone,m.status,
 count(s.id) filter(where s.status='completed'),
 coalesce(sum(s.total) filter(where s.status='completed'),0),
 coalesce(sum(s.commission_amount) filter(where s.status='completed'),0),
 coalesce((select sum(st.amount_due) from public.merchant_statements st where st.merchant_id=m.id and st.status<>'paid'),0)
 from public.merchant_accounts m left join public.merchant_sales s on s.merchant_id=m.id
 where public.is_admin() group by m.id order by m.created_at desc
$$;
grant execute on function public.admin_merchant_list() to authenticated;
create or replace function public.admin_pending_merchant_payments()
returns table(id uuid,merchant_id uuid,merchant_name text,statement_id uuid,amount numeric,method text,reference text,proof_url text,created_at timestamptz)
language sql security definer set search_path=public as $$
 select p.id,p.merchant_id,m.legal_name,p.statement_id,p.amount,p.method,p.reference,p.proof_url,p.created_at
 from public.merchant_commission_payments p join public.merchant_accounts m on m.id=p.merchant_id
 where public.is_admin() and p.status='pending' order by p.created_at
$$;
grant execute on function public.admin_pending_merchant_payments() to authenticated;
