import '../models/classification_hit.dart';
import '../models/place.dart';

/// Abstract classifier interface.
/// Designed to be replaceable: rule-based, AI-based, or hybrid.
abstract class PlaceClassifier {
  Future<List<ClassificationHit>> classify(Place place);
}
