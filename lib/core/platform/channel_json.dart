/// Platform channels deliver `Map<Object?, Object?>` at every nesting level,
/// while generated `fromJson` code expects `Map<String, dynamic>`.
Map<String, dynamic> jsonMap(Object? value) => (value! as Map).map(
  (key, value) => MapEntry(key as String, _jsonValue(value)),
);

Object? _jsonValue(Object? value) => switch (value) {
  Map() => jsonMap(value),
  List() => value.map(_jsonValue).toList(),
  _ => value,
};
