# MetMusic

A Flutter music streaming client for YouTube Music. It searches the YouTube
Music catalog and plays audio streams directly, with no downloaded media and no
bundled resolver.

## Features

- Search the YouTube Music catalog (Songs tab, up to 20 results) with artwork,
  artist, album and duration.
- Resolve any track to a directly playable audio stream and play it through
  `just_audio`.
- A persistent mini player with progress, play/pause and stop.

## How stream resolution works

The InnerTube layer lives in `lib/innertube/` and mirrors the architecture used
by BStream Music, reduced to what is verified to work today.

### The client ladder

YouTube does not accept every client identity, and the identities that work for
searching are not the ones that work for playback. Each entry in the ladder was
verified against the live API while building this app:

| Client | Search | Playback | Notes |
| --- | --- | --- | --- |
| `iosMusic` (26) | yes | no (`LOGIN_REQUIRED`) | Primary search client |
| `androidMusic` (21) | yes | no (`LOGIN_REQUIRED`) | Search fallback |
| `ios` (5) | no | **yes** | Returns direct, unciphered audio URLs |
| `android` (3) | no | no | `OK` but withholds all stream URLs |

Consequences baked into the design:

- **Search only works with a music client.** The desktop web client is rejected
  outright and the generic Android client answers with non-music renderers.
- **Playback only works with the `ios` client.** It returns audio formats with a
  ready `url`, so no PO token and no JavaScript signature solver are needed.
  Formats behind a `signatureCipher` are discarded, because this app ships no
  EJS runtime to decipher them.
- **The `User-Agent` is mandatory on playback.** googlevideo binds each media
  URL to the client identity that produced it and answers `403` without it.

### Request flow

1. Scrape `INNERTUBE_API_KEY`, `INNERTUBE_CLIENT_VERSION` and `VISITOR_DATA`
   from `music.youtube.com` (cached; the key rotates, so it is never hardcoded).
2. `POST /youtubei/v1/search` with the music client ladder, failing over to the
   next client when one is rejected.
3. `POST /youtubei/v1/player` with the playback ladder, then rank the returned
   audio formats by bitrate, preferring M4A/AAC as a tie-breaker.
4. Probe each candidate with a bounded range read before publishing it, so a URL
   that resolves but cannot be fetched is caught here rather than silently
   failing in the player.

### The stream probe size

`InnerTubeStreamValidator` probes with a 512 KiB range. This is measured, not
assumed: against the live `ios` client, ranged requests up to 1 MiB are served
while a 1.5 MiB range returns `403`, even though the same URL serves a 1 KiB
range fine. BStream probes 3 MiB, which is rejected here.

## Project layout

```text
lib/
  innertube/        InnerTube transport, client ladder, parsers, resolver
  app/              app-level state (search + playback coordination)
  player/           just_audio wrapper
  ui/               search page and mini player
```

The transport is an interface (`InnerTubeTransport`) so a platform without
`dart:io` can be added without touching call sites.

## Building

```bash
flutter pub get
flutter run
```

### Release APKs on GitHub Actions

APKs are built on CI, not locally. The **Build APK** workflow
(`.github/workflows/build-apk.yml`) runs on every push and pull request, and can
also be triggered manually from the **Actions** tab.

It has three jobs:

1. **Verify** — `flutter pub get`, `flutter analyze`, `flutter test`.
2. **Build** — one job per ABI (`arm64-v8a`, `armeabi-v7a`, `x86_64`) plus a
   universal APK, each uploaded as a separate artifact.
3. **Summary** — writes an artifact table to the run summary.

Download the APKs from the run's **Artifacts** section. Release builds are
currently signed with the debug key, so they are for testing and sideloading
only; see [Release signing](#release-signing) before distributing them.

## Tests

```bash
flutter test
```

Parser tests run against fixtures captured from the real API
(`test/fixtures.dart`), preserving the real renderer shapes.

A separate script exercises the live network path:

```bash
dart run test/live_innertube.dart          # searches and resolves for real
QUERY="pink floyd" dart run test/live_innertube.dart
```

It is not part of `flutter test`, so CI never depends on a third-party service.

## Release signing

Release builds currently use the debug key. To sign properly, copy
`android/key.properties.example` to `android/key.properties` and point it at a
keystore outside the repository:

```properties
storeFile=../release/keystore.jks
storePassword=...
keyAlias=metmusic
keyPassword=...
```

These environment variables are also supported:
`METMUSIC_ANDROID_STORE_FILE`, `METMUSIC_ANDROID_STORE_PASSWORD`,
`METMUSIC_ANDROID_KEY_ALIAS`, `METMUSIC_ANDROID_KEY_PASSWORD`.

`key.properties`, `*.jks` and `*.keystore` are excluded from Git.

## Limitations

- **Android only.** A browser build is not possible as written:
  `music.youtube.com` sends no `Access-Control-Allow-Origin` headers and its
  preflight returns `403`, so the browser blocks the API. Supporting web would
  require a proxy.
- Playback depends on the `ios` client being accepted. If YouTube retires it,
  playback breaks until a new client is verified and added to
  `InnerTubeClientRegistry`.
- No offline downloads, playlists, lyrics or account sync.

## Notes

This project is not affiliated with or endorsed by YouTube or Google. You are
responsible for complying with copyright law and YouTube's Terms of Service.