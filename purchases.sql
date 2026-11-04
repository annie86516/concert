create table if not exists public.ticket_purchases (
 id uuid primary key default gen_random_uuid(), room_code text not null,
 data jsonb not null, created_at timestamptz not null default now(), deleted_at timestamptz
);
alter table public.ticket_purchases enable row level security;
do $$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.ticket_purchases'::regclass and conname='ticket_purchases_required_fields') then
  alter table public.ticket_purchases add constraint ticket_purchases_required_fields check (coalesce(data->>'recipient','')<>'' and coalesce(data->>'currency','') in ('TWD','JPY'));
 end if;
end $$;
create index if not exists ticket_purchases_room_idx on public.ticket_purchases(room_code);
create or replace function public.get_ticket_purchases(p_code text,p_pin text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
 perform public.get_ticket_room(p_code,p_pin);
 return coalesce((select jsonb_agg(jsonb_build_object('id',id,'data',data,'createdAt',created_at) order by created_at desc) from public.ticket_purchases where room_code=upper(p_code) and deleted_at is null),'[]'::jsonb);
end $$;
create or replace function public.save_ticket_purchase(p_code text,p_pin text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare r jsonb; item_id uuid;
begin
 r:=public.get_ticket_room(p_code,p_pin);
 if not ((r->'room'->'members') ? (p_payload->>'recipient')) then raise exception '請選擇群組成員'; end if;
 if coalesce(length(p_payload->>'title'),0) not between 1 and 80 or coalesce(length(p_payload->>'note'),0)>500 then raise exception '請檢查品名與備註'; end if;
 if (p_payload->>'currency') not in ('TWD','JPY') or coalesce((p_payload->>'amount')::numeric,0)<=0 or (p_payload->>'amount')::numeric>99999999 or (p_payload->>'amount')::numeric<>round((p_payload->>'amount')::numeric,2) then raise exception '金額須大於零，最多兩位小數'; end if;
 if coalesce(length(p_payload->>'image'),0)>1600000 or coalesce(p_payload->>'image','') !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$' then raise exception '請提供有效且不超過大小限制的圖片'; end if;
 item_id:=nullif(p_payload->>'id','')::uuid;
 if item_id is null then insert into public.ticket_purchases(room_code,data) values(upper(p_code),p_payload-'id');
 else update public.ticket_purchases set data=p_payload-'id' where id=item_id and room_code=upper(p_code) and deleted_at is null; if not found then raise exception '紀錄已不存在，請重新整理'; end if; end if;
 return public.get_ticket_purchases(p_code,p_pin);
end $$;
create or replace function public.delete_ticket_purchase(p_code text,p_pin text,p_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
 perform public.get_ticket_room(p_code,p_pin);
 update public.ticket_purchases set deleted_at=now() where id=p_id and room_code=upper(p_code) and deleted_at is null;
 return public.get_ticket_purchases(p_code,p_pin);
end $$;
revoke all on public.ticket_purchases from anon,authenticated;
revoke all on function public.get_ticket_purchases(text,text),public.save_ticket_purchase(text,text,jsonb),public.delete_ticket_purchase(text,text,uuid) from public;
grant execute on function public.get_ticket_purchases(text,text),public.save_ticket_purchase(text,text,jsonb),public.delete_ticket_purchase(text,text,uuid) to anon,authenticated;
notify pgrst,'reload schema';
