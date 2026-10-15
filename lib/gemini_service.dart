import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'editor_state.dart';

class GeminiService {
  final String apiKey;

  GeminiService(this.apiKey);

  Future<EditorState?> analyzePrompt({
    required String prompt,
    required EditorState currentState,
    required Uint8List targetBytes,
    Uint8List? referenceBytes,
  }) async {
    final promptText = '''
You are a parametric image editor AI.
The user wants to edit a photo. 
Here is their intent: "$prompt"
Current state:
${jsonEncode(currentState.toJson())}

PHOTOGRAPHIC HEURISTICS & CONSTRAINTS:
1. Bolder Moody & Cinematic Grading: For requests mentioning "moody", "cinematic", "dramatic", "dark", or "low-key", do NOT leave sliders near 0.0/1.0 defaults. You MUST be decisive:
   - Deepen shadows (shadows: -0.3..-0.6)
   - Slightly lower exposure (exposure: -0.1..-0.35)
   - Boost contrast (contrast: 1.15..1.35)
   - Preserve highlights (highlights: +0.15..+0.4) so the subject pops from darkness.

2. Mandatory Spotlight / Focus Effect: If the prompt asks for focusing, accentuating, darkening edges, or spotlighting a subject ("focus", "spotlight", "darken edges", "make it pop", "center subject"), you MUST set vignette_amount decisively in the range -0.35 to -0.65.
   - CRITICAL INTERCONNECTION: target_box and vignette_radius do NOTHING by themselves unless accompanied by a noticeable vignette_amount (< -0.3). A vignette_amount > -0.15 for a focus/spotlight request is considered an ERROR.

3. Clipping Prevention: CRITICAL - Never drop exposure, highlights, and whites to extreme negative values simultaneously (-1.0).

4. Spatial Composition Analysis: Analyze the TARGET image. If the prompt implies focusing on, highlighting, or accentuating a specific subject, you MUST return its normalized bounding box as [ymin, xmin, ymax, xmax] tightly hugging the object in "target_box". If no specific focus is requested, set "target_box": null.
${referenceBytes != null ? """5. Reference Style Transfer: You have been provided with TWO images. The FIRST image is the TARGET. The SECOND image is the REFERENCE.
- Evaluate the dynamic range and lighting of the TARGET image.
- Evaluate the color palette, shadows, contrast, and color temperature of the REFERENCE image.
- Adapt the artistic style of the REFERENCE image to the physical lighting conditions of the TARGET image.
- Calculate and output the sliders needed to achieve this style transfer on the TARGET image.""" : ""}

Output ONLY a valid JSON object matching this schema exactly:
{
  "explanation": "Short rationale",
  "target_box": [0.0, 0.0, 1.0, 1.0],
  "adjustments": {
    "exposure": 0.0,
    "contrast": 1.0,
    "highlights": 0.0,
    "shadows": 0.0,
    "whites": 0.0,
    "blacks": 0.0,
    "temperature": 0.0,
    "tint": 0.0,
    "saturation": 1.0,
    "vibrance": 0.0,
    "color_grading_shadow_hue": 0.0,
    "color_grading_highlight_hue": 0.0,
    "clarity": 0.0,
    "sharpness": 0.0,
    "grain": 0.0,
    "vignette_amount": 0.0,
    "vignette_radius": 0.8,
    "vignette_feather": 0.6,
    "mask_center_x": 0.5,
    "mask_center_y": 0.5,
    "mask_aspect_ratio": 1.0
  }
}
Return only the raw JSON. No markdown code blocks.
''';

    final parts = <Map<String, dynamic>>[
      {"text": promptText},
      {
        "inlineData": {
          "mimeType": "image/jpeg",
          "data": base64Encode(targetBytes),
        }
      }
    ];

    if (referenceBytes != null) {
      parts.add({
        "inlineData": {
          "mimeType": "image/jpeg",
          "data": base64Encode(referenceBytes),
        }
      });
    }

    final body = jsonEncode({
      "contents": [
        {"parts": parts}
      ],
      "generationConfig": {
        "responseMimeType": "application/json",
      }
    });

    final modelsToTry = [
      'gemini-2.5-flash-lite',
      'gemini-3.5-flash-lite',
      'gemini-3.8-flash',
      'gemini-2.5-flash',
    ];

    for (final model in modelsToTry) {
      try {
        debugPrint('[GeminiService] Trying model: $model...');
        final response = await http.post(
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey'),
          headers: {'Content-Type': 'application/json'},
          body: body,
        );

        debugPrint('[GeminiService][$model] Status: ${response.statusCode}');

        if (response.statusCode != 200) {
          debugPrint('[GeminiService][$model] Error response: ${response.body}');
          continue;
        }

        final data = jsonDecode(response.body);
        final candidate = data['candidates']?[0];
        if (candidate == null) continue;

        final responseParts = candidate['content']?['parts'] as List?;
        if (responseParts == null || responseParts.isEmpty) continue;

        String? jsonString;
        for (final p in responseParts) {
          if (p is Map && p.containsKey('text') && p['thought'] != true) {
            jsonString = p['text'];
            break;
          }
        }
        jsonString ??= responseParts.last['text'];

        if (jsonString == null) continue;

        final jsonContent = jsonDecode(jsonString);
        EditorState state = EditorState.fromJson(jsonContent['adjustments']);

        // Deterministic Bounding Box Geometry Calculation
        final rawBox = jsonContent['target_box'];
        if (rawBox is List && rawBox.length == 4) {
          try {
            final double ymin = (rawBox[0] as num).toDouble();
            final double xmin = (rawBox[1] as num).toDouble();
            final double ymax = (rawBox[2] as num).toDouble();
            final double xmax = (rawBox[3] as num).toDouble();

            final double boxWidth = (xmax - xmin).abs();
            final double boxHeight = (ymax - ymin).abs();

            final double centerX = xmin + (boxWidth / 2);
            final double centerY = ymin + (boxHeight / 2);

            final double calculatedRadius = (math.max(boxWidth, boxHeight) / 2) * 1.25;

            // Ensure vignette_amount is visually noticeable when a focus box is generated
            double vignetteAmt = state.vignetteAmount;
            if (vignetteAmt > -0.3) {
              vignetteAmt = -0.45;
            }

            state = state.copyWith(
              maskCenterX: centerX,
              maskCenterY: centerY,
              vignetteRadius: calculatedRadius.clamp(0.08, 0.95),
              vignetteAmount: vignetteAmt,
            );
            debugPrint('[GeminiService] Target Box parsed: center=($centerX, $centerY), radius=$calculatedRadius, amount=$vignetteAmt');
          } catch (boxError) {
            debugPrint('[GeminiService] Bounding box parse error: $boxError');
          }
        }

        return state;
      } catch (e, stack) {
        debugPrint('[GeminiService][$model] Exception: $e\n$stack');
      }
    }

    return null;
  }
}
