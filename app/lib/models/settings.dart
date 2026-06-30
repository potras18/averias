class Settings {
  final String smtpHost;
  final String smtpPort;
  final String smtpUser;
  final String smtpPass;
  final String smtpFrom;
  final List<String> emailRecipients;

  const Settings({
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpUser,
    required this.smtpPass,
    required this.smtpFrom,
    required this.emailRecipients,
  });

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        smtpHost:        (j['smtp_host']  as String?) ?? '',
        smtpPort:        (j['smtp_port']  as String?) ?? '587',
        smtpUser:        (j['smtp_user']  as String?) ?? '',
        smtpPass:        (j['smtp_pass']  as String?) ?? '',
        smtpFrom:        (j['smtp_from']  as String?) ?? '',
        emailRecipients: (j['email_recipients'] as List<dynamic>?)?.cast<String>() ?? [],
      );
}
