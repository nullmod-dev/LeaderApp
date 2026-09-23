class NotificationPrefs {
  const NotificationPrefs({
    required this.shiftReminders,
    required this.stockAlerts,
    required this.workshopUpdates,
    required this.joinRequests,
  });

  final bool shiftReminders;
  final bool stockAlerts;
  final bool workshopUpdates;
  final bool joinRequests;

  NotificationPrefs copyWith({
    bool? shiftReminders,
    bool? stockAlerts,
    bool? workshopUpdates,
    bool? joinRequests,
  }) =>
      NotificationPrefs(
        shiftReminders: shiftReminders ?? this.shiftReminders,
        stockAlerts: stockAlerts ?? this.stockAlerts,
        workshopUpdates: workshopUpdates ?? this.workshopUpdates,
        joinRequests: joinRequests ?? this.joinRequests,
      );

  factory NotificationPrefs.fromJson(Map<String, dynamic> j) =>
      NotificationPrefs(
        shiftReminders: j['shiftReminders'] as bool,
        stockAlerts: j['stockAlerts'] as bool,
        workshopUpdates: j['workshopUpdates'] as bool,
        joinRequests: j['joinRequests'] as bool,
      );

  Map<String, dynamic> toJson() => {
        'shiftReminders': shiftReminders,
        'stockAlerts': stockAlerts,
        'workshopUpdates': workshopUpdates,
        'joinRequests': joinRequests,
      };
}

class OrgInfo {
  const OrgInfo({
    required this.name,
    required this.legalName,
    required this.address,
    required this.emailPublic,
    required this.detachmentCount,
    required this.memberCount,
  });

  final String name;
  final String legalName;
  final String address;
  final String emailPublic;
  final int detachmentCount;
  final int memberCount;

  factory OrgInfo.fromJson(Map<String, dynamic> j) => OrgInfo(
        name: j['name'] as String,
        legalName: j['legalName'] as String,
        address: j['address'] as String,
        emailPublic: j['emailPublic'] as String,
        detachmentCount: j['detachmentCount'] as int,
        memberCount: j['memberCount'] as int,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'legalName': legalName,
        'address': address,
        'emailPublic': emailPublic,
        'detachmentCount': detachmentCount,
        'memberCount': memberCount,
      };
}
