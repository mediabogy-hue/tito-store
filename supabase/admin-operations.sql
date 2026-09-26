-- BLNK unified admin overview
create or replace function public.admin_operations_overview()
returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb;
begin
 if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
 select jsonb_build_object(
  'pending_topups',(select count(*) from public.balance_topup_requests where status='pending'),
  'open_orders',(select count(*) from public.orders where status not in ('delivered','cancelled')),
  'preparing_orders',(select count(*) from public.orders where status='preparing'),
  'ready_orders',(select count(*) from public.orders where status='ready_to_ship'),
  'sales_today',coalesce((select sum(total) from public.orders where created_at>=date_trunc('day',now()) and status<>'cancelled'),0),
  'orders_today',(select count(*) from public.orders where created_at>=date_trunc('day',now()) and status<>'cancelled')
 ) into r;
 return r;
end $$;
revoke all on function public.admin_operations_overview() from public;
grant execute on function public.admin_operations_overview() to authenticated;
