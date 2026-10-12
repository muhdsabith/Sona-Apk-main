# Raaga 4.8.1 — YouTube playback update

This ZIP contains the complete updated app, with the same `sona/` layout
expected by your existing Sona-Apk build workflow.

## Install using your phone

1. Replace `sona-flutter-starter.zip` in the root of `muhdsabith/Sona-Apk` with this file. Keep the filename unchanged.
2. Open GitHub Actions → Build Raaga APK → Run workflow.
3. When the build succeeds, download Raaga-Android-APK, extract it and install app-debug.apk.
4. Search for a YouTube song and tap it. Test pause, seek and Next.

## Playback changes

- Direct audio links go straight to the audio player, without a preflight GET that can consume a one-use link.
- Uses the current androidSdkless client, a 15-second extraction deadline and a 25-second total load deadline.
- When direct audio fails, Raaga opens a visible YouTube player inside the app.
- You can also choose Use YouTube player in the full player screen.
- In the fallback, tap Play inside the video if necessary. Keep that screen open; this fallback does not play in the background.
- The fallback includes previous/next and advances through the YouTube items in the queue. If YouTube restricts embedding, it reports the error and offers Open in YouTube.
- Spotify import remains preview-only. No full Spotify playback was added.

## Verification

Dependencies resolved with Flutter 3.47.6. Analysis found no compilation errors,
and all 22 automated tests passed, including four new audio handoff/timeout tests.
No APK build or phone playback has been verified. The live media check was blocked
by a Site Unavailable response in the test environment. See VALIDATION.json.

GitHub was not modified because the connected integration denied write access.
The root ZIP is the only file you need to replace. An updated build workflow is
included at tool/build-android.yml if you need a separate copy later.

---

# Raaga 4.8.0

Flutter music player with a dark lime/lavender interface, saved playlists and
native background audio. Raaga supports local music, licensed direct audio
links, Internet Archive search and public Spotify playlist import.

## What it does

- Import audio files from your phone and play them in the background.
- Add direct HTTPS audio links from your own or licensed catalogs.
- Search the Internet Archive for Creative Commons, public-domain and LibriVox
  audio. Each result keeps its license information.
- Import a public Spotify playlist by pasting its `open.spotify.com/playlist/...`
  share URL, a `spotify:playlist:...` URI or the 22-character playlist ID.
- On Android, use Spotify **Share > Raaga**. Raaga detects the shared playlist
  link and imports it automatically.
- Imported Spotify tracks are saved as playlist metadata in Raaga. When Spotify
  exposes an official preview URL for a track, Raaga can play that preview.
  Raaga does not convert Spotify full tracks into downloadable/direct streams.
- Search, favourites, playlists, sleep timer, lock-screen controls and podcast
  feed import remain available.

## Spotify import implementation

Raaga reads Spotify's public embed page at
`https://open.spotify.com/embed/playlist/{id}` and parses the `__NEXT_DATA__`
playlist track list. This does not require a Spotify client secret or Spotify
Web API login. It is an unofficial page format and can stop working if Spotify
changes the embed page structure.

The import is intended for playlist metadata. Spotify preview availability is
controlled by Spotify/rightsholders and varies by track. A track with no
preview stays in the imported Raaga playlist but cannot be played by Raaga's
normal `just_audio` player.

The public embed page can also limit how much playlist data it exposes. The
current importer uses the track list present in that page and does not use
private Spotify APIs or stream-ripping services.

## Spotube

Spotube is not bundled as a dependency. The earlier attempt to use Spotube as a
git dependency was removed because Spotube is a full application and introduced
package-version conflicts in this starter project.

## Android phone build

1. Upload **raaga-flutter-starter-v4.8.0.zip** to your GitHub repository root.
2. Put `tool/build-android.yml` in `.github/workflows/build-android.yml` if your
   repository does not already contain the workflow there.
3. Run **Build Raaga APK** from GitHub Actions.
4. Download the **Raaga-Android-APK** artifact and install `app-debug.apk`.

The ZIP keeps top-level `sona/` and Android package `com.example.sona`.

## Verification

Not verified in this editing environment because Flutter and Dart SDKs are not
installed here. The included GitHub Actions workflow runs `flutter pub get`,
`flutter analyze`, tests and the Android debug APK build.
