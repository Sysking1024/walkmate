# WalkMate

[简体中文](README.md) | English

A progressive rehabilitation app that helps people with acquired vision loss build confidence in independent travel. An Insta360 X5 panoramic camera acts as the user’s eyes, while the phone provides obstacle detection, scene descriptions, and voice conversations. After each training session, the app automatically creates a highlight video with narration and subtitles for sharing with the rehabilitation community.

An entry for the Insta360 Hackathon, September 2026, China Nanjing.

## Features

- **Progressive training**: Indoor orientation → semi-open environments (neighborhood routes) → independent outdoor travel. Stages unlock based on training records.
- **Obstacle detection**: Insta360’s open-source [DAP](https://github.com/Insta360-Research-Team/DAP) panoramic depth estimation model (Depth Any Panoramas, CVPR 2026, with on-device Core ML inference) identifies obstacles and walkable paths in the forward sector. Guidance uses 3D spatial audio through headphones, or spoken directions and distances through the speaker.
- **AI companion**: Activated when the user stands still for 5 seconds or says “walkmate.” Qwen3-VL describes the surroundings from camera images, and Qwen3-TTS reads the description aloud. Users can ask follow-up questions by voice.
- **Highlights**: Records the stitched panoramic preview during conversations. After training, selected moments are edited into a vertical short video with subtitles, voiceover, and background music.
- **Community**: Friends’ achievements, accessible place reviews (ratings, routes, Amap walking navigation, and friend invitations), and shared journeys.
- **Accessibility**: Full VoiceOver support, large touch targets, Dynamic Type, and unique melodies for badges.

## Repository Structure

```text
WalkMate/               iOS app (SwiftUI, iOS 17+)
  App/                  App entry point and main camera view (teammate’s travel screen)
  Core/Camera           Insta360 SDK connection, streaming, and frame bus
  Core/Inference        DAP depth estimation
  Core/Perception       Spatial perception (obstacles and paths)
  Core/Audio            Spatial audio and procedural audio cues
  Core/Collector        Perception data collection and offline replay
  Core/Narration        Scene descriptions (Qwen3-VL), speech synthesis, and subtitles
  Core/Conversation     Stationary detection, conversation state machine, and voice commands
  Core/Recording        Preview recording, video composition, and highlight generation
  Core/Community        Place ratings and community feed
  Core/Training         Training records and stage unlocking
  Core/Backend          Backend client (offline-first)
  Core/Settings         Preferences and accessibility feedback
  Core/Badges           Badge melodies
  Features/             App screens (Home, Training, Community, Profile, Routes, and Growth)
  Resources/            Design assets, demo videos, badge audio, and Secrets.plist
backend/                Community backend using Python’s standard library and SQLite
Tests/                  Module unit tests; NarrationTests contains scripted checks
specs/                  Feature requirements, implementation plans, and task breakdowns
```

## Installation Guide for Judges (Packaged Version)

The submitted archive already includes the following files, which are excluded from version control. Extract the archive and follow “Run on a Physical Device” below:

- `WalkMate/Frameworks/`: Insta360 iOS SDK (v1.10.4)
- `WalkMate/Resources/Secrets.plist`: Alibaba Cloud Model Studio credentials and backend URL
- `WalkMate/Resources/Models/dap_256x512_int8.mlpackage`: Depth estimation model

You will need an Insta360 X5 (with the phone connected to its Wi-Fi hotspot), a phone with cellular data (for scene descriptions, speech recognition, and community sync), and an iPhone running iOS 17 or later. Without a camera, you can still try all features except the live training view. If the backend is unavailable, the community automatically uses built-in data.

## Setup

1. **Xcode**: Xcode 27 beta. Run on a physical device, as the Insta360 SDK does not include simulator slices.

2. **Insta360 SDK**: Create a symbolic link from the SDK’s `Frameworks` directory to `WalkMate/Frameworks` (already listed in `.gitignore`).

   ```bash
   ln -s /path/to/iOS_v1.10.4/INSCameraSDKSample-bluetooth/Frameworks WalkMate/Frameworks
   ```

3. **Credentials**: Copy `WalkMate/Resources/Secrets.example.plist` to `Secrets.plist` and fill in:

   - `QwenAPIKey`, `QwenBaseURL`, and `QwenDashScopeURL`: Alibaba Cloud Model Studio credentials and endpoints
   - `BackendBaseURL`: Community backend URL (use your local network IP for local debugging)

4. **Depth model**: Place `dap_256x512_int8.mlpackage`, converted from [DAP](https://github.com/Insta360-Research-Team/DAP), in `WalkMate/Resources/Models/` (319 MB; excluded from version control).

5. **Generate the Xcode project**:

   ```bash
   cd WalkMate && xcodegen generate
   ```

## Run on a Physical Device

Open `WalkMate/WalkMate.xcodeproj` in Xcode, select a physical device, and run. When using your own developer account, override the signing settings from the command line without changing `project.yml`:

```bash
xcodebuild -project WalkMate/WalkMate.xcodeproj -scheme WalkMate \
  -destination "id=<DEVICE_UDID>" -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=<TEAM_ID> PRODUCT_BUNDLE_IDENTIFIER=<YOUR_BUNDLE_ID> build
```

Connect the phone to the camera’s Wi-Fi hotspot, then tap “Connect Camera” on the Training screen. Scene descriptions and speech recognition use cellular data.

## Backend

```bash
python3 backend/server.py --port 8080 --db backend/walkmate.db
```

No external dependencies are required. On first launch, the backend automatically creates the database tables and inserts seed data. See `backend/README.md` for API details. The iOS client is offline-first: changes take effect locally and are sent to the backend when it becomes available.

## Tests

```bash
# Xcode unit tests (camera, perception, audio, replay, etc.)
xcodebuild test -project WalkMate/WalkMate.xcodeproj -scheme WalkMate -destination "id=<DEVICE_UDID>"

# Scripted checks for narration and conversation (no Xcode project required)
cat WalkMate/Core/Conversation/VoiceIntent.swift Tests/NarrationTests/VoiceIntentChecks.swift | xcrun swift -
```

## Voice Commands During Training

The commands below are translated for reference; the original spoken commands are in Chinese.

| What to say | Effect |
|---|---|
| “walkmate，说说周围” (“walkmate, describe my surroundings”) | Immediately describes the surroundings |
| “walkmate，左手边是什么” (“walkmate, what’s on my left?”) | Describes the surroundings, then answers the question |
| “好 / 不用” (“Yes / No thanks”), when the companion asks “Would you like me to describe this place?” | Accepts or declines |
| Any question within 15 seconds after a description | Asks a follow-up question |
| “够了 / 停” (“That’s enough / Stop”) | Ends the current conversation |

## Conventions

- Write comments, logs, and commit messages in Chinese. Use `Log.info(_:category:)` for logging; do not use `print`.
- Touch targets must be at least 48 points. Group each card into a single VoiceOver element.
- Store credentials only in `Secrets.plist` and keep the file out of version control.

## Co-Authors

YU XIAOXUE  LIN XIN
