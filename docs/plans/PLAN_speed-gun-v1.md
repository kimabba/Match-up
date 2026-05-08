# Speed Gun v1.1 — Video Analysis Mode MVP

**Feature**: SSF-161
**Scope**: Large (6 phases)
**Approach**: 240fps slow-mo video → frame extraction → ball detection → speed calculation

---

## Architecture

```
Video File (240fps)
  │
  ├─→ Frame Extraction (ffmpeg_kit_flutter)
  │
  ├─→ Court Calibration (user marks 4 corners → homography matrix)
  │     └─→ First frame displayed, user taps 4 court corners
  │
  ├─→ Ball Detection (YOLOv8n TFLite, batch processing)
  │     └─→ Per-frame bounding box → center point extraction
  │
  ├─→ Trajectory Tracking (nearest-neighbor + Kalman filter)
  │
  ├─→ Speed Calculation (pixel displacement × homography → real distance / time)
  │
  └─→ Results Display (peak speed, avg speed, trajectory overlay)
```

## File Structure

```
app/lib/
├── models/
│   └── speed_measurement.dart      # BallPosition, CourtCalibration, SpeedResult
├── services/
│   ├── video_processing_service.dart  # Frame extraction via ffmpeg
│   ├── ball_detector_service.dart     # TFLite YOLOv8n inference
│   └── speed_calculator.dart          # Homography + Kalman + speed math
├── screens/
│   ├── speed_gun_screen.dart          # Main: video selection + processing flow
│   ├── court_calibration_screen.dart  # Interactive 4-point court marking
│   └── speed_result_screen.dart       # Results: stats + trajectory overlay
└── widgets/
    ├── court_painter.dart             # CustomPainter: court line overlay
    └── trajectory_painter.dart        # CustomPainter: ball trajectory + speed labels
```

## Dependencies to Add

```yaml
image_picker: ^1.1.0       # Video selection from gallery
ffmpeg_kit_flutter: ^6.0.3  # Frame extraction from video
tflite_flutter: ^0.11.0     # YOLOv8n model inference
path_provider: ^2.1.0       # Temp directory for frames
```

## Phase Details

### Phase 1: Foundation — Models + Math Engine
**Goal**: Pure Dart data models and speed calculation math (no external deps)

**Files**:
- `speed_measurement.dart`: BallPosition, CourtCalibration, SpeedResult, TrajectoryPoint
- `speed_calculator.dart`: Homography matrix computation, pixel-to-real transform, Kalman filter, speed calculation

**Key Math**:
- Homography: 4-point correspondence → 3x3 matrix (DLT algorithm)
- Speed: `real_distance / frame_interval × 3.6` → km/h
- Kalman filter: smooth noisy ball positions

**Quality Gate**: Unit tests pass for homography + speed calculation

---

### Phase 2: Video Processing Pipeline
**Goal**: Select video, extract frames, read metadata

**Files**:
- `video_processing_service.dart`: VideoMeta, frame extraction, temp file management

**Flow**: Pick video → probe metadata (fps, duration, resolution) → extract frames as JPEG → return frame paths

**Quality Gate**: Can select video, frames extracted to temp dir

---

### Phase 3: Ball Detection
**Goal**: TFLite model integration for tennis ball detection

**Files**:
- `ball_detector_service.dart`: Model loading, preprocessing, inference, postprocessing (NMS)

**Model**: YOLOv8n (COCO pre-trained, "sports ball" class 32) — 6MB TFLite
**Fallback**: Mock detector for development without model file

**Quality Gate**: Can run inference on frame, return bounding boxes

---

### Phase 4: Court Calibration UI
**Goal**: Interactive 4-point court corner marking

**Files**:
- `court_calibration_screen.dart`: Full-screen frame image + tap-to-mark UI
- `court_painter.dart`: Draw court corners, lines, and perspective grid

**UX Flow**: Show first frame → user taps 4 court corners in order → preview court overlay → confirm

**Quality Gate**: 4 points selectable, court overlay renders correctly

---

### Phase 5: Main Screen + Results
**Goal**: End-to-end flow from video selection to speed results

**Files**:
- `speed_gun_screen.dart`: Entry point with video picker, processing orchestration
- `speed_result_screen.dart`: Stats display (peak/avg speed), trajectory visualization
- `trajectory_painter.dart`: Ball path with speed gradient coloring

**Quality Gate**: Complete pipeline runs, results displayed

---

### Phase 6: Integration
**Goal**: 4th tab in bottom navigation, pubspec dependencies

**Changes**:
- `pubspec.yaml`: Add 4 new dependencies
- `main.dart`: Add SpeedGunScreen as 4th tab with speed icon

**Quality Gate**: App builds, all 4 tabs work, speed gun flow complete

---

## Limitations (MVP)

- Manual court calibration only (no auto-detection)
- YOLOv8n COCO model (sports_ball class) — not custom-trained for tennis
- Side-on camera angle recommended for best accuracy
- Accuracy: +/- 15-30% vs radar gun
- Processing time: 5-30 seconds depending on video length
- 240fps video required (standard 30fps too low)

## Future (v2.0 — SSF-162)

- Real-time camera mode
- Auto court detection (ResNet50 keypoint CNN)
- Custom-trained YOLOv8n on tennis ball dataset
- 3D trajectory estimation
- Shot type classification
