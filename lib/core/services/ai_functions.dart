import 'package:cloud_functions/cloud_functions.dart';

/// Γιατί απέτυχε μια κλήση AI — ο χρήστης βλέπει διαφορετικό μήνυμα.
enum AiFailure {
  /// Ημερήσιο όριο χρήσης (ανά χρήστη ή καθολικό).
  quota,

  /// Δίκτυο, σφάλμα server/Gemini API, άρνηση μοντέλου.
  unavailable,
}

class AiException implements Exception {
  final AiFailure reason;
  const AiException(this.reason);

  @override
  String toString() => 'AiException($reason)';
}

/// Κοινή κλήση στα AI callables (push-notifications/src/ai.ts).
///
/// Τα LLM τρέχουν ΜΟΝΟ στον server — η εφαρμογή δεν βλέπει ποτέ API key.
/// Κάθε σφάλμα μεταφράζεται σε [AiException], ώστε οι οθόνες να έχουν ΕΝΑΝ
/// τύπο να χειριστούν (και να πέφτουν πάντα σε λειτουργία χωρίς AI).
class AiFunctions {
  final FirebaseFunctions? _functions;

  const AiFunctions({FirebaseFunctions? functions}) : _functions = functions;

  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> data, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final functions =
        _functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');
    try {
      final res = await functions
          .httpsCallable(name, options: HttpsCallableOptions(timeout: timeout))
          .call(data);
      // Το plugin επιστρέφει Map<Object?, Object?> — όχι απευθείας cast.
      return Map<String, dynamic>.from(res.data as Map);
    } on FirebaseFunctionsException catch (e) {
      throw AiException(e.code == 'resource-exhausted'
          ? AiFailure.quota
          : AiFailure.unavailable);
    } catch (_) {
      throw const AiException(AiFailure.unavailable);
    }
  }
}
