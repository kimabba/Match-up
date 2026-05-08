# Tennis Ball Speed Measurement Feature - Technical Feasibility Report

**Date**: 2026-02-25
**Scope**: Flutter mobile app with real-time and video analysis modes
**Confidence Level**: High (based on published research, open-source implementations, and commercial precedent)

---

## Executive Summary

Building a tennis ball speed measurement feature in a Flutter app is **technically feasible but significantly challenging** for an indie developer. The core problem -- detecting a small, fast-moving object from a single phone camera and converting pixel displacement to real-world speed -- has been solved in research and commercial products, but the gap between "works in a paper" and "works reliably on-device" is substantial.

**Bottom line**: A video analysis mode (post-processing recorded slow-mo video) is achievable for an MVP. Real-time mode at acceptable accuracy requires considerable native platform work and is closer to a v2.0 feature.

---

## 1. Computer Vision for Ball Tracking

### 1.1 Algorithms and Models

Three main approaches exist, each with distinct trade-offs:

**A. Classical CV (OpenCV-based)**
- Color-based detection (HSV filtering for yellow-green tennis ball) + contour detection
- OpenCV CSRT/KCF trackers for frame-to-frame tracking
- Pros: Lightweight, no ML model needed, fast inference
- Cons: Fragile under varying lighting, fails with motion blur, high false-positive rate

