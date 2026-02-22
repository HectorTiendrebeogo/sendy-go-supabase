-- =========================
-- RPC FUNCTION: Get Active Drivers with Back Route
-- =========================

CREATE OR REPLACE FUNCTION get_active_drivers_with_back_route()
RETURNS TABLE (
  id UUID,
  back_route JSONB
)
SECURITY DEFINER
SET search_path = public, auth 
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    u.id, 
    au.raw_user_meta_data->'back_route'
  FROM public.users u
  JOIN auth.users au ON u.id = au.id
  WHERE u.user_type = 'DRIVER' 
    AND u.is_active = true;
END;
$$;
