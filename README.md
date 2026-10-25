# Itinerary by Leonera Labs

An iPhone app that turns the activities you dictate into a one-day itinerary. It takes into account your
home and office, travel times, your daily routines and the fixed events of your calendar, and it tries to
move flexible activities to the morning.

- **SwiftUI**, iOS 17+, no third-party dependencies.
- English and Spanish; the app follows the language of the iPhone.
- Visible name: **Itinerary by Leonera Labs**. Bundle ID: `com.leonardoramirezr.itinerarybyleoneralabs`.

## Features

| Feature | Where |
| --- | --- |
| Asks for your home and office on first launch (your home can also be your office) | Onboarding, Settings › Places |
| Dictate activities; Groq Whisper transcribes them and you can edit the text | Plan my day |
| An LLM builds the itinerary considering travel, estimated durations, routines and fixed events | Plan my day › Generate |
| Prioritizes the morning for flexible activities | Default planner prompt |
| Day view like Google Calendar with two modes: same height for every event, or height proportional to the duration | Home (segmented control) and Settings › Display |
| Imports fixed events from Google Calendar (OAuth) or from the calendars configured on the iPhone | Settings › Calendar |
| Daily routines (shower, get ready, exercise…) in three slots — morning, midday and night — with a custom duration | Settings › Daily routines |
| Every prompt the app uses can be edited and restored | Settings › Prompts |
| LLM providers through their OpenAI-compatible API: Gemini, OpenAI, Cloudflare Workers AI, NVIDIA NIM and Groq | Settings › Providers and API keys |
| Test button for every API key | Provider and speech to text screens |

## Configuring the app

### LLM providers

API keys are stored in the iOS Keychain. As soon as a key is entered, the app lists the models of the provider
(`{base URL}/models`) and offers them in a picker. Model and base URL can be changed per provider; the app calls
`{base URL}/chat/completions`.

