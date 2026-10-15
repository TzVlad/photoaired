import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'editor_state.dart';
import 'dart:math';

Uint8List _resizeAndCompressImage(Uint8List rawBytes) {
  final image = img.decodeImage(rawBytes);
  if (image == null) return rawBytes;

  img.Image resized;
  if (image.width >= image.height) {
    resized = img.copyResize(image, width: 512);
  } else {
    resized = img.copyResize(image, height: 512);
  }

  return Uint8List.fromList(img.encodeJpg(resized, quality: 75));
}

Future<Uint8List> prepareImageForGemini(Uint8List rawBytes) async {
  return compute(_resizeAndCompressImage, rawBytes);
}

class GeminiService {
  final String apiKey;

  GeminiService(this.apiKey);

  Future<EditorState?> processPrompt({
    required String prompt,
    required Uint8List targetImageBytes,
    Uint8List? referenceImageBytes,
    required EditorState currentState,
  }) async {
    const url = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';
    
    final preparedTargetBytes = await prepareImageForGemini(targetImageBytes);
    final preparedReferenceBytes = referenceImageBytes != null
        ? await prepareImageForGemini(referenceImageBytes)
        : null;

    String promptText = '''
You are an expert parametric image editor AI analyzing an image and user request.
The user wants to edit the attached photo. 
User Intent: "$prompt"
Current editor state:
${jsonEncode(currentState.toJson())}

CRITICAL RULES:
- Exposure values must stay balanced between -0.5 and 0.5 for aesthetic styles. Do not continuously blow out highlights or blacks.
- Generate absolute target settings based on a neutral/default baseline, rather than multiplying or blowing out current values.
''';

    if (preparedReferenceBytes != null) {
      promptText += '''
- Analyze the color grade and lighting of the reference image, apply similar grading to the target image. Avoid blown-out highlights.
''';
    }

    promptText += '''
COMPOSITION & FOCUS DETECTION RULE:
If the user prompt does not specify a target object, you MUST visually identify the primary subject in focus (compositional center of interest: e.g. face, object in hands, subject with sharpest edges) from the target image.
Define its bounding box in target_box [ymin, xmin, ymax, xmax] (0 to 1000 scale).

DO NOT create generic harsh vignettes. All masks must be subtle Dodge & Burn adjustments:
- feather MUST be between 0.70 and 0.85 (ultra-soft gradient falloff).
- mask exposure delta MUST be between -0.30 and +0.30 (never exceed absolute values of 0.40 to avoid dirty halos).
- radius must tightly encompass the detected subject (typically 0.25 to 0.45 relative radius).
If no specific object is mentioned, leave "target_box" null.
Also provide "mask_intent" which can be "highlight" or "dim_background" or null.

Output ONLY a valid JSON object matching this schema exactly.
{
  "explanation": "Short rationale",
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
    "grain": 0.0
  },
  "target_box": [200, 200, 800, 800],
  "mask_intent": "highlight"
}
Return only the raw JSON. No markdown code blocks.
''';

    final parts = <Map<String, dynamic>>[
      {"text": promptText},
      {
        "inlineData": {
          "mimeType": "image/jpeg",
          "data": base64Encode(preparedTargetBytes)
        }
      }
    ];

    if (preparedReferenceBytes != null) {
      parts.add({
        "inlineData": {
          "mimeType": "image/jpeg",
          "data": base64Encode(preparedReferenceBytes)
        }
      });
    }

    final body = jsonEncode({
      "contents": [
        {
          "parts": parts
        }
      ],
      "generationConfig": {
        "responseMimeType": "application/json"
      }
    });

    try {
      final response = await http.post(
        Uri.parse('$url?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final contentText = data['candidates'][0]['content']['parts'][0]['text'];
        final jsonContent = jsonDecode(contentText);
        
        double clampVal(dynamic val, double min, double max, double def) {
          if (val == null || val is! num) return def;
          return val.toDouble().clamp(min, max);
        }

        EditorState newState = currentState.copyWith(
          exposure: clampVal(jsonContent['adjustments']['exposure'], -2.0, 2.0, currentState.exposure),
          contrast: clampVal(jsonContent['adjustments']['contrast'], 0.5, 2.0, currentState.contrast),
          highlights: clampVal(jsonContent['adjustments']['highlights'], -1.0, 1.0, currentState.highlights),
          shadows: clampVal(jsonContent['adjustments']['shadows'], -1.0, 1.0, currentState.shadows),
          whites: clampVal(jsonContent['adjustments']['whites'], -1.0, 1.0, currentState.whites),
          blacks: clampVal(jsonContent['adjustments']['blacks'], -1.0, 1.0, currentState.blacks),
          temperature: clampVal(jsonContent['adjustments']['temperature'], -1.0, 1.0, currentState.temperature),
          tint: clampVal(jsonContent['adjustments']['tint'], -1.0, 1.0, currentState.tint),
          saturation: clampVal(jsonContent['adjustments']['saturation'], 0.0, 2.0, currentState.saturation),
          vibrance: clampVal(jsonContent['adjustments']['vibrance'], -1.0, 1.0, currentState.vibrance),
          colorGradingShadowHue: clampVal(jsonContent['adjustments']['color_grading_shadow_hue'], 0.0, 360.0, currentState.colorGradingShadowHue),
          colorGradingHighlightHue: clampVal(jsonContent['adjustments']['color_grading_highlight_hue'], 0.0, 360.0, currentState.colorGradingHighlightHue),
          clarity: clampVal(jsonContent['adjustments']['clarity'], -1.0, 1.0, currentState.clarity),
          sharpness: clampVal(jsonContent['adjustments']['sharpness'], 0.0, 1.0, currentState.sharpness),
          grain: clampVal(jsonContent['adjustments']['grain'], 0.0, 1.0, currentState.grain),
        );

        if (jsonContent['target_box'] != null && jsonContent['target_box'] is List) {
          final box = jsonContent['target_box'] as List;
          if (box.length == 4) {
            final double ymin = (box[0] as num).toDouble();
            final double xmin = (box[1] as num).toDouble();
            final double ymax = (box[2] as num).toDouble();
            final double xmax = (box[3] as num).toDouble();
            
            final double cx = ((xmin + xmax) / 2.0) / 1000.0;
            final double cy = ((ymin + ymax) / 2.0) / 1000.0;
            final double width = (xmax - xmin).abs() / 1000.0;
            final double height = (ymax - ymin).abs() / 1000.0;
            final double radius = (max(width, height) * 0.6).clamp(0.2, 0.5);
            
            String intent = jsonContent['mask_intent'] ?? 'highlight';
            
            AdjustmentMask newMask = AdjustmentMask(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              name: 'AI Mask',
              centerX: cx,
              centerY: cy,
              radius: radius,
              feather: 0.75,
              exposure: intent == 'dim_background' ? -0.2 : 0.2,
              isInverted: intent == 'dim_background',
            );
            
            newState = newState.addMask(newMask);
          }
        }
        
        return newState;
      }
    } catch (e) {
      debugPrint('Gemini API Error: $e');
    }
    return null;
  }
}
