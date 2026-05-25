-- invoke_edge_function: INTERNAL_CRON_JWT (= service_role JWT) 사용
-- SUPABASE_SERVICE_ROLE_KEY 가 platform reserved secret 으로 교체 불가하므로
-- 별도 INTERNAL_CRON_JWT secret + auth.ts requireCronSecret 체계로 분리.

create or replace function public.invoke_edge_function(
  fn_name text,
  body jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
as $$
declare
  invoke_url   constant text := 'https://bsjdgwmveokanclqwtvx.supabase.co/functions/v1';
  -- auth.ts requireCronSecret 이 INTERNAL_CRON_JWT env var 와 비교함
  cron_jwt     constant text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJzamRnd212ZW9rYW5jbHF3dHZ4Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3OTQxODk5NiwiZXhwIjoyMDk0OTk0OTk2fQ.HQfmphQbkU-pzSVHt3OeePoWIN91Y-KDV2syGJ0oRjI';
  request_id   bigint;
begin
  select net.http_post(
    url     := invoke_url || '/' || fn_name,
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || cron_jwt
    ),
    body    := body
  ) into request_id;
  return request_id;
end;
$$;
