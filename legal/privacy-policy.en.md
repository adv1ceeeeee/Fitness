---
layout: default
title: Privacy Policy — Sportify
permalink: /legal/privacy-en/
---

# Sportify Privacy Policy

**Effective date:** January 1, 2026
**Version:** 1.0

This Privacy Policy describes what personal data the **Sportify** mobile application ("the App") collects, controlled by **{{PUBLISHER_NAME}}** (Tax ID **{{PUBLISHER_TAX_ID}}**).

By using the App you confirm you have read and accept this Policy. If you do not agree — do not use the App.

---

## 1. What we collect

### 1.1. Account
- **Email** and **password** (password is stored as a hash and is not visible to us).
- Optional: name, nickname, date of birth, gender, city, phone, profile photo.

### 1.2. Health & fitness data
- **Body measurements:** weight, height, body fat %, circumferences (neck, shoulders, chest, waist, hips, biceps, forearm, thigh, calf).
- **Wellness log:** sleep hours, stress level, energy, muscle soreness.
- **Goal and experience:** your selected training goal and level.

### 1.3. Training data
- Workout programs, exercises, sets (weight, reps, rest, RPE).
- Training schedule and history of completed sessions.
- Personal records (PR).

### 1.4. Device technical data
- Platform (iOS / Android / Windows / macOS / Web).
- Operating system version.
- Device model and manufacturer.
- App version.
- Locale (interface language).
- Vendor-level device identifier (Android ID / IDFV / Windows deviceId) — does **not** contain IMEI, MAC addresses, or advertising identifiers.

### 1.5. Usage analytics
- In-app events: screen views, key button taps, workout completion, settings changes.
- Time in App (foreground duration).

### 1.6. Crashes and errors
- Crash stack traces.
- Device context at the moment of failure.

### 1.7. Push tokens
- Your device's push notification token, used to send workout reminders (if you've granted notification permission).

### 1.8. Content you create
- Program names, session notes, custom exercises, profile photos.

---

## 2. Why we collect this data

| Purpose | Data used | Legal basis |
|---|---|---|
| Registration and sign-in | Email, password | Contract |
| Personalised training recommendations | Goal, level, gender, age, weight, height, history | Consent |
| Showing progress and analytics | Training data, body measurements | Contract |
| Workout reminders | Push token, schedule | Consent |
| User support | Email, device technical data | Legitimate interest |
| Improving the App | Usage analytics, crashes | Legitimate interest |
| Fraud protection | Technical data, IP address | Legitimate interest |

We **do not** use your data for advertising, do not sell it, and do not share it with third parties except as described below.

---

## 3. Who we share data with

| Recipient | What | Where processed | Purpose |
|---|---|---|---|
| **Supabase, Inc.** | Account, profile, workouts, body metrics | EU/US | Backend and database hosting |
| **Sentry** | Crash stack traces, device context | EU/US | Crash monitoring |
| **Apple Push Notification Service** | Push token | USA | Push delivery (iOS) |
| **Firebase Cloud Messaging** (Google) | Push token | USA | Push delivery (Android) — *planned* |
| **App Store / Google Play / RuStore** | Anonymous statistics | USA / RU | Subscription & purchase processing |

All processors have signed Data Processing Agreements (DPAs).

---

## 4. How long we keep data

- **Account** — until you delete it.
- **Training history** — for the lifetime of your account.
- **Analytics logs** — 18 months, then anonymised.
- **Crash logs** — 90 days.
- **Push tokens** — while the device is active (deleted after 90 days of inactivity).

After account deletion we erase all data within **30 calendar days**, except records we are required to keep by law (e.g. payment records — 5 years under Russian Tax Code).

---

## 5. Your rights

Under **Russian Federal Law 152-FZ** and **GDPR**, you have the right to:

1. **Request a copy** of all your data (via Profile → Export data in the App, or by email).
2. **Correct** inaccurate data (via profile settings).
3. **Delete** your account and all data ("Profile → Delete account").
4. **Restrict processing** of certain data categories (disable analytics in settings, withdraw push consent).
5. **Receive data in a machine-readable format** (JSON export).
6. **Lodge a complaint** with Roskomnadzor or your local supervisory authority.

---

## 6. How we protect data

- **Encryption at rest** — all Supabase database data is AES-256 encrypted.
- **Encryption in transit** — all requests use TLS 1.3.
- **Row-Level Security** — at the database level each user sees only their own data.
- **Password hashing** — we never see your password in plaintext (bcrypt).
- **Two-factor authentication** available via email (magic link).

---

## 7. Children

The App is **not intended for children under 14**. If you are a parent and believe your child provided us data, contact us at the address below — we will delete it.

---

## 8. Cookies and tracking

The mobile App does not use cookies. The web version (if available) uses **only functional cookies** to keep your session. No advertising or tracking cookies.

---

## 9. Changes to this policy

We may update this Policy. For material changes we will notify you via the App or by email **at least 30 days** before they take effect. The current version and change history are always available at:

`https://{{GITHUB_PAGES_DOMAIN}}/legal/privacy-en/`

---

## 10. Contact

For any questions about personal data processing:

- **Email:** {{CONTACT_EMAIL}}
- **Operator:** {{PUBLISHER_NAME}}
- **Tax ID:** {{PUBLISHER_TAX_ID}}

We respond to requests within **30 days** (per 152-FZ).
