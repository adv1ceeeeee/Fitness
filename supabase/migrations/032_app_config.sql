-- Таблица конфигурации приложения (min_version и другие remote-флаги).
-- Доступна на чтение всем без авторизации.

create table if not exists app_config (
  key   text primary key,
  value text not null
);

alter table app_config enable row level security;

-- Читать могут все (в т.ч. анонимные пользователи)
drop policy if exists "app_config readable by all" on app_config;
create policy "app_config readable by all" on app_config
  for select using (true);

-- Писать может только сервис-роль (администратор)
-- (нет политики на insert/update — значит запрещено для anon/authenticated)

-- Начальные значения
insert into app_config (key, value)
values
  ('min_version', '1.0.0'),
  ('store_url_android', 'https://play.google.com/store/apps/details?id=com.sportwai.app'),
  ('store_url_ios', 'https://apps.apple.com/app/sportwai/id000000000')
on conflict (key) do nothing;
