-- The BLNK "Try It On" feature was removed from the customer app.
-- Keep tryon_transactions and wallet_transactions intact for historical accounting.
revoke execute on function public.reserve_tryon(text) from public, anon, authenticated;
revoke execute on function public.complete_tryon(uuid) from public, anon, authenticated;
revoke execute on function public.refund_tryon(uuid) from public, anon, authenticated;
