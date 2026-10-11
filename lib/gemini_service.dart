import 'dart:convert';
import 'package:http/http.dart' as http;
import 'editor_state.dart';

class GeminiService {
  final String apiKey;

  GeminiService(this.apiKey);

  Future<EditorState?> analyzePrompt(String prompt, EditorState currentState) async {
    const url = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';
    
    final promptText = '''
You are a parametric image editor AI.
The user wants to edit a photo. 
Here is their intent: "$prompt"
Current state:
${jsonEncode(currentState.toJson())}

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

    final body = jsonEncode({
      "contents": [
        {
          "parts": [
            {"text": promptText}
          ]
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
        return EditorState.fromJson(jsonContent['adjustments']);
      }
    } catch (e) {
      print('Gemini API Error: $e');
    }
    return null;
  }
}