**B. TrackNet (Deep Learning, Purpose-Built)**
- Heatmap-based CNN specifically designed for tennis/badminton ball tracking
- Takes 3 consecutive frames (640x360) as input, outputs detection heatmap
- Performance: 99.7% precision, 97.3% recall, 98.5% F1 on broadcast video
- Architecture: Modified VGG16-based encoder-decoder
- Problem: Designed for GPU inference, not optimized for mobile. Model size ~30MB before quantization. No official TFLite/ONNX export available.
- Source: [TrackNet paper (arXiv:1907.03698)](https://arxiv.org/abs/1907.03698)

**C. YOLO-based Detection (Most Practical for Mobile)**
- YOLOv5/v8 nano models custom-trained on tennis ball datasets
- YOLOv8n TFLite: ~6MB model, sub-30ms inference on modern phones with GPU delegate
- YOLOv5-based tennis detection achieved 94% mAP
- Roboflow has pre-labeled tennis ball datasets available
- Best option for mobile deployment due to size/speed tradeoff
- Source: [Tennis ball detection with YOLOv5](https://www.nature.com/articles/s41598-025-06365-3)

### 1.2 Accuracy: Phone Camera vs. Professional Systems

| System | Method | Accuracy | Cost |
|--------|--------|----------|------|
| Hawk-Eye | 8-10 cameras at 1000fps | Sub-centimeter | $50K+ |
| TrackMan radar | Doppler radar | +/- 1 km/h | $15K+ |
| Handheld radar gun | Doppler radar | +/- 1-2 km/h | $100-400 |
| SwingVision (phone) | Single camera CV | ~20% lower than radar (averages trajectory) | $150/year |
| Phone camera MVP | Single camera CV | +/- 15-30% estimated | Development cost |

**Key insight**: SwingVision, the best-in-class phone-based solution, explicitly states its readings are ~20% lower than radar because it measures average flight speed rather than peak speed off the racket. A phone-based MVP will inherently face this same limitation.

### 1.3 Frame Rate Impact on Accuracy

This is the single most important hardware constraint:

| Frame Rate | Time Between Frames | Ball Travel at 150 km/h | Usability |
|------------|---------------------|--------------------------|-----------|
| 30 fps | 33.3 ms | 1.39 m | Ball moves too far; often invisible between frames |
| 60 fps | 16.7 ms | 0.69 m | Marginal; heavy motion blur |
| 120 fps | 8.3 ms | 0.35 m | Minimum viable for tracking |
| 240 fps | 4.2 ms | 0.17 m | Good accuracy; recommended minimum |

**At 30fps, a serve at 200 km/h travels 1.85m between frames -- the ball may not appear in the frame at all.** This makes 30fps essentially unusable for fast shots. 240fps slow-motion is the practical minimum for reliable speed measurement.

---

## 2. Speed Calculation Methods

### 2.1 Pixel Displacement to Real-World Speed

The fundamental formula:

```
speed (m/s) = (pixel_displacement * real_world_scale) / time_between_frames
speed (km/h) = speed (m/s) * 3.6
```

Where `real_world_scale` = meters per pixel, derived from calibration.

### 2.2 Calibration Requirements

**Method A: Court Line Homography (Most Robust)**

1. Detect tennis court keypoints (line intersections) using a CNN (ResNet50-based models exist)
2. Compute homography matrix H mapping image coordinates to real-world court coordinates
3. Tennis court has known dimensions (23.77m x 10.97m doubles), providing ground-truth reference
4. Ball position in image -> multiply by inverse homography -> real-world position
5. Distance between positions in consecutive frames / time = speed

Open-source implementations:
- [TennisCourtDetector](https://github.com/yastrebksv/TennisCourtDetector) -- ResNet50-based keypoint detection
- [CourtCheck](https://github.com/AggieSportsAnalytics/CourtCheck) -- Court boundary + ball tracking
- [Tennis3DTracker](https://github.com/John-Boccio/Tennis3DTracker) -- Single-view calibration + 3D estimation

**Method B: Known Reference Object (Simpler but Less Accurate)**

1. User places a reference object of known size in the frame (e.g., racket length ~68.5cm)
2. Compute pixels-per-meter from the reference
3. Assumes the ball stays roughly at the same depth as the reference
4. Error: Does not account for perspective distortion or depth changes

**Method C: Dual-Camera Stereo (Most Accurate, Most Complex)**

1. Two phones recording simultaneously from different angles
2. Triangulate 3D position from both views
3. Stanford research achieved 0.5m average position error
4. Impractical for casual users
5. Source: [Stanford EE367 project](http://stanford.edu/class/ee367/Winter2018/fazio_fisher_fujinami_ee367_win18_report.pdf)

### 2.3 Major Error Sources

1. **Depth ambiguity**: Single camera cannot distinguish ball moving toward/away from camera vs. laterally. A ball moving directly at the camera appears stationary in 2D.
2. **Non-planar motion**: Homography maps to ground plane, but the ball travels through 3D space (arcs, topspin). This introduces systematic error.
3. **Rolling shutter**: Phone cameras use rolling shutter, introducing spatial distortion on fast-moving objects.
4. **Motion blur**: Even at 240fps, fast serves produce motion blur that shifts the detected centroid.

### 2.4 Research Papers

- [Automated Tennis Player and Ball Tracking with Court Keypoints (2024)](https://arxiv.org/html/2511.04126v1) -- Complete pipeline: YOLO + court keypoints + homography + speed
- [TennisEye: Speed Estimation using Racket-mounted Sensor](https://gzhou.pages.wm.edu/wp-content/blogs.dir/5736/files/sites/13/2017/12/TennisEye_IPSN2019.pdf) -- Alternative IMU-based approach
- [Real-time tracking of table tennis ball with low-speed camera](https://www.tandfonline.com/doi/full/10.1080/21642583.2018.1450167) -- Demonstrates ML-based tracking at low fps

---

## 3. Mobile Implementation

### 3.1 ML/CV Frameworks for Flutter

| Framework | Platform | Flutter Support | Strengths | Weaknesses |
|-----------|----------|----------------|-----------|------------|
| TensorFlow Lite (LiteRT) | Android + iOS | `tflite_flutter` package | GPU/NNAPI/Metal delegates, mature ecosystem | TF 2.20+ deprecated tf.lite in favor of LiteRT |
| Google ML Kit | Android + iOS | `google_mlkit_*` packages | Easy integration, pre-built models | No custom model support for object detection |
| MediaPipe | Android + iOS | Limited Flutter support | Box tracking, efficient pipeline | Object detection subsamples to 0.5fps |
| Core ML (iOS only) | iOS | Platform channel required | Neural Engine acceleration, best iOS perf | iOS only, requires Swift bridge |
| ONNX Runtime | Android + iOS | `onnxruntime_flutter` | Cross-platform, YOLO export support | Less mature Flutter ecosystem |

**Recommendation**: `tflite_flutter` with a YOLOv8n model exported to TFLite format. Use GPU delegate on Android, Metal delegate on iOS. Fall back to NNAPI/XNNPack where needed.

### 3.2 Real-Time Performance on Modern Phones

**Inference Pipeline (per frame):**
1. Camera frame capture: ~1-2ms
2. Image preprocessing (resize to 640x640, normalize): ~2-5ms
3. YOLO inference (YOLOv8n, GPU delegate): ~15-30ms
4. Post-processing (NMS, coordinate extraction): ~1-2ms
5. Speed calculation: ~<1ms
6. **Total: ~20-40ms per frame**

**At 30fps** (33ms budget): Tight but possible with YOLOv8n + GPU delegate
**At 60fps** (16.7ms budget): Marginal; may drop frames
**At 120/240fps**: Cannot run inference on every frame. Must subsample.

**Device benchmarks (YOLOv8n TFLite):**
- iPhone 14 Pro (A16): ~15-20ms with CoreML/Metal delegate
- iPhone 15 Pro (A17 Pro): ~10-15ms
- Galaxy S23 (Snapdragon 8 Gen 2): ~20-30ms with GPU delegate
- Galaxy S24 (Snapdragon 8 Gen 3): ~15-25ms

These are approximate values based on community benchmarks and Ultralytics documentation. Actual performance depends on image resolution, quantization level (FP16 vs INT8), and concurrent processes.

### 3.3 Processing Architecture for Video Analysis Mode

For recorded slow-motion video (240fps), real-time inference is not required:

```
Video File (240fps)
  |
  v
Frame Extraction (every frame or subsample to 120fps)
  |
  v
Ball Detection (YOLOv8n, batch process)
  |
  v
Trajectory Smoothing (Kalman filter / polynomial fit)
  |
  v
Court Detection (run once on first frame)
  |
  v
Homography Computation
  |
  v
Speed Calculation per segment
  |
  v
Results Display
```

This is significantly more feasible because:
- No real-time constraint
- Can process frames in background
- Can use larger/more accurate models
- Can apply trajectory smoothing across many frames
- User tolerance for processing time (5-30 seconds acceptable)

---

## 4. Existing Solutions and Prior Art

### 4.1 Commercial Apps

**SwingVision** (Best-in-class)
- Platform: iOS only (Apple exclusive)
- Technology: Core ML on Neural Engine, proprietary CNN models
- Features: Ball tracking, speed, placement, automated line calling, scoring
- Accuracy: Claims 10% for speed, 5% for placement. Peer-reviewed ICC of 0.76-0.80 for speed.
- Speed measurement: Averages over flight path (~20% below radar peak speed)
- Founded by ex-Tesla CV engineer
- Price: $149.99/year
- Source: [Apple Newsroom](https://www.apple.com/newsroom/2022/05/swupnil-sahai-and-his-co-founder-serve-an-ace-with-ai-powered-swingvision/)

**Baseline Vision**
- Uses external camera hardware + phone app
- Provides shot tracking and speed measurement
- Hardware dependency limits pure phone-based comparison

**HomeCourt** (Basketball-focused, acquired by NEX Team)
- Similar CV technology but basketball-specific
- Demonstrates feasibility of phone-based sports analytics

**Sony Smart Tennis Sensor**
- IMU-based (racket-mounted accelerometer)
- Measures swing speed, not ball speed
- Open SDK available: [github.com/sony/smarttennissensorsdk](https://github.com/sony/smarttennissensorsdk)

### 4.2 Open Source Projects

| Project | Technology | What It Does |
|---------|-----------|--------------|
| [tennis_analysis](https://github.com/abdullahtarek/tennis_analysis) | YOLOv8 + ResNet50 + OpenCV | Player tracking, ball speed, court keypoints |
| [tennis-tracking](https://github.com/ArtLabss/tennis-tracking) | Python, Monocular HawkEye | Ball tracking + speed from single camera |
| [Tennis3DTracker](https://github.com/John-Boccio/Tennis3DTracker) | OpenCV + single-view calibration | 3D position estimation from one camera |
| [tennis_serve_speed](https://github.com/hanssun123/tennis_serve_speed) | OpenCV CSRT tracker | Serve speed from 240fps video |
| [TennisProject](https://github.com/yastrebksv/TennisProject) | TrackNet + YOLO + court detector | Full analysis pipeline |
| [TRACE](https://github.com/hgupt3/TRACE) | Multi-model pipeline | Top-view reconstruction from single feed |
| [Tennis-Serve-Analysis](https://github.com/adeeteya/Tennis-Serve-Analysis) | ML + CV (Flutter!) | Mobile serve analysis app |

The `Tennis-Serve-Analysis` project on GitHub is particularly relevant -- it's a Flutter app doing tennis serve analysis with ML/CV.

---

## 5. Realistic Assessment

### 5.1 Feasibility Matrix

| Feature | Difficulty | MVP Feasible? | Notes |
|---------|-----------|---------------|-------|
| Video analysis (240fps pre-recorded) | Medium-High | Yes | Process offline, no real-time constraint |
| Video analysis (30fps standard video) | Very High | No | Insufficient temporal resolution |
| Real-time speed display (30fps preview) | Very High | Marginal | Frame rate too low for accuracy |
| Real-time speed display (120fps) | High | Possible on iOS | Flutter camera plugin limitations |
| Court auto-calibration | High | Yes (with constraints) | Requires visible court lines |
| Manual calibration (user marks reference) | Medium | Yes | Simpler, less accurate |

### 5.2 Minimum Viable Approach

**Recommended MVP (Video Analysis Mode Only):**

1. User records serve/rally using phone's native slow-motion camera (240fps)
2. User imports the video into the app
3. App processes the video:
   a. Detect court keypoints on first clear frame (ResNet50 or manual marking)
   b. Compute homography to standard court dimensions
   c. Run YOLOv8n ball detection on each frame (batch, not real-time)
   d. Track ball trajectory across frames (Kalman filter)
   e. Calculate speed between consecutive detections
   f. Apply trajectory smoothing
4. Display results: peak speed, average speed, trajectory overlay

**Why this is the simplest viable path:**
- No real-time processing pressure
- 240fps provides adequate temporal resolution
- Can use the phone's optimized native camera app for recording
- Batch processing allows larger models and multi-pass approaches
- Can show a processing progress indicator (user expects to wait)

**Estimated accuracy**: +/- 10-20% vs radar gun, depending on camera angle and court visibility. This is comparable to SwingVision's accuracy range.

### 5.3 Development Effort Estimate

| Component | Estimated Time | Skills Required |
|-----------|---------------|----------------|
| YOLOv8n model training on tennis ball data | 1-2 weeks | Python, PyTorch, dataset curation |
| TFLite model export and Flutter integration | 1 week | TFLite, Dart |
| Video frame extraction pipeline | 1 week | FFmpeg or platform APIs |
| Court keypoint detection (using existing model) | 1-2 weeks | Transfer learning, TFLite |
| Homography + speed calculation | 1 week | Linear algebra, OpenCV |
| Trajectory smoothing (Kalman filter) | 3-5 days | Signal processing basics |
| UI for video selection + results display | 1-2 weeks | Flutter |
| Testing and calibration tuning | 2-3 weeks | Patience |
| **Total MVP (video mode)** | **~8-12 weeks** | |
| Add real-time mode | **+8-16 weeks** | Native platform expertise |

### 5.4 Major Limitations and Gotchas

1. **Camera angle matters enormously**: Side-on views (perpendicular to ball flight) give best accuracy. Head-on views make speed unmeasurable in 2D.

2. **Court must be visible**: Without court lines for calibration, there's no reliable way to convert pixels to meters. Indoor courts with different line colors, clay courts with obscured lines, and courts at extreme angles all cause failures.

3. **Single camera depth problem**: Speed measurements are only accurate for ball motion perpendicular to the camera axis. Motion toward/away from the camera is invisible in 2D projection.

4. **Flutter camera plugin limitations**: The standard `camera` package does NOT support 120/240fps capture. Recording at high frame rates requires:
   - Using the phone's native camera app and importing the video (simplest)
   - Writing a native plugin in Swift (AVCaptureDevice with high-speed format) and Kotlin (CameraX setSlowMotionEnabled)
   - The `camerawesome` package may offer better frame rate control but still has limitations

5. **Battery and thermal**: Real-time inference at 30fps continuously will drain battery and heat up the phone. 15-20 minutes of continuous processing is a reasonable limit.

6. **SwingVision has a 5+ year head start**: Their models are trained on millions of frames. An indie MVP will not match their accuracy, and that should be set as a clear expectation.

7. **Motion blur at low fps**: Even with detection, motion blur shifts the apparent center of the ball, introducing systematic bias in position estimation.

8. **Variable ball size in frame**: A tennis ball is 6.7cm diameter. At 5m distance, it is ~35 pixels wide on a 1080p frame. At 15m, it is ~12 pixels. At 25m+, it may be <8 pixels -- below reliable detection threshold for most models.

---

## 6. Flutter-Specific Technical Details

### 6.1 Camera Plugins

| Plugin | High FPS | Frame Streaming | Platform | Notes |
|--------|----------|----------------|----------|-------|
| `camera` (official) | No (30fps only, [open issue #125683](https://github.com/flutter/flutter/issues/125683)) | Yes (image stream) | iOS + Android | Cannot access 120/240fps modes |
| `camerawesome` | Limited | Yes | iOS + Android | Better quality control, still limited fps |
| Native plugin (custom) | Yes | Yes | Per-platform | Full access to AVCaptureDevice / CameraX |
| Use native camera + import | N/A | N/A | Both | Simplest approach for video mode |

**For video analysis mode**: Use the `image_picker` or `file_picker` package to select pre-recorded slow-mo videos. This sidesteps all camera plugin limitations.

**For real-time mode**: A custom platform channel to Swift/Kotlin is unavoidable. Flutter's camera plugin does not expose high frame rate configuration.

### 6.2 Video Processing in Flutter

| Package | Purpose | Notes |
|---------|---------|-------|
| `video_player` | Playback | Cannot extract individual frames efficiently |
| `ffmpeg_kit_flutter` | Frame extraction, transcoding | Can extract frames from slow-mo video at full fps |
| `image` (Dart) | Image manipulation | CPU-based, slow for large batches |
| Native FFI to OpenCV | Frame processing | Requires C++ bridge via Dart FFI |

**Recommended pipeline for video mode:**
1. `ffmpeg_kit_flutter` to extract frames from slow-mo video
2. `tflite_flutter` to run YOLOv8n on extracted frames
3. Dart code for homography computation and speed calculation
4. Flutter UI for result visualization

### 6.3 Native Code Integration

For real-time mode, you will need platform channels:

**iOS (Swift)**:
- AVCaptureDevice with `activeFormat` supporting 120/240fps
- Run Core ML or TFLite inference on captured CMSampleBuffer
- Send results back to Flutter via EventChannel
- Apple's Neural Engine provides best inference performance

**Android (Kotlin)**:
- CameraX 1.5+ with `setSlowMotionEnabled(true)` for high-speed capture
- TFLite with GPU delegate or NNAPI delegate
- Send results via EventChannel

**Communication options:**
- Method Channel: Simple request/response
- Event Channel: Streaming results (preferred for continuous inference)
- Dart FFI: Direct C/C++ calls, lowest latency, highest complexity
- Pigeon: Type-safe code generation for platform channels

---

## 7. Recommended Technology Stack for MVP

### Phase 1: Video Analysis Mode (MVP)

```
Recording:       Phone's native slow-mo camera (240fps)
Video Import:    image_picker / file_picker
Frame Extract:   ffmpeg_kit_flutter
Ball Detection:  YOLOv8n (TFLite via tflite_flutter, GPU delegate)
Court Detection: ResNet50 keypoint model (TFLite) OR manual marking
Calibration:     OpenCV homography (via dart:ffi to C++ or pure Dart implementation)
Tracking:        Simple nearest-neighbor + Kalman filter in Dart
Speed Calc:      Pure Dart math
UI:              Flutter standard widgets + CustomPaint for trajectory overlay
```

### Phase 2: Real-Time Mode (Future)

```
Camera:          Custom native plugin (Swift AVCaptureDevice / Kotlin CameraX)
Inference:       Core ML on iOS, TFLite GPU on Android
Communication:   EventChannel streaming inference results to Flutter
Display:         Flutter overlay on camera preview
```

---

## 8. Conclusions

### What is feasible:
- Video analysis mode processing 240fps slow-mo recordings
- Ball detection using YOLOv8n on TFLite with reasonable accuracy
- Speed estimation with +/-10-20% accuracy under good conditions (side-on view, visible court lines, 240fps)
- Running on iPhone 14+ and Galaxy S23+ class hardware

### What is challenging but possible:
- Real-time mode at 30fps with reduced accuracy
- Automatic court calibration without user interaction
- Cross-platform consistency between iOS and Android

### What is not feasible for an indie MVP:
- Matching professional radar gun accuracy (+/- 1 km/h)
- Matching SwingVision's accuracy without years of model training data
- Real-time processing at 120/240fps (even SwingVision processes at lower effective rates)
- Accurate speed measurement from arbitrary camera angles

### Recommended path forward:
1. Start with video analysis of pre-recorded 240fps video
2. Use court line homography for calibration (with manual fallback)
3. Use YOLOv8n for ball detection
4. Set honest accuracy expectations with users ("estimated speed, not radar-grade")
5. Consider real-time mode only after video mode is validated

---

## Sources

### Research Papers
- [TrackNet: Deep Learning for Tracking High-speed Objects (arXiv:1907.03698)](https://arxiv.org/abs/1907.03698)
- [Tennis Ball Tracking: 3D Trajectory Estimation using Smartphone Videos (Stanford)](http://stanford.edu/class/ee367/Winter2018/fazio_fisher_fujinami_ee367_win18_report.pdf)
- [Tennis ball detection based on YOLOv5 with TensorRT (Nature Scientific Reports)](https://www.nature.com/articles/s41598-025-06365-3)
- [Automated Tennis Player and Ball Tracking with Court Keypoints](https://arxiv.org/html/2511.04126v1)
- [TennisEye: Ball Speed Estimation using Racket-mounted Motion Sensor](https://gzhou.pages.wm.edu/wp-content/blogs.dir/5736/files/sites/13/2017/12/TennisEye_IPSN2019.pdf)
- [Real-time tracking of table tennis ball with low-speed camera](https://www.tandfonline.com/doi/full/10.1080/21642583.2018.1450167)
- [Concurrent Validity of Mobile Application for Tracking Tennis Performance (MDPI)](https://www.mdpi.com/2076-3417/13/10/6195)
- [Camera Calibration in Sports with Keypoints (Roboflow)](https://blog.roboflow.com/camera-calibration-sports-computer-vision/)
- [Fast moving table tennis ball tracking with GNN (Nature)](https://www.nature.com/articles/s41598-024-80056-3)

### Commercial Products
- [SwingVision](https://swing.vision/)
- [SwingVision - Apple Newsroom](https://www.apple.com/newsroom/2022/05/swupnil-sahai-and-his-co-founder-serve-an-ace-with-ai-powered-swingvision/)
- [SwingVision Review - Tennis.com](https://www.tennis.com/baseline/articles/swingvision-delivers-pro-level-insights-for-recreational-players)
- [SwingVision Review - Gravity Tennis](https://www.gravitytennis.com/blog/swingvision-review)
- [Baseline Vision - Top Tennis Tracking Systems](https://www.baselinevision.com/blog/top-5-tennis-tracking-systems-to-improve-your-game)

### Flutter/Mobile Development
- [tflite_flutter package](https://pub.dev/packages/tflite_flutter)
- [Flutter Camera Plugin](https://pub.dev/packages/camera)
- [Flutter Camera Plugin High FPS Issue #125683](https://github.com/flutter/flutter/issues/125683)
- [LiteRT (TFLite) in Flutter - Object Detection](https://medium.com/simform-engineering/litert-tensorflow-lite-in-flutter-implementing-live-object-detection-part-1-d060d33d6e33)
- [Flutter Camera + Vision Models Real-Time Object Detection](https://dasroot.net/posts/2025/12/flutter-camera-vision-models-real-time-object-detection/)
- [TFLite GPU Delegate Documentation](https://www.tensorflow.org/lite/performance/gpu)
- [Android CameraX 1.5 High-Speed Capture](https://android-developers.googleblog.com/2025/10/high-speed-capture-and-slow-motion.html)
- [Flutter OpenCV Plugin Tutorial (Scanbot)](https://scanbot.io/techblog/implementing-a-flutter-plugin-with-native-opencv-support-via-dartffi-part-1-2/)

### Open Source Projects
- [tennis_analysis (YOLO + court keypoints + speed)](https://github.com/abdullahtarek/tennis_analysis)
- [tennis-tracking (Monocular HawkEye)](https://github.com/ArtLabss/tennis-tracking)
- [Tennis3DTracker (single-view calibration)](https://github.com/John-Boccio/Tennis3DTracker)
- [tennis_serve_speed (OpenCV tracker)](https://github.com/hanssun123/tennis_serve_speed)
- [TennisProject (TrackNet + YOLO)](https://github.com/yastrebksv/TennisProject)
- [TennisCourtDetector (court keypoint CNN)](https://github.com/yastrebksv/TennisCourtDetector)
- [Tennis-Serve-Analysis (Flutter app)](https://github.com/adeeteya/Tennis-Serve-Analysis)
- [TRACE (top-view reconstruction)](https://github.com/hgupt3/TRACE)
- [CourtCheck (court boundary + ball)](https://github.com/AggieSportsAnalytics/CourtCheck)
- [Ball Tracking with OpenCV (PyImageSearch)](https://pyimagesearch.com/2015/09/14/ball-tracking-with-opencv/)
