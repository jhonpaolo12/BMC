import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the most recent order so the payment deep link can still
/// find it if Android restarts the app while the browser is open.
class LastOrderStore {
  LastOrderStore._();

  static const String _orderIdKey = 'plaintees_last_order_id';
  static const String _sessionIdKey =
      'plaintees_last_payment_session_id';

  static Future<void> save({
    required String orderId,
    required String sessionId,
  }) async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.setString(_orderIdKey, orderId);
    await preferences.setString(_sessionIdKey, sessionId);
  }

  static Future<String?> readOrderId() async {
    final preferences = await SharedPreferences.getInstance();

    return preferences.getString(_orderIdKey);
  }

  static Future<String?> readSessionId() async {
    final preferences = await SharedPreferences.getInstance();

    return preferences.getString(_sessionIdKey);
  }

  static Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.remove(_orderIdKey);
    await preferences.remove(_sessionIdKey);
  }
}
