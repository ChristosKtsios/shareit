# ShareIt — Architecture

Peer-to-peer marketplace for lending and exchanging items and services within
local communities. Flutter client, serverless Firebase backend.

**Live on Google Play** · [play.google.com/store/apps/details?id=com.ChrisK.shareit](https://play.google.com/store/apps/details?id=com.ChrisK.shareit)

---

## 1. System architecture

How the client, the managed services and the server-side logic fit together.

```mermaid
graph TB
    subgraph client["📱 Flutter Client"]
        UI["Presentation<br/>screens · widgets"]
        STATE["State — Riverpod<br/>providers"]
        REPO["Data — Repositories<br/>models"]
        UI --> STATE --> REPO
    end

    subgraph firebase["☁️ Firebase — managed services"]
        AUTH["Authentication<br/>email · Google · phone OTP"]
        FS[("Cloud Firestore<br/>documents + security rules")]
        ST[("Cloud Storage<br/>images · video")]
        FCM["Cloud Messaging<br/>push"]
        CRASH["Crashlytics<br/>stability"]
    end

    subgraph functions["⚙️ Cloud Functions — trusted server"]
        TRIG["Firestore triggers<br/>onDealUpdate · onReportCreated<br/>onNewMessage · onFriendRequestAccepted"]
        CALL["Callable functions<br/>deleteUserAccount · unfriendUser"]
        CRON["Scheduled jobs<br/>expire listings · complete deals"]
    end

    EXT["🗺️ Google Maps SDK"]

    REPO -->|"sign in"| AUTH
    REPO -->|"read / write<br/>(rules enforced)"| FS
    REPO -->|"upload"| ST
    REPO -->|"invoke"| CALL
    UI --> EXT
    FCM -->|"notification"| UI

    FS -.->|"document events"| TRIG
    TRIG -->|"admin writes"| FS
    TRIG -->|"send"| FCM
    CALL -->|"admin writes"| FS
    CRON --> FS
    UI -.-> CRASH

    style client fill:#e8f0fe,stroke:#4285f4
    style firebase fill:#fff8e1,stroke:#f9ab00
    style functions fill:#e6f4ea,stroke:#34a853
```

**Key decision — why Cloud Functions at all.** Anything a user must not be able
to forge runs server-side with admin privileges: ratings aggregation, friendship
writes, report counters and takedown, account deletion. The client is never
trusted with those, and the security rules deny them outright.

---

## 2. Data model

Firestore is document-based, so this is the logical shape rather than a
relational schema.

```mermaid
erDiagram
    USERS ||--o| PRIVATE : "owns (owner-only)"
    USERS ||--o{ LISTINGS : creates
    USERS ||--o{ USERPOSTS : authors
    USERS }o--o{ CHATS : "participates in"
    USERS }o--o{ DEALS : "participates in"
    USERS ||--o{ FRIENDREQUESTS : sends
    USERS ||--o{ REPORTS : files
    CHATS ||--o{ MESSAGES : contains
    LISTINGS ||--o{ DEALS : "subject of"
    DEALS ||--o{ WALLPOSTS : generates
    USERPOSTS ||--o{ COMMENTS : has
    WALLPOSTS ||--o{ COMMENTS : has

    USERS {
        string firstName
        string lastName
        string avatarUrl
        float rating "server-managed"
        int ratingCount "server-managed"
        bool phoneVerified
        array friends "server-managed"
        array blockedUids
        bool isPrivateProfile
    }
    PRIVATE {
        string email "never public"
        string phone "never public"
        string fcmToken "never public"
        string language
    }
    LISTINGS {
        string userId FK
        string title
        geopoint location
        array imageUrls
        array tags
        bool isHidden "moderation"
    }
    CHATS {
        array participants "immutable"
        string lastMessage
        array mutedBy
    }
    MESSAGES {
        string senderId
        string text
        string mediaUrl
        map reactions
        bool isDeleted "soft delete"
    }
    DEALS {
        array participants
        string listingId FK
        string status
        map proposal1
        map proposal2
        float ownerRating
        float seekerRating
    }
```

**Key decision — the `private` subcollection.** Firestore has no field-level read
filtering: any rule that lets a user read a profile hands them the *entire*
document. Email, phone and device tokens therefore live in
`users/{uid}/private/data`, readable only by its owner, while the public profile
document holds nothing sensitive.

---

## 3. Security model

Rules are the real access-control layer, not the UI.

```mermaid
graph LR
    C["📱 Client"] -->|"request"| R{"Firestore<br/>Security Rules"}
    R -->|"✅ allowed"| DB[("Firestore")]
    R -->|"❌ denied"| X["PERMISSION_DENIED"]
    CF["⚙️ Cloud Functions<br/>(admin SDK)"] -->|"bypasses rules"| DB

    style R fill:#fce8e6,stroke:#ea4335
    style CF fill:#e6f4ea,stroke:#34a853
```

| Enforced rule | Why |
|---|---|
| `private/**` readable only by owner | Prevents mass harvesting of emails and phone numbers |
| `chats.participants` immutable | Stops a participant adding a third party and exposing history |
| Queries must prove membership | Rules filter nothing — an unprovable query is rejected whole |
| `rating`, `friends`, `reportCount` server-only | Removes rating farming and self-added friendships |
| Messages: sender-only soft delete, no undelete | History cannot be silently rewritten |
| `phoneVerified` requires a genuine `phone_number` auth claim | A patched client cannot self-declare as verified |

Rules are covered by an **automated test suite (77 tests)** run against the
Firestore emulator before every deploy — each test asserts both that an attack
is rejected *and* that the legitimate flow still works.

---

## 4. Key flow — proposing and accepting a deal

Shows how client, rules and server-side triggers cooperate.

```mermaid
sequenceDiagram
    participant A as 👤 User A
    participant App as 📱 Client
    participant FS as ☁️ Firestore
    participant CF as ⚙️ Cloud Functions
    participant B as 👤 User B

    A->>App: propose deal
    App->>FS: create deal {participants, status: pending}
    Note over FS: rules verify the author<br/>is one of the participants
    FS-->>CF: onDealProposalSent
    CF->>B: push notification

    B->>App: accept
    App->>FS: update status → active
    Note over FS: cancellation allowed only<br/>while still pending
    FS-->>CF: onDealUpdate
    CF->>FS: create wall posts (admin)

    Note over CF: scheduled job marks<br/>expired deals completed

    A->>FS: submit rating
    FS-->>CF: onDealUpdate
    CF->>FS: aggregate onto B's profile (admin)
    Note over CF: written server-side —<br/>users cannot rate themselves
```

---

## 5. Content moderation

Required by Play policy for any app carrying user-generated content.

```mermaid
graph LR
    U["👤 User"] -->|"report"| RP[("reports")]
    RP -.->|"trigger"| CF["⚙️ onReportCreated"]
    CF -->|"count distinct reporters"| CF
    CF -->|"≥ 3 → isHidden = true"| CONTENT[("listing · post · comment")]
    CONTENT -->|"hidden content<br/>filtered out"| APP["📱 Client"]

    style CF fill:#e6f4ea,stroke:#34a853
```

Counting *distinct* reporters rather than raw reports matters: counting reports
would let a single malicious account file three of them and take down anyone's
content.

---

## 6. Project structure

Feature-first: each feature owns its data, state and presentation layers.

```
lib/
├── core/            # shared services, widgets, constants, utils
└── features/
    ├── auth/        # sign-in, registration, phone verification
    ├── listings/    # create, edit, browse, detail
    ├── map/         # geolocated listing map
    ├── feed/        # paginated listing feed
    ├── chat/        # real-time messaging
    ├── deals/       # agreement flow and ratings
    ├── profile/     # profiles, posts, comments, friends
    ├── report/      # content reporting
    ├── notifications/ · saved/ · search/ · settings/

shareit-functions/   # Cloud Functions — deals, moderation (JS)
push-notifications/  # Cloud Functions — messaging, account lifecycle (TS)
firestore-tests/     # security-rules test suite (77 tests)
```

Each feature follows `data/` (models, repositories) → `providers/` (Riverpod
state) → `presentation/` (screens, widgets), so a feature can be understood, or
removed, in isolation.

---

## Stack

**Client** Flutter · Dart · Riverpod · go_router · Google Maps · Geolocator
**Backend** Firestore · Firebase Auth · Cloud Storage · Cloud Messaging · Cloud Functions (Node.js, TypeScript) · App Check · Crashlytics
**Release** 3 locales (el / en / es) · 24 countries · GDPR-compliant data handling
