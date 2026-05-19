# Speed Gun Rules

Load this when touching video upload/processing, ball detection, trajectory tracking, calibration, or speed calculation.

## Product principle

A wrong speed number is worse than a cautious “low confidence” result.
The feature should surface input quality and confidence boundaries clearly.

## Input quality

- Prefer high-FPS video for measurement.
- Warn below 120fps.
- Consider blocking or marking low confidence below 60fps.
- Validate video duration, resolution, and readable frame metadata before analysis.

## Calibration

- Court calibration points must be validated, not only counted.
- Reject duplicate or near-duplicate points.
- Reject degenerate quadrilaterals with too-small area.
- Calibration math should be unit-tested with known fixtures.

## Ball detection and tracking

- Mock detection is acceptable for local development, but production builds must not silently use mock detector output.
- Track detected frame count and gaps.
- Low detection coverage should lower confidence or fail analysis.

## Speed calculation

- Use deterministic fixtures for known trajectories.
- Add sanity bounds; for tennis, values outside a plausible range such as 0–300 km/h should not be shown as confident results.
- Distinguish peak speed, average speed, and confidence.
- Keep units explicit.

## Suggested tests

- `speed_calculator_test.dart` for straight-line known-distance fixtures.
- Calibration validation tests for invalid point sets.
- Detector fallback tests to ensure mock mode cannot reach production unnoticed.
- Result sanity tests for impossible speeds.
