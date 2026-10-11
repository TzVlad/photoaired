class EditorState {
  // A. Tone & Exposure (Light)
  final double exposure;
  final double contrast;
  final double highlights;
  final double shadows;
  final double whites;
  final double blacks;

  // B. Color & Chrominance
  final double temperature;
  final double tint;
  final double saturation;
  final double vibrance;
  final double colorGradingShadowHue;
  final double colorGradingHighlightHue;

  // C. Texture & Detail
  final double clarity;
  final double sharpness;
  final double grain;

  // D. Spatial Shading / Radial Mask
  final double vignetteAmount;
  final double vignetteRadius;
  final double vignetteFeather;
  final double maskCenterX;
  final double maskCenterY;
  final double maskAspectRatio;
  final bool showMaskOverlay;

  const EditorState({
    this.exposure = 0.0,
    this.contrast = 1.0,
    this.highlights = 0.0,
    this.shadows = 0.0,
    this.whites = 0.0,
    this.blacks = 0.0,
    this.temperature = 0.0,
    this.tint = 0.0,
    this.saturation = 1.0,
    this.vibrance = 0.0,
    this.colorGradingShadowHue = 0.0,
    this.colorGradingHighlightHue = 0.0,
    this.clarity = 0.0,
    this.sharpness = 0.0,
    this.grain = 0.0,
    this.vignetteAmount = 0.0,
    this.vignetteRadius = 0.8,
    this.vignetteFeather = 0.6,
    this.maskCenterX = 0.5,
    this.maskCenterY = 0.5,
    this.maskAspectRatio = 1.0,
    this.showMaskOverlay = false,
  });

  EditorState copyWith({
    double? exposure,
    double? contrast,
    double? highlights,
    double? shadows,
    double? whites,
    double? blacks,
    double? temperature,
    double? tint,
    double? saturation,
    double? vibrance,
    double? colorGradingShadowHue,
    double? colorGradingHighlightHue,
    double? clarity,
    double? sharpness,
    double? grain,
    double? vignetteAmount,
    double? vignetteRadius,
    double? vignetteFeather,
    double? maskCenterX,
    double? maskCenterY,
    double? maskAspectRatio,
    bool? showMaskOverlay,
  }) {
    return EditorState(
      exposure: exposure ?? this.exposure,
      contrast: contrast ?? this.contrast,
      highlights: highlights ?? this.highlights,
      shadows: shadows ?? this.shadows,
      whites: whites ?? this.whites,
      blacks: blacks ?? this.blacks,
      temperature: temperature ?? this.temperature,
      tint: tint ?? this.tint,
      saturation: saturation ?? this.saturation,
      vibrance: vibrance ?? this.vibrance,
      colorGradingShadowHue: colorGradingShadowHue ?? this.colorGradingShadowHue,
      colorGradingHighlightHue: colorGradingHighlightHue ?? this.colorGradingHighlightHue,
      clarity: clarity ?? this.clarity,
      sharpness: sharpness ?? this.sharpness,
      grain: grain ?? this.grain,
      vignetteAmount: vignetteAmount ?? this.vignetteAmount,
      vignetteRadius: vignetteRadius ?? this.vignetteRadius,
      vignetteFeather: vignetteFeather ?? this.vignetteFeather,
      maskCenterX: maskCenterX ?? this.maskCenterX,
      maskCenterY: maskCenterY ?? this.maskCenterY,
      maskAspectRatio: maskAspectRatio ?? this.maskAspectRatio,
      showMaskOverlay: showMaskOverlay ?? this.showMaskOverlay,
    );
  }

  factory EditorState.fromJson(Map<String, dynamic> json) {
    double clamp(dynamic val, double min, double max, double def) {
      if (val == null) return def;
      double v = (val is num) ? val.toDouble() : def;
      if (v < min) return min;
      if (v > max) return max;
      return v;
    }

    return EditorState(
      exposure: clamp(json['exposure'], -2.0, 2.0, 0.0),
      contrast: clamp(json['contrast'], 0.5, 2.0, 1.0),
      highlights: clamp(json['highlights'], -1.0, 1.0, 0.0),
      shadows: clamp(json['shadows'], -1.0, 1.0, 0.0),
      whites: clamp(json['whites'], -1.0, 1.0, 0.0),
      blacks: clamp(json['blacks'], -1.0, 1.0, 0.0),
      temperature: clamp(json['temperature'], -1.0, 1.0, 0.0),
      tint: clamp(json['tint'], -1.0, 1.0, 0.0),
      saturation: clamp(json['saturation'], 0.0, 2.0, 1.0),
      vibrance: clamp(json['vibrance'], -1.0, 1.0, 0.0),
      colorGradingShadowHue: clamp(json['color_grading_shadow_hue'], 0.0, 360.0, 0.0),
      colorGradingHighlightHue: clamp(json['color_grading_highlight_hue'], 0.0, 360.0, 0.0),
      clarity: clamp(json['clarity'], -1.0, 1.0, 0.0),
      sharpness: clamp(json['sharpness'], 0.0, 1.0, 0.0),
      grain: clamp(json['grain'], 0.0, 1.0, 0.0),
      vignetteAmount: clamp(json['vignetteAmount'] ?? json['vignette_amount'], -1.0, 1.0, 0.0),
      vignetteRadius: clamp(json['vignetteRadius'] ?? json['vignette_radius'], 0.1, 1.5, 0.8),
      vignetteFeather: clamp(json['vignetteFeather'] ?? json['vignette_feather'], 0.0, 1.0, 0.6),
      maskCenterX: clamp(json['maskCenterX'] ?? json['mask_center_x'], 0.0, 1.0, 0.5),
      maskCenterY: clamp(json['maskCenterY'] ?? json['mask_center_y'], 0.0, 1.0, 0.5),
      maskAspectRatio: clamp(json['maskAspectRatio'] ?? json['mask_aspect_ratio'], 0.5, 2.0, 1.0),
    );
  }

  Map<String, dynamic> toJson() => {
        'exposure': exposure,
        'contrast': contrast,
        'highlights': highlights,
        'shadows': shadows,
        'whites': whites,
        'blacks': blacks,
        'temperature': temperature,
        'tint': tint,
        'saturation': saturation,
        'vibrance': vibrance,
        'color_grading_shadow_hue': colorGradingShadowHue,
        'color_grading_highlight_hue': colorGradingHighlightHue,
        'clarity': clarity,
        'sharpness': sharpness,
        'grain': grain,
        'vignette_amount': vignetteAmount,
        'vignette_radius': vignetteRadius,
        'vignette_feather': vignetteFeather,
        'mask_center_x': maskCenterX,
        'mask_center_y': maskCenterY,
        'mask_aspect_ratio': maskAspectRatio,
      };
}
