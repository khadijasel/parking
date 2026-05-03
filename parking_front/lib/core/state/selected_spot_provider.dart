import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global provider that holds the currently selected parking spot label.
/// When null or empty, no explicit selection has been made.
final selectedSpotProvider = StateProvider<String?>((ref) => null);
