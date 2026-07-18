-- 旅行分账 V2 同步后端建表脚本
-- 用法：Supabase Dashboard → SQL Editor → 整段粘贴运行一次。
-- 另需手动开一个开关：Dashboard → Authentication → Sign In / Providers → 开启 Anonymous sign-ins。

create table trips (
  id text primary key,
  join_code text unique not null,
  created_at timestamptz default now()
);

create table trip_users (
  trip_id text references trips on delete cascade,
  user_id uuid not null,
  primary key (trip_id, user_id)
);

-- 每行一条同步记录：kind = trip | member | expense | stop | settlement
-- data 是客户端实体原样 JSON，冲突按 updated_at 记录级 LWW（客户端时间戳）
create table records (
  trip_id text references trips on delete cascade,
  id text,
  kind text not null,
  data jsonb not null,
  updated_at timestamptz not null,
  deleted boolean not null default false,
  primary key (trip_id, id)
);

alter table trips enable row level security;
alter table trip_users enable row level security;
alter table records enable row level security;

create policy member_read_trips on trips for select using (
  exists (select 1 from trip_users u where u.trip_id = trips.id and u.user_id = auth.uid()));

create policy own_membership on trip_users for select using (user_id = auth.uid());

create policy member_all_records on records for all
  using (exists (select 1 from trip_users u where u.trip_id = records.trip_id and u.user_id = auth.uid()))
  with check (exists (select 1 from trip_users u where u.trip_id = records.trip_id and u.user_id = auth.uid()));

-- 首次分享：建 trips 行并把调用者加为成员。
-- 行程已存在时仅当调用者已是成员才静默通过——防止拿猜到的 trip_id 绕过邀请码入团。
create or replace function share_trip(p_trip_id text, p_join_code text)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into trips (id, join_code) values (p_trip_id, p_join_code);
  insert into trip_users (trip_id, user_id) values (p_trip_id, auth.uid());
exception when unique_violation then
  if not exists (select 1 from trip_users where trip_id = p_trip_id and user_id = auth.uid()) then
    raise exception 'trip already shared';
  end if;
end $$;

-- 凭邀请码加入，返回 trip_id；码不对返回 null
create or replace function join_trip(p_code text)
returns text language sql security definer set search_path = public as $$
  insert into trip_users (trip_id, user_id)
    select id, auth.uid() from trips where join_code = p_code
    on conflict do nothing;
  select id from trips where join_code = p_code;
$$;

alter publication supabase_realtime add table records;