| Provider | Default base URL | Default model | Get a key |
| --- | --- | --- | --- |
| Google Gemini | `https://generativelanguage.googleapis.com/v1beta/openai` | `gemini-2.5-flash` | [AI Studio](https://aistudio.google.com/apikey) |
| OpenAI | `https://api.openai.com/v1` | `gpt-5-mini` | [OpenAI](https://platform.openai.com/api-keys) |
| Cloudflare Workers AI | `https://api.cloudflare.com/client/v4/accounts/{account_id}/ai/v1` | `@cf/meta/llama-3.3-70b-instruct-fp8-fast` | [Cloudflare](https://dash.cloudflare.com/profile/api-tokens) (token with the Workers AI permission, plus your account ID) |
| NVIDIA NIM | `https://integrate.api.nvidia.com/v1` | `meta/llama-3.3-70b-instruct` | [NVIDIA](https://build.nvidia.com/settings/api-keys) |
| Groq | `https://api.groq.com/openai/v1` | `openai/gpt-oss-120b` | [Groq](https://console.groq.com/keys) |

**Test API key** sends the *API key test* prompt to the configured model, so it validates the key, the base
URL and the model at the same time.

### Speech to text

Dictation is transcribed by Groq (`whisper-large-v3-turbo` through `{base URL}/audio/transcriptions`). It uses
the same key as the Groq LLM provider. The models available for the key are listed automatically in a picker.

### Google Calendar

The app talks to the Google Calendar API directly with OAuth 2.0 + PKCE (no Google SDK). You need your own
OAuth client:

1. Open [Google Cloud Console](https://console.cloud.google.com/) and create (or pick) a project.
2. **APIs & Services › Library**: enable the **Google Calendar API**.
3. **Google Auth Platform** (OAuth consent screen): choose *External*, fill in the app name and your email,
   add your Google account as a **test user**, and add the scopes `openid`, `email` and
   `https://www.googleapis.com/auth/calendar.readonly`.
4. **Credentials › Create credentials › OAuth client ID**: application type **iOS**, bundle ID
   `com.leonardoramirezr.itinerarybyleoneralabs`.
5. Copy the client ID (it ends with `.apps.googleusercontent.com`), paste it in **Settings › Calendar ›
   Google Calendar › OAuth client ID** and tap **Connect Google Calendar**. Then choose the calendars to import.

While the OAuth app is in *Testing*, Google expires refresh tokens after seven days, so you will have to
connect again from time to time. As an alternative, choose **iPhone calendars**: Google accounts added in
the iPhone Settings app (Calendar › Accounts) are read through EventKit without any OAuth setup.

### Prompts

The planner uses two prompts (system instructions and the day request) with placeholders such as
`{{activities}}`, `{{routines}}`, `{{fixedEvents}}`, `{{home}}`, `{{office}}`, `{{commute}}` and
`{{language}}`. The app expects the JSON structure described in the default planner instructions
(`summary`, `items` with `title`, `start`, `end`, `kind`, `location`, `notes`, and `unscheduled`).

## Development

```bash
brew install xcodegen
xcodegen generate
open Itinerary.xcodeproj
```

The Xcode project is generated from `project.yml` and is not committed. The bundle identifier is the build
setting `APP_BUNDLE_ID`; future extensions must use `$(APP_BUNDLE_ID).<suffix>`.

Useful checks that do not need Xcode:

```bash
python3 scripts/check-localizations.py   # every UI string exists in English and Spanish
```

### Layout

```
Itinerary/
  App/          App entry point and root view
  Models/       Settings, places, routines, providers, prompts, itineraries
  Stores/       Settings (UserDefaults), itineraries (JSON file), Keychain
  Services/     LLM client, Groq transcription, planner/parser, audio, location, Google/iPhone calendars
  Utilities/    Errors, HTTP helpers, text and time formatting
  Views/        SwiftUI screens (home, timeline, dictation, onboarding, settings)
  Resources/    Assets, en.lproj and es.lproj strings
Config/Info.plist
scripts/        CI helpers (App Store Connect, GitHub Pages, localization check)
```

## Continuous delivery

Every push (to any branch except `gh-pages`) runs `.github/workflows/build.yml` on `macos-15`. It builds the
app, signs it Ad Hoc, publishes the IPA on GitHub Pages so it can be installed from Safari on the iPhone,
and creates a GitHub release.

### Required secrets

Add them in **Settings › Secrets and variables › Actions › Repository secrets** (repository secrets, not
organization secrets, because this is a personal repository):

| Secret | Value |
| --- | --- |
| `ASC_KEY_ID` | Key ID of an App Store Connect API key. |
| `ASC_ISSUER_ID` | Issuer ID shown above the list of keys. |
| `ASC_KEY_P8` | Full contents of the downloaded `AuthKey_XXXXXXXX.p8` file. It must be a **Team key** with the **Admin** role (needed for cloud-managed distribution certificates). |
| `APPLE_TEAM_ID` | Apple Developer Team ID. |

- **No secrets:** the workflow builds an **unsigned IPA** and uploads it as a workflow artifact; nothing is
  published.
- **Only some secrets:** the workflow fails with an error that lists the missing ones.

### What the workflow does

1. Computes the tag. On `main` it is `0.x.0`, incrementing the middle number of the latest `0.x.0` tag, and it is
   published as the **Latest** stable release. On other branches it is `build-<run_number>-<sha7>` and it is
   published as a **pre-release**. Builds are never cancelled: `main` builds run one at a time and every other
   run has its own concurrency group.
2. Validates the App Store Connect key with `scripts/asc.py` (JWT ES256 signed with `openssl`) and checks that
   at least one iOS device is registered.
3. Archives with automatic signing (`-allowProvisioningUpdates` plus the API key). Xcode registers the App ID
   and creates the profiles.
4. Exports with `method=release-testing` and `signingStyle=automatic`, which uses the cloud-managed distribution
   certificate and an Ad Hoc profile with every registered device. It then verifies that every bundle embeds
   an Ad Hoc `embedded.mobileprovision` and prints how many devices it includes.
5. Publishes the build to the `gh-pages` branch with `scripts/publish-pages.sh`: one folder per tag with the
   IPA, `manifest.plist`, `index.html` (with the `itms-services://` install button) and `build.json`. The home
   page lists every build with its commit title and has a button for the latest stable version. The branch is
   rewritten as a single orphan commit, all `main` versions are kept, and only the last 20 branch builds are kept.
6. Creates the GitHub release with the IPA and the install link, and adds the link to the run summary.
7. Always revokes, through the API, the temporary *Apple Development* certificate that `xcodebuild` creates in
   each run (only the certificates that were not in the keychain before the archive).

### Enable GitHub Pages (once)

After the **first signed build** has finished (it creates the `gh-pages` branch), open **Settings › Pages**
and choose **Deploy from a branch**, branch **`gh-pages`**, folder **`/ (root)`**. The site is published at
`https://leonardoramirezr.github.io/<repository>/`.

### Add an iPhone

Register the UDID of the iPhone in the Apple Developer portal
(**Certificates, Identifiers & Profiles › Devices**) and push any commit. The next build regenerates the Ad Hoc
profile with every registered device, so the new iPhone can install it.
