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

String sanitizeJson(String raw) {
  var text = raw.trim();
  if (text.startsWith('```json')) {
    text = text.substring(7);
  } else if (text.startsWith('```')) {
    text = text.substring(3);
  }
  if (text.endsWith('```')) {
    text = text.substring(0, text.length - 3);
  }
  return text.trim();
}

class GeminiService {
  final String apiKey;
  
  static const bool kDebugMockMode = false;

  GeminiService(this.apiKey);

  Future<EditorState?> processPrompt({
    required String prompt,
    required Uint8List targetImageBytes,
    Uint8List? referenceImageBytes,
    required EditorState currentState,
  }) async {
    if (kDebugMockMode) {
      debugPrint('[AI Pipeline] Running in MOCK mode');
      await Future.delayed(const Duration(milliseconds: 700));
      return currentState.copyWith(
        exposure: (currentState.exposure + 0.25).clamp(-2.0, 2.0),
        contrast: (currentState.contrast + 0.15).clamp(0.5, 2.0),
        temperature: -0.20,
        tint: 0.10,
        shadows: 0.15,
        highlights: -0.30,
      );
    }

    final preparedTargetBytes = await prepareImageForGemini(targetImageBytes);
    final preparedReferenceBytes = referenceImageBytes != null
        ? await prepareImageForGemini(referenceImageBytes)
        : null;

    debugPrint('[AI Pipeline] Input bytes: target=${preparedTargetBytes.length}, ref=${preparedReferenceBytes?.length}');

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
MASK RULE (STRICT): If the user request is global (e.g., 'vintage', 'black and white', 'increase exposure', 'cinematic warm', 'more contrast'), target_box and mask_intent MUST BE null.
ONLY populate target_box [ymin, xmin, ymax, xmax] if the user explicitly asks for a local change ('brighten face', 'darken background') OR the prompt strictly requires isolating a distinct primary subject.

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
  "target_box": null,
  "mask_intent": null
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

    final endpointsToTry = [
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent',
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent',
    ];

    String? lastErrorDetails;

    for (final urlString in endpointsToTry) {
      final url = Uri.parse(urlString);
      final headers = {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      };

      try {
        debugPrint('[AI Pipeline] Requesting endpoint: $url');
        final response = await http.post(
          url,
          headers: headers,
          body: body,
        );

        debugPrint('[AI Pipeline] Status code: ${response.statusCode}');

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final contentText = data['candidates'][0]['content']['parts'][0]['text'];
          debugPrint('[AI Pipeline] Raw Gemini response text: $contentText');

          final cleanedJsonStr = sanitizeJson(contentText);
          debugPrint('[AI Pipeline] Cleaned JSON string: $cleanedJsonStr');

          final jsonContent = jsonDecode(cleanedJsonStr);
          
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
          } else {
            newState = newState.copyWith(masks: currentState.masks);
          }

          return newState;
        } else if (response.statusCode == 404) {
          lastErrorDetails = '[Status 404 for $urlString]: Model not found';
          debugPrint('[AI Pipeline Error]: $lastErrorDetails');
          continue; // Try next model
        } else {
          throw Exception('Gemini API Error (${response.statusCode}): ${response.body}');
        }
      } catch (e, stackTrace) {
        if (e is Exception && e.toString().contains('404')) {
          lastErrorDetails = e.toString();
          continue;
        }
        debugPrint('[ERROR] Gemini API Exception: $e\n$stackTrace');
        rethrow;
      }
    }

    throw Exception('Gemini API Error: Models not found. Detailed fallback log: $lastErrorDetails');
  }
}
