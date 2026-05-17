# Supabase Auth Email Templates (RU)

Templates for the three system emails Supabase Auth sends. Default
templates are in English — these are Russian replacements.

## How to apply

Open Supabase Dashboard → Authentication → Email Templates and paste
the contents of each `.html` file into the matching slot:

| File | Supabase template slot |
|---|---|
| `confirm-signup.ru.html` | Confirm signup |
| `reset-password.ru.html` | Reset password |
| `magic-link.ru.html` | Magic Link |
| `change-email.ru.html` | Change Email Address |

Supabase auto-populates `{{ .ConfirmationURL }}`, `{{ .Token }}`,
`{{ .Email }}` — they're already in the templates.

Subject lines (set per-template in the Dashboard):
- Confirm: "Подтвердите регистрацию в Sportify"
- Reset: "Сброс пароля Sportify"
- Magic Link: "Вход в Sportify"
- Change Email: "Подтвердите новый email"
