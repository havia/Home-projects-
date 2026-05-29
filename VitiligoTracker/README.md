# VitiligoTracker

A native iOS app for tracking vitiligo progression over time using phototherapy and medicine treatment. Built entirely with Apple frameworks — no third-party dependencies.

---

## How to Open in Xcode

1. Clone or copy this folder to your Mac.
2. Open Xcode (version 15.0 or later required).
3. Select **File → Open** and navigate to `VitiligoTracker/VitiligoTracker.xcodeproj`.
4. Xcode will load the project. Wait for it to index the files.
5. If prompted to update the project format, click **Update to recommended settings**.

---

## Required iOS Version

**iOS 17.0 or later** is required. The app uses:
- SwiftData (iOS 17+) for local persistence
- VNDetectFaceLandmarksRequest (Vision framework)
- Swift Charts (iOS 16+)
- PhotosUI PhotosPicker (iOS 16+)
- async/await throughout

---

## How to Install on iPhone (No Paid Developer Account Required)

You can run this app on your own iPhone using a free Apple ID (personal team):

1. In Xcode, connect your iPhone via USB cable.
2. In the top toolbar, select your iPhone as the run destination (not a Simulator).
3. Go to **VitiligoTracker target → Signing & Capabilities**.
4. Under **Team**, select your personal Apple ID. If it doesn't appear, go to Xcode → Settings → Accounts and add your Apple ID.
5. Xcode will change the bundle ID automatically if needed.
6. On your iPhone, go to **Settings → General → VPN & Device Management** and trust your developer certificate.
7. Press **Run (⌘R)** in Xcode. The app will build and install.

**Note:** Free personal team certificates expire after 7 days for physical devices. Re-run from Xcode to refresh. A $99/year Apple Developer account removes this limitation.

---

## Camera Protocol for Consistent Tracking

For the most accurate spot tracking across sessions, follow the same protocol each time:

### Lighting
- Use natural daylight from a window (indirect, not direct sunlight to avoid harsh shadows).
- If indoors, use a ring light or two balanced white lights at 45-degree angles to your face.
- Avoid colored lights, warm/yellow incandescent bulbs, or strong overhead lighting that creates shadows.
- Ideal color temperature: 5500K–6500K (daylight white).

### Distance and Angle
- Hold your iPhone **30–40 cm** from your face.
- Use the **main (wide) camera** — not selfie camera, for higher resolution.
- Face the camera **straight on** — chin level, eyes forward, neutral expression.
- Keep your hair pulled back from your face.
- Stand or sit in the same position against the same plain background each session.

### Timing
- Try to photograph at the **same time of day** (skin tone and lighting vary).
- Wait at least 30 minutes after phototherapy before photographing to let any redness settle (unless you want to document the reaction).
- Remove makeup, cream, and sunscreen before photographing for accurate skin tone readings.

### iPhone 15 Pro Tips
- Use **Portrait mode** or the standard Photo mode — both work well.
- Tap on your face to lock focus and exposure before capturing.
- Enable the grid in Camera settings to help with consistent framing.
- The app also accepts videos — if recording video, record 3–5 seconds holding still, and the app will extract the sharpest frame with best face detection.

---

## How Spot Detection Works

### Overview
The app uses a pipeline of Apple Vision and CoreImage analysis to automatically detect and track hypopigmented (depigmented) patches on the face:

### Step 1: Face Detection (Vision Framework)
`VNDetectFaceLandmarksRequest` detects the face bounding box and 76+ facial landmarks (eyes, nose, mouth, jawline). The image is cropped to just the face region with 20% padding.

### Step 2: LAB Color Space Conversion
Each pixel of the face image is converted from sRGB to the CIE LAB color space. The **L* channel** represents perceptual lightness (0 = black, 100 = white). Vitiligo patches appear as significantly higher L* values than surrounding normally-pigmented skin.

This conversion is performed mathematically per-pixel:
- sRGB → linearized RGB → CIE XYZ (D65 white point) → LAB

### Step 3: Baseline Skin Tone Sampling
The app samples the skin tone from areas less commonly affected by vitiligo: the nose bridge region and inner cheeks. It uses the 40th percentile L* value of these samples as the "normal" baseline for that individual's skin tone. This makes it adaptive to different skin tones automatically.

### Step 4: Hypopigmentation Threshold
Any pixel where `L* > baseline + 15` is flagged as potentially depigmented. The threshold of 15 LAB units corresponds to a clearly visible lightening — this is calibrated to avoid false positives from skin surface highlights while still catching early depigmentation.

### Step 5: Morphological Filtering
- **Erosion** (radius 2): Removes small noise pixels and thin edges.
- **Dilation** (radius 3): Restores and slightly expands the cleaned regions.

### Step 6: Connected Components Analysis
Remaining bright regions are grouped using BFS flood-fill. Each connected region becomes a candidate spot with a normalized bounding box, centroid, area (as fraction of face), and mean L* value.

Regions smaller than 0.3% of face area (noise) or larger than 60% (glare/non-vitiligo) are discarded.

### Step 7: Spot Tracking Across Sessions
When you analyze a new session, detected regions are matched to existing spots from previous sessions using **centroid distance**. If a detected region's center is within 15% of the face width/height of an existing spot, they are linked as the same spot. Otherwise, a new spot is created with an auto-generated label based on face zone (Left Cheek, Forehead, Chin, etc.).

### Step 8: Trend Calculation
Each spot's trend is determined by comparing its two most recent measurements:
- **Improving**: Area shrinking >5% OR luminance decreasing >2 L* units (repigmentation)
- **Worsening**: Area growing >5% OR luminance increasing >2 L* units (spreading)
- **Stable**: Changes within those thresholds

### Limitations
- Detection accuracy depends heavily on consistent lighting between sessions.
- Very early-stage vitiligo (subtle patches) may not be detected until they reach a certain lightness contrast.
- Background skin color changes (tanning, sunburn, natural variation) can slightly affect the baseline threshold. Using the same lighting setup each session minimizes this.
- Shiny areas of skin (nose, forehead) can occasionally register as false positives — these typically appear in the same location across sessions and can be ignored as stable "spots."

---

## Data Storage

All photos and session data are stored **entirely on your device**:
- Session photos: `Documents/SessionPhotos/` (within the app sandbox)
- Database: SwiftData SQLite store in the app's Application Support directory

No data is sent to any server. No network requests are made. The app works completely offline.

---

## Project Structure

```
VitiligoTracker/
├── VitiligoTracker.xcodeproj/
│   └── project.pbxproj
└── VitiligoTracker/
    ├── VitiligoTrackerApp.swift      # App entry point, SwiftData container setup
    ├── Info.plist                    # Privacy permissions
    ├── Assets.xcassets/              # App icon and accent color
    ├── Models/
    │   ├── Session.swift             # SwiftData model: one per photo session
    │   ├── Spot.swift                # SwiftData model: one per tracked spot
    │   └── SpotMeasurement.swift     # SwiftData model: spot measurement per session
    ├── Services/
    │   ├── ImageProcessor.swift      # Core analysis engine (Vision + CoreImage + LAB)
    │   └── VideoFrameExtractor.swift # Best-frame extraction from video
    └── Views/
        ├── ContentView.swift         # Tab bar root view
        ├── CaptureView.swift         # Photo/video import + treatment form
        ├── SpotMapView.swift         # Face photo with spot overlays + history
        ├── SessionsListView.swift    # All sessions list with swipe-to-delete
        ├── ProgressView.swift        # Charts: total area + per-spot trends
        └── CompareView.swift         # Side-by-side session comparison + deltas
```
