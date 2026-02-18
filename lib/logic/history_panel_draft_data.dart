class HistoryPanelDraftData {
  final String progressReference;
  final String supervisorEmail;
  final String supervisorCode;
  final String learnerInternalName;
  final String comment;
  final bool learnerConsentConfirmed;

  const HistoryPanelDraftData({
    this.progressReference = '',
    this.supervisorEmail = '',
    this.supervisorCode = '',
    this.learnerInternalName = '',
    this.comment = '',
    this.learnerConsentConfirmed = false,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'progressReference': progressReference,
        'supervisorEmail': supervisorEmail,
        'supervisorCode': supervisorCode,
        'learnerInternalName': learnerInternalName,
        'comment': comment,
        'learnerConsentConfirmed': learnerConsentConfirmed,
      };

  factory HistoryPanelDraftData.fromJson(Map<String, dynamic> json) {
    String readString(String key) => (json[key] ?? '').toString();
    return HistoryPanelDraftData(
      progressReference: readString('progressReference'),
      supervisorEmail: readString('supervisorEmail'),
      supervisorCode: readString('supervisorCode'),
      learnerInternalName: readString('learnerInternalName'),
      comment: readString('comment'),
      learnerConsentConfirmed: json['learnerConsentConfirmed'] == true,
    );
  }
}
