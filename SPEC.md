# Project Specification: AI Parametric & Spatial Photo Editor

## 1. Concept & Scope
A mobile-first parametric image editor that translates natural language prompts or reference intents into deterministic visual parameters.
The AI does not repaint pixels unpredictably; instead, it outputs a strict JSON payload controlling granular grading parameters and a spatial radial vignette/shading mask. The user retains bilateral control to fine-tune every slider and mask anchor manually.

## 2. Tech Stack & Execution Constraints
- Target Framework: Flutter (preferred) or React Native / Expo.
- Processing Pipeline: Pure client-side hardware-accelerated filters (ColorFilter / ColorMatrix, Skia/Canvas Shaders, and CustomPainter overlays).
- AI Engine: Direct LLM API call (Gemini 1.5/2.x Flash) with Structured Output / JSON schema enforcement.
- Response Latency: Real-time UI rendering (<16ms per slider tick).

## 3. Parametric State Model (Full Tuning Suite)

The global state must track the following parameters, clustered into 4 logical categories:

### A. Tone & Exposure (Light)
- `exposure`: float (-2.0 to 2.0, default: 0.0) — overall exposure compensation.
- `contrast`: float (0.5 to 2.0, default: 1.0) — tonal separation.
- `highlights`: float (-1.0 to 1.0, default: 0.0) — compression of bright areas.
- `shadows`: float (-1.0 to 1.0, default: 0.0) — recovery/deepening of dark tones.
- `whites`: float (-1.0 to 1.0, default: 0.0) — extreme highlight clip point.
- `blacks`: float (-1.0 to 1.0, default: 0.0) — true black floor anchor.

### B. Color & Chrominance
- `temperature`: float (-1.0 to 1.0, default: 0.0) — cool (blue) to warm (amber) shift.
- `tint`: float (-1.0 to 1.0, default: 0.0) — green to magenta bias.
- `saturation`: float (0.0 to 2.0, default: 1.0) — uniform color intensity.
- `vibrance`: float (-1.0 to 1.0, default: 0.0) — smart skin-tone-aware saturation.
- `color_grading_shadow_hue`: float (0.0 to 360.0, default: 0.0) — split-toning hue in shadows.
- `color_grading_highlight_hue`: float (0.0 to 360.0, default: 0.0) — split-toning hue in highlights.

### C. Texture & Detail
- `clarity`: float (-1.0 to 1.0, default: 0.0) — midtone local contrast.
- `sharpness`: float (0.0 to 1.0, default: 0.0) — edge accentuation.
- `grain`: float (0.0 to 1.0, default: 0.0) — analog film simulation noise.

### D. Spatial Shading / Radial Mask (The "Red Oval" Vignette System)
- `vignette_amount`: float (-1.0 to 1.0, default: 0.0) — negative darkens periphery, positive brightens.
- `vignette_radius`: float (0.1 to 1.5, default: 0.8) — spread factor of the oval.
- `vignette_feather`: float (0.0 to 1.0, default: 0.6) — softness/blur gradient transition.
- `mask_center_x`: float (0.0 to 1.0, default: 0.5) — normalized horizontal focus anchor.
- `mask_center_y`: float (0.0 to 1.0, default: 0.5) — normalized vertical focus anchor.
- `mask_aspect_ratio`: float (0.5 to 2.0, default: 1.0) — oval eccentricity (stretch ratio).
- `show_mask_overlay`: boolean (default: false) — toggle displaying the visual red guidance oval.

## 4. UI/UX Architecture
1. **Viewfinder Canvas (Top 50-55% of viewport):**
    - High-performance image display.
    - Interactive overlay rendering the radial mask anchor: allows drag & pinch to change `mask_center_x/y` and `vignette_radius` directly by touch.
2. **Tabbed Controls Shelf (Middle 30%):**
    - Horizontal tab selector: `[Light]` | `[Color]` | `[Detail]` | `[Spatial Mask]`.
    - Vertical scrollable slider deck rendering the active tab's properties.
    - Sliders display parameter name, numerical value badge, and reset-on-double-tap trigger.
3. **Prompt & Action Bar (Bottom 15% - Keyboard-safe):**
    - Single-line expandable text input for prompt injection.
    - Attachment icon for reference image upload (stub/hook).
    - "Apply AI Grade" button with reactive loading state.

## 5. AI Service & Contract Rules
- The LLM receives the natural language prompt and current state context.
- System instruction strictly enforces outputting **ONLY** valid JSON satisfying this structure:
```json
{
  "explanation": "Short 1-sentence design rationale",
  "adjustments": {
    "exposure": 0.15,
    "contrast": 1.25,
    "highlights": -0.3,
    "shadows": 0.4,
    "whites": 0.0,
    "blacks": -0.1,
    "temperature": 0.2,
    "tint": -0.05,
    "saturation": 0.9,
    "vibrance": 0.15,
    "color_grading_shadow_hue": 210.0,
    "color_grading_highlight_hue": 45.0,
    "clarity": 0.3,
    "sharpness": 0.2,
    "grain": 0.15,
    "vignette_amount": -0.55,
    "vignette_radius": 0.7,
    "vignette_feather": 0.75,
    "mask_center_x": 0.5,
    "mask_center_y": 0.45,
    "mask_aspect_ratio": 1.2
  }
}
```
- Safe Clamping: The client-side parser must clamp all incoming numbers strictly within each slider's defined boundaries to prevent rendering artifacts or NaN crashes.
- Bidirectional reactivity: If AI sets `exposure: 0.15`, the corresponding slider physically glides to `0.15`, and the user can immediately grab and tweak it manually.

## 6. Development Guardrails
- Maintain state immutability via a clean state holder (ValueNotifier, River pod, or lightweight Bloc/Hook).
- Do not add remote database backends or complex auth schemes.
- Provide a bundled default high-contrast portrait/street photo asset for immediate testing.