# StreamBD IPTV v5.0 — Native iOS Port (SwiftUI)

Complete native iOS SwiftUI port of **StreamBD IPTV v5.0.apk**, ready to compile into an unsigned `.ipa` via **GitHub Actions (`macos-14`)** for **LiveContainer**, **SideStore**, **AltStore**, or **Sideloadly** on iPhone.

## Reverse-Engineered Architecture Included

1. **Native AES-128-CBC Decryption (`CryptoUtils.swift`)**
   - Extracted from `lib/arm64-v8a/libnative-keys.so` (`Java_com_streambd_iptv_utils_CryptoUtils_getNativeAesKey` & `getNativeAesIv`):
     - **AES Key**: `X3#yS@6k~u&hr$0z`
     - **AES IV**: `n!0kfd&re%3#pw*s`
   - Automatically decrypts `.enc` and Base64-encrypted JSON/M3U responses via Apple's native `CommonCrypto` framework.

2. **Decrypted RemoteConfig Endpoints (`AppConfig.swift`)**
   - **Live TV Catalog (`iptv_playlist_url`)**: `https://myselfhridoy.github.io/streambd-libs/playlists/IPTV.json`
   - **Live Sports Events (`live_events_api_url`)**: `https://myselfhridoy.github.io/streambdAPI/api/all/events/index.enc`
   - **Event Streams Pattern**: `https://myselfhridoy.github.io/streambdAPI/api/all/events/{event.id}/index.enc`
   - **VOD Addon Registry (`addon_registry_url`)**: `https://myselfhridoy.github.io/streambd-libs/addons/StreamBD_IPTV_Addon.json`
   - **TMDB API Key (`tmdb_api_key`)**: `460327acf6e0235a391222cb530de9c8`

3. **Bundled APK Assets (`StreamBDIPTV/Resources/`)**
   - `channels.json` (133 Bangladeshi & regional channels with AkashBD CDN logos)
   - `plusbox.js`, `server1_jio.js`, `server2_jio.js` (ported to native async Swift + `JavaScriptCore` fallback)
   - `crypto-js.min.js` & original `AppIcon` (`icon 512x512.png` upscaled to 1024×1024)

## How to Build the `.ipa` on GitHub Actions (No Mac Needed)

1. Create a new GitHub repository and upload/push the contents of this folder (ensuring `.github/workflows/build-ipa.yml` is in the root).
2. Open the **Actions** tab in your GitHub repository and run **Build StreamBD IPTV iOS IPA**.
3. Download **`StreamBD-IPTV-v5.0-iOS-IPA`** (`StreamBD-IPTV-v5.0-iOS.ipa`) from the workflow run's Artifacts section and import it into **LiveContainer**, **SideStore**, **AltStore**, or **Sideloadly**.
