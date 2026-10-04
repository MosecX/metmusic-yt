# MetMusic

A Flutter music streaming client for YouTube Music. It searches the YouTube
Music catalog and plays audio streams directly, with no downloaded media and no
bundled resolver.

## Features

- Search the YouTube Music catalog (Songs tab, up to 20 results) with artwork,
  artist, album and duration.
- Resolve any track to a directly playable audio stream and play it through
  `just_audio`.
- A media session: lock screen and notification controls, and playback that
  survives the app being backgrounded.
- A floating glass player bar with a draggable seek bar, and a full player that
  expands from it.

## How stream resolution works

The InnerTube engine lives in `lib/services/youtube_music/` and was ported from
[BStream Music](https://github.com/nicobailon/bstream-music)'s
`lib/services/youtube_music/` — the client ladder, the PO token / EJS solver
stack, the deep range validator and the search parsers. Only the UI is ours.

### The client ladder

YouTube does not accept every client identity, and the identities that work for
searching are not the ones that work for playback. The registry
(`lib/services/youtube_music/playback/innertube_client_profile.dart`) declares
them all; the router (`innertube_client_router.dart`) picks eligible candidates
per request and remembers which ones are healthy.

| Client | Search | Playback | Notes |
| --- | --- | --- | --- |
| `iosMusic` (26) | yes | no (`LOGIN_REQUIRED`) | Primary search client |
| `androidMusic` (21) | yes | no (`LOGIN_REQUIRED`) | Search fallback |
| `visionOS` | no | yes, with a PO token | Primary playback client |
| `androidSdkless` | no | yes, with a PO token | Playback fallback |
| `tv`, `webMusic`, `mweb` | no | with a PO token | Later fallbacks |

Two consequences are baked into the design:

- **Search only works with a music client.** The desktop web client is rejected
  outright and the generic Android client answers with non-music renderers.
- **Playback needs a Web PO token.** The clients that return audio URLs only do
  so when the request carries a BotGuard PO token. `ios` and `android` are
  marked `unsupportedByWebPo` and excluded by the router on purpose: they need a
  platform attestation provider that does not exist, so the engine never sends
  requests that are guaranteed to be rejected.

### Request flow

1. Scrape `INNERTUBE_API_KEY`, `INNERTUBE_CLIENT_VERSION` and `VISITOR_DATA`
   from `music.youtube.com` (cached; the key rotates, so it is never hardcoded).
2. `POST /youtubei/v1/search` with the music client ladder, failing over to the
   next client when one is rejected.
3. `POST /youtubei/v1/player` with the playback ladder, ranking the returned
   audio formats by bitrate and preferring M4A/AAC as a tie-breaker.
4. Probe each candidate with a **deep** range read before publishing it, so a URL
   that resolves but cannot be fetched is caught here rather than silently
   failing in the player.
5. Stream through `StreamProxy` (see below).

### PO tokens and the WebView

The PO token and EJS solvers run BotGuard inside a headless WebView, because
BotGuard fingerprints its environment and refuses to install its minter without
a real browser. `HeadlessInAppWebViewJavaScriptRuntime` is backed by
`flutter_inappwebview`, which also intercepts requests natively and so bypasses
the CORS wall that blocks a plain WebView.

They are only constructed on platforms that have a WebView
(`lib/main.dart`), which today means **Android and iOS only**. On desktop they
are omitted rather than stubbed, and the router narrows the ladder accordingly —
desktop can search but is not expected to play.

### Why playback goes through a local proxy

ExoPlayer's first request is `Range: bytes=0-`, an open-ended range, which
googlevideo answers with **403**. Only bounded ranges are served. This was the
cause of `Playback failed: Source error`.

`StreamProxy` (`lib/player/stream_proxy.dart`) listens on loopback and answers
whatever the player asks for using bounded 256 KiB upstream reads, so the
player's open-ended request becomes a working `206`. The proxy also keeps the
identity-bound User-Agent and the signed URL inside the app instead of handing
them to the platform player. Android's cleartext block is satisfied by
`android/app/src/main/res/xml/network_security_config.xml`, which permits HTTP
**only** on loopback.

If the CDN stops serving partway through a track, the proxy reports the stall and
the player transparently re-resolves and resumes at the same position.

### The depth ceiling, and what removed it

Before the PO token stack existed, this app could only read about the **first
1 MiB** of a track — roughly 50 seconds — no matter which client it asked. The
refusal appeared even on a freshly resolved URL, so it was not a per-URL budget,
and re-resolving did not extend it. The CDN serves the opening chunk and then
answers 403 for deeper ranges when the request carries no BotGuard PO token.

With the solvers wired up, whole tracks play through. Verified on device with a
4:01 track playing to completion. `flutter test --tags live` keeps a guard for
this: it reads through the proxy and fails if a track dies below 2 MiB, so the
ceiling cannot silently come back.

## Project layout

```text
lib/
  services/youtube_music/   ported InnerTube engine: transport, client ladder,
                            search parsers, PO token + EJS solvers, resolver
  core/                     platform detection, bounded byte stream
  app/                      app-level state (search + playback coordination)
  player/                   just_audio wrapper and the loopback stream proxy
  app/                      service wiring and app-level state
  ui/                       search page, floating player bar, expanded player
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
flutter test --exclude-tags live   # hermetic, what CI runs
```

The engine's parser, resolver, validator and PO token tests are ported from
BStream, so the resolution layer is covered by the suite that shipped it.

A tagged suite exercises the live network path — real search, real resolution,
and a deep read through the proxy to catch the ~1 MiB ceiling regressing:

```bash
flutter test --tags live
```

It is excluded from the default run so CI never depends on a third-party service.

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

- **No shuffle or repeat.** The queue is the current result set; there is no
  reordering or persistence across sessions.
- **Playback needs Android or iOS.** The PO token solvers require a WebView. On
  desktop the app searches but has no way to mint tokens, so playback is not
  expected to resolve.
- **A browser build is not possible as written**: `music.youtube.com` sends no
  `Access-Control-Allow-Origin` headers and its preflight returns `403`, so the
  browser blocks the API.
- Playback depends on YouTube continuing to accept the clients in
  `InnerTubeClientRegistry`, and on BotGuard's handshake continuing to work.
  Both are internal behaviours that change without notice; when they do, the
  ladder is where a replacement identity is added.
- No offline downloads, playlists, lyrics or account sync.

## Notes

This project is not affiliated with or endorsed by YouTube or Google. You are
responsible for complying with copyright law and YouTube's Terms of Service.