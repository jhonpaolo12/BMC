/// Configuration for the free Supabase Edge Function that creates
/// Xendit payment sessions.
///
/// The Supabase anon key is a publishable client key. It is safe to
/// ship in the app; the Xendit secret key stays in Supabase secrets
/// and is never included in this project.
class PaymentConfig {
  PaymentConfig._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://hyehlrqplnmfmvuircoc.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh5ZWhscnFwbG5tZm12dWlyY29jIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI1ODYyODQsImV4cCI6MjEwODE2MjI4NH0.aE7lPVHwKw9lbyHOW7DT8w38Bd8WUxUpAu4mtzG-01g',
  );

  static Uri functionUri(String functionName) {
    return Uri.parse('$supabaseUrl/functions/v1/$functionName');
  }
}
