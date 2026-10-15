class AdjustmentMask {
  final String id;
  final String name;
  final double centerX; // 0.0 .. 1.0
  final double centerY; // 0.0 .. 1.0
  final double radius;  // 0.05 .. 1.0
  final double feather; // 0.05 .. 1.0
  final double exposure;// -1.0 .. 1.0
  final bool isInverted;

  const AdjustmentMask({
    required this.id,
    required this.name,
    this.centerX = 0.5,
    this.centerY = 0.5,
    this.radius = 0.5,
    this.feather = 0.5,
    this.exposure = 0.0,
    this.isInverted = false,
  });

  AdjustmentMask copyWith({
    String? id,
    String? name,
    double? centerX,
    double? centerY,
    double? radius,
    double? feather,
    double? exposure,
    bool? isInverted,
  }) {
    return AdjustmentMask(
      id: id ?? this.id,
      name: name ?? this.name,
      centerX: centerX ?? this.centerX,
      centerY: centerY ?? this.centerY,
      radius: radius ?? this.radius,
      feather: feather ?? this.feather,
      exposure: exposure ?? this.exposure,
      isInverted: isInverted ?? this.isInverted,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'centerX': centerX,
      'centerY': centerY,
      'radius': radius,
      'feather': feather,
      'exposure': exposure,
      'isInverted': isInverted,
    };
  }

  factory AdjustmentMask.fromMap(Map<String, dynamic> map) {
    double clamp(dynamic val, double min, double max, double def) {
      if (val == null) return def;
      double v = (val is num) ? val.toDouble() : def;
      if (v < min) return min;
      if (v > max) return max;
      return v;
    }

    return AdjustmentMask(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      centerX: clamp(map['centerX'], 0.0, 1.0, 0.5),
      centerY: clamp(map['centerY'], 0.0, 1.0, 0.5),
      radius: clamp(map['radius'], 0.05, 1.0, 0.5),
      feather: clamp(map['feather'], 0.05, 1.0, 0.5),
      exposure: clamp(map['exposure'], -1.0, 1.0, 0.0),
      isInverted: map['isInverted'] ?? false,
    );
  }
}

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
  final List<AdjustmentMask> masks;
  final int selectedMaskIndex;
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
    this.masks = const [],
    this.selectedMaskIndex = -1,
    this.showMaskOverlay = true,
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
    List<AdjustmentMask>? masks,
    int? selectedMaskIndex,
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
      masks: masks ?? this.masks,
      selectedMaskIndex: selectedMaskIndex ?? this.selectedMaskIndex,
      showMaskOverlay: showMaskOverlay ?? this.showMaskOverlay,
    );
  }
  
  EditorState lerpTo(EditorState target, double t) {
    double lerp(double a, double b, double t) => a + (b - a) * t;
    return EditorState(
      exposure: lerp(exposure, target.exposure, t),
      contrast: lerp(contrast, target.contrast, t),
      highlights: lerp(highlights, target.highlights, t),
      shadows: lerp(shadows, target.shadows, t),
      whites: lerp(whites, target.whites, t),
      blacks: lerp(blacks, target.blacks, t),
      temperature: lerp(temperature, target.temperature, t),
      tint: lerp(tint, target.tint, t),
      saturation: lerp(saturation, target.saturation, t),
      vibrance: lerp(vibrance, target.vibrance, t),
      colorGradingShadowHue: lerp(colorGradingShadowHue, target.colorGradingShadowHue, t),
      colorGradingHighlightHue: lerp(colorGradingHighlightHue, target.colorGradingHighlightHue, t),
      clarity: lerp(clarity, target.clarity, t),
      sharpness: lerp(sharpness, target.sharpness, t),
      grain: lerp(grain, target.grain, t),
      masks: t > 0.5 ? target.masks : masks,
      selectedMaskIndex: t > 0.5 ? target.selectedMaskIndex : selectedMaskIndex,
      showMaskOverlay: t > 0.5 ? target.showMaskOverlay : showMaskOverlay,
    );
  }
  
  EditorState addMask(AdjustmentMask mask) {
    final newMasks = List<AdjustmentMask>.from(masks);
    if (newMasks.length >= 4) {
      newMasks.removeAt(0);
    }
    newMasks.add(mask);
    return copyWith(masks: newMasks, selectedMaskIndex: newMasks.length - 1);
  }

  EditorState removeMask(int index) {
    if (index < 0 || index >= masks.length) return this;
    final newMasks = List<AdjustmentMask>.from(masks)..removeAt(index);
    int newSelectedIndex = selectedMaskIndex;
    if (newSelectedIndex == index) {
      newSelectedIndex = newMasks.isNotEmpty ? newMasks.length - 1 : -1;
    } else if (newSelectedIndex > index) {
      newSelectedIndex--;
    }
    return copyWith(masks: newMasks, selectedMaskIndex: newSelectedIndex);
  }

  EditorState updateActiveMask(AdjustmentMask mask) {
    if (selectedMaskIndex < 0 || selectedMaskIndex >= masks.length) return this;
    final newMasks = List<AdjustmentMask>.from(masks);
    newMasks[selectedMaskIndex] = mask;
    return copyWith(masks: newMasks);
  }

  EditorState selectMask(int index) {
    if (index < -1 || index >= masks.length) return this;
    return copyWith(selectedMaskIndex: index);
  }

  factory EditorState.fromJson(Map<String, dynamic> json) {
    double clamp(dynamic val, double min, double max, double def) {
      if (val == null) return def;
      double v = (val is num) ? val.toDouble() : def;
      if (v < min) return min;
      if (v > max) return max;
      return v;
    }

    List<AdjustmentMask> parsedMasks = [];
    if (json['masks'] != null && json['masks'] is List) {
      parsedMasks = (json['masks'] as List).map((m) => AdjustmentMask.fromMap(m)).toList();
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
      masks: parsedMasks,
      selectedMaskIndex: json['selectedMaskIndex'] ?? (parsedMasks.isNotEmpty ? 0 : -1),
      showMaskOverlay: json['showMaskOverlay'] ?? true,
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
        'masks': masks.map((m) => m.toMap()).toList(),
        'selectedMaskIndex': selectedMaskIndex,
        'showMaskOverlay': showMaskOverlay,
      };
}
