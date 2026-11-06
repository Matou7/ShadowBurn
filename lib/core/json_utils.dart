// lib/core/json_utils.dart
/// Lecture sécurisée de valeurs JSON (jamais de crash si une clé manque ou change de type).
int asInt(dynamic v, [int fallback = 0]) => v is num ? v.toInt() : fallback;
double asDouble(dynamic v, [double fallback = 0.0]) => v is num ? v.toDouble() : fallback;
bool asBool(dynamic v, [bool fallback = false]) => v is bool ? v : fallback;
String asString(dynamic v, [String fallback = '']) => v is String ? v : fallback;

Map<String, dynamic> asMap(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<dynamic> asList(dynamic v) => v is List ? List<dynamic>.from(v) : <dynamic>[];