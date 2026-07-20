class Settings {
  final String smtpHost;
  final String smtpPort;
  final String smtpUser;
  final String smtpPass;
  final String smtpFrom;
  final List<String> emailRecipients;
  final String emailSubjectReports;
  final String emailBodyReports;
  final String emailSubjectStats;
  final String emailBodyStats;
  final bool ticketLevelQuestionEnabled;

  const Settings({
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpUser,
    required this.smtpPass,
    required this.smtpFrom,
    required this.emailRecipients,
    required this.emailSubjectReports,
    required this.emailBodyReports,
    required this.emailSubjectStats,
    required this.emailBodyStats,
    required this.ticketLevelQuestionEnabled,
  });

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        smtpHost:        (j['smtp_host']  as String?) ?? '',
        smtpPort:        (j['smtp_port']  as String?) ?? '587',
        smtpUser:        (j['smtp_user']  as String?) ?? '',
        smtpPass:        (j['smtp_pass']  as String?) ?? '',
        smtpFrom:        (j['smtp_from']  as String?) ?? '',
        emailRecipients: (j['email_recipients'] as List<dynamic>?)?.cast<String>() ?? [],
        emailSubjectReports: (j['email_subject_reports'] as String?) ?? '',
        emailBodyReports:    (j['email_body_reports']    as String?) ?? '',
        emailSubjectStats:   (j['email_subject_stats']   as String?) ?? '',
        emailBodyStats:      (j['email_body_stats']      as String?) ?? '',
        ticketLevelQuestionEnabled: (j['ticket_level_question_enabled'] as bool?) ?? true,
      );
}
