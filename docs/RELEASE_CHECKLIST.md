# Release Checklist

Что нужно сделать перед публикацией Sportify в App Store / Google Play / RuStore.

Поддерживается в `main`. По мере выполнения переключай `[ ]` → `[x]`,
оставляй один-два слова комментарием рядом если нужно.

> Актуально на: 2026-05-17 (заведён в commit 1c8d308)

---

## 1. Юридическое лицо и контакты

- [ ] **Оформить статус** — ИП / самозанятость / ООО. Получить ИНН/ОГРНИП.
- [ ] **Завести support-email** на собственном домене (`support@sportify.app`
      или аналог) — через Yandex 360 / Google Workspace / VK WorkSpace.
- [ ] **Купить домен** `sportify.app` или альтернативный (можно отложить
      если не критично — GitHub Pages работает с поддоменом
      `adv1ceeeeee.github.io`).

## 2. Юридические документы

Файлы готовы в [legal/](../legal/) с placeholders.

- [ ] **Подставить значения** одним PowerShell-скриптом из
      [legal/README.md](../legal/README.md):
      `{{PUBLISHER_NAME}}`, `{{PUBLISHER_TAX_ID}}`, `{{CONTACT_EMAIL}}`,
      `{{GITHUB_PAGES_DOMAIN}}`.
- [ ] То же — в [releases/store-listing/*.md](../releases/store-listing/)
      (политика и контакты копируются в описание сторов).
- [ ] **Включить GitHub Pages** — Settings → Pages → Source: Deploy from
      a branch / `main` / `/(root)`.
- [ ] **Проверить открываются** все четыре URL:
      - `/legal/privacy/` (RU)
      - `/legal/privacy-en/` (EN)
      - `/legal/terms/` (RU)
      - `/legal/terms-en/` (EN)
- [ ] **Дать юристу** на быстрый ревью (особенно дисклеймер о здоровье
      и пункт об ограничении ответственности).

## 3. Email-шаблоны Supabase Auth

Файлы в [supabase/email-templates/](../supabase/email-templates/).

- [ ] Скопировать **Confirm signup** в Supabase Dashboard → Authentication
      → Email Templates → Confirm signup.
- [ ] То же для **Reset password**, **Magic link**, **Change email**.
- [ ] Поправить **subject lines** для каждого (см. README).
- [ ] Подставить `{{CONTACT_EMAIL}}` внутри HTML перед загрузкой.

## 4. Скриншоты для маркетплейсов

План в [releases/store-listing/screenshots.md](../releases/store-listing/screenshots.md).

- [ ] Снять **8 кадров** с тестового аккаунта (Главная / Сессия /
      Аналитика / Программа / Календарь / Тело / Профиль / Инсайты).
- [ ] Прогнать через Figma-шаблон с маркетинговыми заголовками.
- [ ] Размеры:
      - App Store 6.7" — 1290 × 2796
      - Google Play phone — минимум 1080 × 1920
      - RuStore — 1080 × 1920
- [ ] Залить в облако (Drive / Я.Диск), ссылку в
      `releases/store-listing/screenshots-location.local.md`.

## 5. App Store / Google Play / RuStore аккаунты

- [ ] **Apple Developer Program** — оплатить $99/год.
- [ ] **Google Play Console** — оплатить $25 единоразово.
- [ ] **RuStore Console** — бесплатно, регистрация через Госуслуги.
- [ ] **Заполнить карточку** в каждом сторе — копи-паст из
      [releases/store-listing/](../releases/store-listing/).
- [ ] **App Privacy / Data Safety form** в каждом сторе:
      - App Store Privacy Nutrition Label — список из `appstore.*.md`
      - Google Play Data Safety — список из `googleplay.ru.md`

## 6. Sign in with Apple (если будут другие провайдеры)

Apple **обязывает** иметь Sign in with Apple на iOS, если есть Google/Email/Facebook sign-in.
В нашем случае email-only сейчас, так что технически не обязательно.

- [ ] Если решим добавлять Google Sign-In → **обязательно** добавить и Apple.
- [ ] Иначе пропускаем (текущий email-only флоу проходит ревью).

## 7. Push-уведомления (FCM)

Сейчас отключены — `firebase_messaging` убран из pubspec ради быстрых Windows-сборок.

- [ ] **Вернуть зависимости** в [pubspec.yaml](../pubspec.yaml):
      `firebase_core`, `firebase_messaging`.
- [ ] Запустить `flutterfire configure` — сгенерирует `firebase_options.dart`.
- [ ] **Раскомментировать `_initFcm()`** в [main.dart](../lib/main.dart).
- [ ] Положить `google-services.json` и `GoogleService-Info.plist` (через
      Firebase Console).
- [ ] **Apple Push Certificates** (APNs Key .p8 → Firebase).
- [ ] Тест: отправить push через Supabase Edge Function или Firebase Cloud
      Messaging Console.

## 8. TestFlight + RuStore beta

- [ ] **TestFlight** — собрать `flutter build ipa --release`, загрузить
      через Transporter, добавить тестеров (коллеги-разработчики).
- [ ] **RuStore Внутреннее тестирование** — аналог TestFlight.
- [ ] **Google Play Closed testing** — для Android-бета.
- [ ] Собрать **первый фидбек** от 3-5 живых юзеров перед публичным релизом.

## 9. Code — небольшие правки перед релизом

- [ ] **Sentry Performance** — проверить что `tracesSampleRate: 0.2` уже
      работает в [main.dart](../lib/main.dart) (он там есть).
- [ ] **Onboarding funnel view** в Supabase — SQL-вью что показывает
      «сколько юзеров дошло до каждого шага onboarding». События уже
      логируются через `EventLogger.onboardingCompleted/Skipped` +
      auto `screen_view`. Нужен `CREATE VIEW onboarding_funnel AS …`.
- [ ] **Min-version gating** — проверить что `app_config.min_version`
      выставлен (видимо уже работает через `VersionService`).
- [ ] Запустить `flutter analyze` — должно быть 0 errors / warnings
      (info — допустимы).
- [ ] Запустить `flutter test` — должно быть green.
- [ ] **Удалить `console.print`/`debugPrint`-следы** (если есть) перед
      production-build.

## 10. Production env vars

- [ ] **Supabase prod-проект** отдельный от dev (если ещё не).
- [ ] **SENTRY_DSN** — boundary к production-проекту в Sentry.
- [ ] **Application signing** Android — ключ в безопасном месте
      (см. `docs/KEYSTORE_INFO.local.md`).
- [ ] **iOS signing** — Distribution certificate в Apple Developer Console.

## 11. Опциональные / Post-MVP

Перенесены в [docs/BACKLOG.md](BACKLOG.md):
- Apple Health / Google Health Connect синхронизация
- 1RM / MEV / MAV / MRV научные расчёты
- Pro-подписка через RevenueCat
- Социальные фичи, тренер, лидерборды
- Wear OS / Apple Watch companion

---

## Когда чек-лист закроется на 90%+

🚀 Можно подавать в сторы. Ревью занимает:
- **App Store** — 1-3 дня (иногда дольше с medical disclaimer)
- **Google Play** — несколько часов (новые аккаунты могут идти 7+ дней)
- **RuStore** — 1-2 дня

После approve → нажать **Release** в каждом сторе → готово.
