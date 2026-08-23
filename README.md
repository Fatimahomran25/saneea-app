# 🤝 Saneea (صنيعة)

**A freelance marketplace platform connecting clients and freelancers — with AI-generated contracts, AI-powered freelancer matching, milestone-based escrow payments, and built-in dispute resolution.**

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.10-0175C2?logo=dart&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white)
![Flask](https://img.shields.io/badge/Flask-3.1-000000?logo=flask&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-Auth%20%7C%20Firestore%20%7C%20Storage%20%7C%20FCM-FFCA28?logo=firebase&logoColor=black)
![OpenAI](https://img.shields.io/badge/OpenAI-GPT--5.4-412991?logo=openai&logoColor=white)
![Moyasar](https://img.shields.io/badge/Payments-Moyasar-5A3E9E)
![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android&logoColor=white)
![Status](https://img.shields.io/badge/Status-Active%20Development-yellow)

---

## 📖 Overview & Motivation

Freelance marketplaces routinely fail their users in three places: **trust** (has this freelancer actually delivered good work before?), **money** (is the client's payment safe until the work is actually done?), and **paperwork** (drafting a fair, legally-coherent contract is a barrier most individual freelancers and small clients skip entirely, leaving both sides exposed).

**Saneea** was built to close those three gaps for a Saudi/Gulf freelance market:

- **Trust** — every freelancer profile carries a real rating history, and a full admin moderation layer (general reports, contract disputes, warnings, and account blocking/appeals) backs up bad-actor accountability instead of leaving it to a comment section.
- **Money** — payments are never released in one lump sum. Every contract is split into **three milestones (10% / 40% / 50%)**, each individually paid through the **Moyasar** payment gateway only after the corresponding deliverable is submitted and approved, with the payment order enforced **server-side** (not just in the UI).
- **Paperwork** — instead of asking two non-lawyers to write a freelance agreement from scratch, Saneea generates a full legal-style contract automatically from the request/proposal details using **OpenAI's GPT-5.4** with a strict structured-output schema, then lets both sides digitally sign it (and download a generated PDF).

**Target users:** individual freelancers and clients (companies or individuals) across five service categories — Graphic Design, Marketing, Software Development, Accounting, and Tutoring — who need a safer, more structured alternative to informal DM-based freelance deals.

---

## ✨ Key Features & Functional Highlights

### For Clients
| Feature | Details |
|---|---|
| **Browse & Search** | Category-filtered freelancer discovery (Graphic Designers, Marketing, Software Developers, Accounting, Tutoring), plus a free-text search bar. |
| **AI-Powered Matching** | A dedicated "✨" AI search flow (`RecommendationView`) posts a text description (and optional images) to the backend `/analyze` endpoint, which is designed to run a **CLIP (ResNet-50, OpenAI-pretrained) image/text embedding model** via PyTorch + `open_clip` to score portfolio-image relevance against the request. *(Currently ships with the model path temporarily stubbed out server-side — the endpoint returns a fixed placeholder match score while the full CLIP pipeline is disabled; the implementation is intact in `server.py`, commented out pending re-enablement.)* |
| **Service Requests / Announcements** | Post a public service request that freelancers can respond to, with full CRUD and status tracking. |
| **Contract Workspace** | Approve/disapprove AI-drafted contracts, track milestone progress, review submitted deliverables, and request contract termination (with a free-cancellation grace window and a compensation-based flow afterward). |
| **Milestone Payments** | Pay each of the 3 milestones independently via an embedded Moyasar card form once the corresponding work is approved. |

### For Freelancers
| Feature | Details |
|---|---|
| **Proposals** | Browse open client requests and submit proposals. |
| **Contract Workspace** | Same shared workspace as clients — submit/update deliverables (images, files, links, notes) per milestone, respond to change requests, and track payment status per milestone. |
| **Profile** | Portfolio, service field, working mode, rating, and warning history (admin-facing) tied to the account. |

### Shared / Platform-Wide
| Feature | Details |
|---|---|
| **AI Contract Generation** | `generate_contract_ai()` (backend `ai_service.py`) calls OpenAI with a strict JSON schema (parties, service scope, payment schedule, timeline, custom clauses) to produce a coherent legal-style contract body — including a computed, per-milestone payment-schedule section that always matches the real 10/40/50 split. |
| **Digital Signatures + PDF** | Both parties sign in-app (stored as base64 image data); a server-rendered PDF (ReportLab) is generated on demand once both signatures are present. |
| **Real-time Chat** | Per-contract chat thread, with delivery submission dialogs, milestone status cards, and a read-only "Chat Preview" surfaced to admins during dispute review. |
| **Milestone State Machine** | Each milestone moves through `locked → pending → submitted ⇄ changes_requested → approved → paid`, authoritatively enforced by `/verify-payment` on the backend (a client can't skip ahead or pay out of order even if the UI is bypassed). |
| **Contract Termination** | A free termination window right after signing, and a 20%-of-total compensation flow for later terminations. |
| **Notifications** | Firebase Cloud Messaging push notifications + a parallel Firestore-backed in-app notification feed (`users/{uid}/notifications`) that live-updates a bell badge and shows foreground banners without needing a push permission grant. |
| **Reporting & Admin Moderation** | Two separate report tracks — general user-to-user reports (`general_reports`) and contract-specific dispute reviews (chat-linked, with a read-only chat preview for the admin) — each with their own status lifecycle (`Open/Requested → Under Review → Resolved/Dismissed`). |
| **Warnings & Blocking** | Admins can issue warnings against a report (up to 3, tracked on the user doc) or block an account outright; blocked users can submit a review appeal, which an admin approves (auto-unblocks live, no re-login needed) or rejects. |
| **Favorites** | Clients can bookmark freelancers for later. |

### 🛠 Admin Panel
A dedicated admin web app surface with four sections:
1. **Dashboard** — live counters (Open Reports / Under Review / Contract Reviews / Resolved) driven by Firestore listeners.
2. **General Reports** — review, dismiss, or mark-valid-and-warn user-to-user reports.
3. **Contract Reviews** — investigate contract disputes with full contract + chat context, then mark Under Review / Resolved / Dismissed.
4. **Appeals** — review and approve/reject blocked-account appeals.

---

## 🏗️ System Architecture & Tech Stack

| Layer | Technology |
|---|---|
| **Frontend** | Flutter 3.x / Dart 3.10 — **Android is the actual target platform** (custom app icon and release config are only set up for Android in `pubspec.yaml`). The `ios/`, `web/`, `windows/`, `macos/`, and `linux/` folders are Flutter's default scaffolding from `flutter create` and are used during development (this session's testing was largely done via `flutter run -d chrome` for convenience) but are not configured or intended as shipped platforms. |
| **State Management** | `provider`, plus per-screen `StatefulWidget` + Firestore `StreamBuilder`s for live data |
| **Backend API** | Python 3.12 + Flask 3.1, organized as a `Blueprint` (`contract_routes`) registered onto the main Flask app (`server.py`) |
| **Database** | Cloud Firestore (NoSQL, real-time listeners throughout) |
| **Auth** | Firebase Authentication (National ID–based login, mapped internally to a synthetic email) |
| **File Storage** | Firebase Storage (portfolio images, delivery attachments, profile photos) |
| **Serverless Functions** | Firebase Cloud Functions (Node 20) — `sendChatNotification`, `sendRequestNotification` |
| **AI — Contract Drafting** | OpenAI API, model `gpt-5.4`, JSON-schema-constrained structured output |
| **AI — Portfolio Matching** | PyTorch + `open_clip` (CLIP `RN50`, OpenAI pretrained weights) for text↔image semantic similarity *(currently disabled in production, code retained)* |
| **Payments** | Moyasar (Saudi payment gateway) — native `moyasar` Flutter SDK on mobile, a custom `WebMoyasarCardForm` widget on Flutter Web |
| **PDF Generation** | ReportLab (server-side contract PDF rendering) |
| **Push Notifications** | Firebase Cloud Messaging |
| **Admin Auth/Access** | Firestore `accountType` field (`client` / `freelancer` / `admin`) + a `isBlocked` account-gate enforced app-wide via a `_BlockedUserGate` wrapper around the entire navigator |

---

## 📁 Project Structure

```
saneea-New/
├── lib/                              # Flutter application source
│   ├── main.dart                     # App entrypoint, routing table, auth-state bootstrap,
│   │                                  # and the app-wide _BlockedUserGate
│   ├── config/
│   │   └── api_config.dart           # Backend base URL resolution
│   ├── controlles/                   # Business-logic controllers (one per feature area)
│   │   ├── account_access_service.dart
│   │   ├── admin_reports_controller.dart
│   │   ├── chat_controller.dart
│   │   ├── contracts_controller.dart
│   │   ├── recommendation_controller.dart
│   │   ├── request_notifications_controller.dart
│   │   └── ...
│   ├── models/                       # Typed data models (contract, chat, profile, etc.)
│   ├── views/                        # ~40 screens: client/freelancer home, chat, contracts,
│   │                                  # profiles, admin_* screens, blocked_account_view, etc.
│   └── widgets/
│       └── web_moyasar_card_form.dart  # Custom Moyasar checkout UI for Flutter Web
│
├── backend/                          # Flask API server
│   ├── server.py                     # Flask app entry, CORS, /analyze (AI matching) endpoint
│   ├── contract_routes.py            # Blueprint: all /generate-contract, /approve-contract,
│   │                                  # /verify-payment, /update-contract, etc. routes
│   ├── contract_controller.py        # Contract lifecycle logic, milestone construction
│   ├── contract_service.py           # Contract text rendering (template + AI prose)
│   ├── ai_service.py                 # OpenAI-backed generate_contract_ai()
│   ├── pdf_service.py                # ReportLab-based contract PDF generation
│   ├── firebase_service.py           # Firebase Admin SDK helpers
│   ├── requirements.txt
│   └── .env.example                  # Template for required environment variables
│
├── functions/                        # Firebase Cloud Functions (Node.js)
│   └── index.js                      # sendChatNotification, sendRequestNotification
│
├── android/                           # Primary target platform (custom app icon configured here)
├── ios/ web/ windows/ macos/ linux/   # Default Flutter scaffolding, used for dev/testing only
├── firebase.json                     # Firebase Hosting/Functions/Storage config
├── pubspec.yaml                      # Flutter dependencies
└── README.md
```

---

## 🚀 Installation & Local Setup

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) `>=3.10` with a configured platform toolchain (Chrome for web, Android Studio/Xcode for mobile)
- [Python](https://www.python.org/downloads/) `3.12+`
- A [Firebase](https://console.firebase.google.com/) project (Firestore, Auth, Storage, Cloud Messaging, and a Firebase Admin service account)
- An [OpenAI API key](https://platform.openai.com/api-keys) (for AI contract generation)
- A [Moyasar](https://moyasar.com/) test/live publishable + secret key pair (for payments)

### 1. Clone the repository
```bash
git clone https://github.com/Fatimahomran25/saneea-app.git
cd saneea-app
```

### 2. Set up the Flutter app
```bash
flutter pub get
```

Firebase config (`lib/firebase_options.dart` and platform-specific files like `android/app/google-services.json`) must be generated for **your own** Firebase project via the [FlutterFire CLI](https://firebase.google.com/docs/flutter/setup):
```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

### 3. Set up the backend
```bash
cd backend
pip install -r requirements.txt
cp .env.example .env
```

Edit `backend/.env`:
```env
# Point to your downloaded Firebase Admin service account JSON
FIREBASE_SERVICE_ACCOUNT_PATH=serviceAccountKey.json

# Or inline the whole JSON instead:
# FIREBASE_SERVICE_ACCOUNT_JSON={"type":"service_account", ...}

# Moyasar secret key (server-side payment verification)
MOYASAR_SECRET_KEY=sk_test_xxxxxxxxxxxx

# Required for AI contract generation (not in .env.example — add it)
OPENAI_API_KEY=sk-xxxxxxxxxxxx
```

Place your Firebase Admin service account JSON at `backend/serviceAccountKey.json` (this file is git-ignored — never commit it).

### 4. Run the backend
```bash
python server.py
```
The Flask API starts on `http://127.0.0.1:5001` by default (see `lib/config/api_config.dart` for the base URL the Flutter app expects).

### 5. Run the Flutter app
```bash
# Web
flutter run -d chrome --dart-define=MOYASAR_PUBLISHABLE_KEY=pk_test_xxxxxxxxxxxx

# Or any connected device/emulator
flutter run --dart-define=MOYASAR_PUBLISHABLE_KEY=pk_test_xxxxxxxxxxxx
```

---

## 🔄 CI/CD & Deployment

There is currently **no automated CI/CD pipeline** configured in this repository (no `.github/workflows/`) — builds and deploys are run manually. Adding one is tracked in the [Roadmap](#-roadmap--future-enhancements) below.

**Manual build commands:**
```bash
# Android release APK (primary target platform)
flutter build apk --release

# Flutter Web build (used for local development/testing and admin-panel access)
flutter build web --release
```

**Firebase Hosting deploy** (serves the `web_reset/` directory per `firebase.json`):
```bash
firebase deploy --only hosting
```

**Firebase Cloud Functions deploy:**
```bash
cd functions
npm install
firebase deploy --only functions
```

**Backend API** is a standard Flask app — deployable to any Python-capable host (Cloud Run, a VM, etc.); it is not currently containerized (no `Dockerfile` yet).

---

## 🗺️ Roadmap & Future Enhancements

**Current status: active development / pre-production MVP** — core flows (auth, requests, AI contracts, milestone payments, chat, admin moderation) are implemented and functionally tested; not yet hardened for a public production launch.

- [ ] Re-enable the CLIP-based AI portfolio-matching pipeline in `/analyze` (currently returns a placeholder score)
- [ ] Add automated CI (lint + `flutter analyze` + backend tests on every PR)
- [ ] Containerize the Flask backend (`Dockerfile` + deploy workflow)
- [ ] Formal test coverage for milestone payment order-enforcement and the admin moderation flows
- [ ] Rate limiting / abuse protection on public backend endpoints
- [ ] Expand supported service categories beyond the current five

---

## 👥 Team & Credits

| Name |
|---|
| Fatimah Omran |
| Manar Alrazin |
| Waad Alqahtani |
| Ghala Al Alsheikh |
| Ghaida Alyousef |
| Hessa Alhozaimy |

---

<p align="center">Built with 💜 for a safer freelance economy.</p>
