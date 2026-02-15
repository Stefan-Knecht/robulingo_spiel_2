import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/resume_state_service.dart';
import '../data/supervisor_link_service.dart';
import '../logic/history_hint_loader.dart';

final Uri _consentInfoUri = Uri.parse(
  'https://www.dailywords-project.org/trial',
);
final Uri _registerInfoUri = Uri.parse(
  'https://www.dailywords-project.org/register/',
);

Future<void> showHistoryPanel({
  required BuildContext context,
  required String? userId,
  required String? targetLang,
  required String? nativeLang,
  required ResumeState? resumeState,
  required ResumeStateService resumeStateService,
  required SupervisorLinkService supervisorLinkService,
  required HistoryHintLoader hintLoader,
  required Future<void> Function(String id, ResumeState? state) onApplyUserId,
  required Future<void> Function() onRemoveUserId,
}) async {
  final controller = TextEditingController(text: userId ?? '');
  final supervisorEmailController = TextEditingController();
  final supervisorCodeController = TextEditingController();
  final learnerInternalNameController = TextEditingController();
  final commentController = TextEditingController();
  bool panelOpen = true;
  String progressStatus = '';
  String supervisorStatus = '';
  bool loading = false;
  bool learnerConsentConfirmed = false;
  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final dialogNavigator = Navigator.of(dialogCtx);
            bool canUseDialog() =>
                panelOpen && ctx.mounted && dialogCtx.mounted;
            final uiLang = _normalizeLang(
              targetLang ??
                  resumeState?.mostRecentEntry()?.lang ??
                  nativeLang ??
                  resumeState?.mostRecentEntry()?.nativeLang ??
                  'en',
            );
            final removeLabel = _textFor('remove', uiLang);
            final reloadLabel = _textFor('reload', uiLang);
            final applyLabel = _textFor('apply_action', uiLang);
            final progressReferenceLabel =
                _textFor('progress_reference', uiLang);
            final supervisorLabel = _textFor('supervisor', uiLang);
            final supervisorEmailLabel = _textFor('supervisor_email', uiLang);
            final supervisorEmailHint = _textFor('enter_email_address', uiLang);
            final supervisorCodeLabel =
                _textFor('supervisor_code_5_digit', uiLang);
            final supervisorCodeHint = _textFor('enter_code', uiLang);
            final codeRequiresRegistrationLabel =
                _textFor('code_requires_registration', uiLang);
            final internalNameLabel =
                _textFor('internal_name_for_learner', uiLang);
            final learnerConsentLabel = _textFor('learner_consent', uiLang);
            final consentConfirmedLabel = _textFor('consent_confirmed', uiLang);
            final viewConsentLabel =
                _textFor('view_consent_information', uiLang);
            final commentOptionalLabel = _textFor('comment_optional', uiLang);
            final commentHint = _textFor('enter_comment', uiLang);
            final areYouSureLabel = _textFor('are_you_sure', uiLang);
            final cancelLabel = _textFor('cancel', uiLang);
            final removeActionLabel = _textFor('remove_action', uiLang);
            final okLabel = _textFor('ok', uiLang);
            final applyConsentRequiredHint =
                _textFor('apply_consent_required_hint', uiLang);
            final applySupervisorRequiredHint =
                _textFor('apply_supervisor_required_hint', uiLang);
            final progressId = controller.text.trim();
            final supervisorEmail = supervisorEmailController.text.trim();
            final supervisorCode = supervisorCodeController.text.trim();
            final hasProgressId = progressId.isNotEmpty;
            final hasSupervisorEmail = supervisorEmail.isNotEmpty;
            final hasValidSupervisorEmail = _looksLikeEmail(supervisorEmail);
            final hasValidSupervisorCode =
                _isValidSupervisorCode(supervisorCode);
            final canApply = !loading &&
                learnerConsentConfirmed &&
                hasProgressId &&
                hasSupervisorEmail &&
                hasValidSupervisorEmail &&
                hasValidSupervisorCode;
            final applyDisabledHint = !learnerConsentConfirmed
                ? applyConsentRequiredHint
                : (!hasSupervisorEmail || supervisorCode.isEmpty)
                    ? applySupervisorRequiredHint
                    : !hasValidSupervisorEmail
                        ? _textFor('status_supervisor_invalid_email', uiLang)
                        : !hasValidSupervisorCode
                            ? _textFor('status_supervisor_invalid_code', uiLang)
                            : !hasProgressId
                                ? _textFor('status_progress_reference_required',
                                    uiLang)
                                : '';
            Future<void> applyChanges() async {
              final id = controller.text.trim();
              final email = supervisorEmailController.text.trim();
              final code = supervisorCodeController.text.trim();
              if (!learnerConsentConfirmed) {
                if (!canUseDialog()) return;
                setDialogState(() {
                  supervisorStatus =
                      _textFor('status_consent_required_for_apply', uiLang);
                });
                return;
              }
              if (email.isEmpty || code.isEmpty) {
                if (!canUseDialog()) return;
                setDialogState(() {
                  supervisorStatus =
                      _textFor('status_supervisor_missing_pair_fields', uiLang);
                });
                return;
              }
              if (!_looksLikeEmail(email)) {
                if (!canUseDialog()) return;
                setDialogState(() {
                  supervisorStatus =
                      _textFor('status_supervisor_invalid_email', uiLang);
                });
                return;
              }
              if (!_isValidSupervisorCode(code)) {
                if (!canUseDialog()) return;
                setDialogState(() {
                  supervisorStatus =
                      _textFor('status_supervisor_invalid_code', uiLang);
                });
                return;
              }
              if (id.isEmpty) {
                if (!canUseDialog()) return;
                setDialogState(() {
                  supervisorStatus =
                      _textFor('status_progress_reference_required', uiLang);
                });
                return;
              }
              if (!canUseDialog()) return;
              setDialogState(() {
                loading = true;
                supervisorStatus = '';
              });
              try {
                final state = await resumeStateService.fetch(userId: id);
                await onApplyUserId(id, state);
                if (!canUseDialog()) return;
                final supervisorSync = await supervisorLinkService.sync(
                  userId: id,
                  monitoringOn: true,
                  supervisorEmail: email,
                  supervisorCode: code,
                  internalLearnerName: learnerInternalNameController.text,
                  comment: commentController.text,
                  uiLanguage: uiLang,
                );
                if (!canUseDialog()) return;
                if (!supervisorSync.success) {
                  setDialogState(() {
                    loading = false;
                    supervisorStatus = _textFor(
                      supervisorSync.statusKey ?? 'status_history_apply_failed',
                      uiLang,
                    );
                  });
                  return;
                }
                if (!canUseDialog()) return;
                dialogNavigator.pop();
              } catch (_) {
                if (!canUseDialog()) return;
                setDialogState(() {
                  loading = false;
                  supervisorStatus =
                      _textFor('status_history_apply_failed', uiLang);
                });
              }
            }

            Future<void> reloadProgressReference() async {
              final id = controller.text.trim();
              if (id.isEmpty) {
                if (!canUseDialog()) return;
                setDialogState(() {
                  progressStatus =
                      _textFor('status_progress_reference_required', uiLang);
                });
                return;
              }
              if (!canUseDialog()) return;
              setDialogState(() {
                loading = true;
                progressStatus = '';
              });
              try {
                final state = await resumeStateService.fetch(userId: id);
                await onApplyUserId(id, state);
                if (!canUseDialog()) return;
                setDialogState(() {
                  loading = false;
                  progressStatus = (state == null || state.entries.isEmpty)
                      ? _textFor('status_userid_applied_no_history', uiLang)
                      : _textFor('status_userid_updated', uiLang);
                });
              } catch (_) {
                if (!canUseDialog()) return;
                setDialogState(() {
                  loading = false;
                  progressStatus =
                      _textFor('status_history_apply_failed', uiLang);
                });
              }
            }

            Future<void> removeUserId() async {
              final confirmed = await showDialog<bool>(
                context: ctx,
                builder: (confirmCtx) {
                  return AlertDialog(
                    title: Text(areYouSureLabel),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(confirmCtx).pop(false),
                        child: Text(cancelLabel),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(confirmCtx).pop(true),
                        child: Text(removeActionLabel),
                      ),
                    ],
                  );
                },
              );
              if (confirmed != true) return;
              await onRemoveUserId();
              if (!canUseDialog()) return;
              setDialogState(() {
                progressStatus = _textFor('status_userid_removed', uiLang);
              });
              if (!canUseDialog()) return;
              dialogNavigator.pop();
            }

            Future<void> showHint() async {
              if (!canUseDialog()) return;
              setDialogState(() {
                loading = true;
                progressStatus = '';
              });
              final text = await hintLoader.loadHint(uiLang);
              if (!canUseDialog()) return;
              setDialogState(() {
                loading = false;
              });
              if (!canUseDialog()) return;
              if (!dialogNavigator.mounted) return;
              showDialog<void>(
                context: dialogNavigator.context,
                builder: (hintCtx) => AlertDialog(
                  content: Text(text),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(hintCtx).pop(),
                      child: Text(okLabel),
                    ),
                  ],
                ),
              );
            }

            return Dialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 680),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                supervisorLabel,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: cancelLabel,
                              onPressed: () => Navigator.of(dialogCtx).pop(),
                              icon: const Icon(
                                Icons.close,
                                size: 30,
                                color: Colors.black,
                                weight: 800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        _LabeledField(
                          label: supervisorEmailLabel,
                          child: TextField(
                            controller: supervisorEmailController,
                            onChanged: (_) => setDialogState(() {}),
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              isDense: true,
                              hintText: supervisorEmailHint,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _LabeledField(
                          label: supervisorCodeLabel,
                          child: TextField(
                            controller: supervisorCodeController,
                            onChanged: (_) => setDialogState(() {}),
                            keyboardType: TextInputType.text,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[A-Za-z0-9]'),
                              ),
                              LengthLimitingTextInputFormatter(5),
                            ],
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              isDense: true,
                              hintText: supervisorCodeHint,
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () async {
                              final launched = await launchUrl(
                                _registerInfoUri,
                                mode: LaunchMode.platformDefault,
                              );
                              if (launched || !ctx.mounted) return;
                              setDialogState(() {
                                supervisorStatus = _textFor(
                                  'status_register_link_failed',
                                  uiLang,
                                );
                              });
                            },
                            child: Text(
                              '$codeRequiresRegistrationLabel: https://www.dailywords-project.org/register/',
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _LabeledField(
                          label: internalNameLabel,
                          child: TextField(
                            controller: learnerInternalNameController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                              hintText: 'Max Mustermann',
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          learnerConsentLabel,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Row(
                          children: [
                            Checkbox(
                              value: learnerConsentConfirmed,
                              onChanged: (value) {
                                setDialogState(() {
                                  learnerConsentConfirmed = value ?? false;
                                });
                              },
                            ),
                            Text(consentConfirmedLabel),
                          ],
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () async {
                              final launched = await launchUrl(
                                _consentInfoUri,
                                mode: LaunchMode.platformDefault,
                              );
                              if (launched || !ctx.mounted) return;
                              setDialogState(() {
                                supervisorStatus = _textFor(
                                  'status_consent_link_failed',
                                  uiLang,
                                );
                              });
                            },
                            child: Text(
                              '$viewConsentLabel: https://www.dailywords-project.org/trial',
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _LabeledField(
                          label: commentOptionalLabel,
                          child: TextField(
                            controller: commentController,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              isDense: true,
                              hintText: commentHint,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    progressReferenceLabel,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: controller,
                                    onChanged: (_) => setDialogState(() {}),
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 14,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: loading ? null : removeUserId,
                                  child: Image.asset(
                                    'assets/icons/remove.webp',
                                    width: 36,
                                    height: 36,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(removeLabel),
                              ],
                            ),
                            GestureDetector(
                              onTap: loading ? null : reloadProgressReference,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset(
                                    'assets/icons/reload.webp',
                                    width: 36,
                                    height: 36,
                                    fit: BoxFit.contain,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    reloadLabel,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: loading ? null : showHint,
                              child: Image.asset(
                                'assets/icons/Magnifying_glass.webp',
                                width: 36,
                                height: 36,
                                fit: BoxFit.contain,
                              ),
                            ),
                            SizedBox(
                              width: 180,
                              child: GestureDetector(
                                onTap: canApply ? applyChanges : null,
                                child: Opacity(
                                  opacity: canApply ? 1.0 : 0.45,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Icon(
                                        canApply ? Icons.check_box : Icons.lock,
                                        size: 36,
                                        color: canApply
                                            ? Colors.green.shade700
                                            : Colors.grey.shade700,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        applyLabel,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      if (!canApply &&
                                          applyDisabledHint
                                              .trim()
                                              .isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        SizedBox(
                                          width: 160,
                                          child: Text(
                                            applyDisabledHint,
                                            textAlign: TextAlign.right,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (progressStatus.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            '$progressReferenceLabel: $progressStatus',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                        if (supervisorStatus.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            '$supervisorLabel: $supervisorStatus',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  } finally {
    panelOpen = false;
    // Delay disposal one frame to avoid transient route teardown callbacks
    // touching controllers during dialog close animations.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
      supervisorEmailController.dispose();
      supervisorCodeController.dispose();
      learnerInternalNameController.dispose();
      commentController.dispose();
    });
  }
}

String _normalizeLang(String raw) {
  final normalized = raw.trim().toLowerCase();
  if (normalized.isEmpty) return 'en';
  final parts = normalized.split(RegExp(r'[-_]'));
  return parts.isEmpty ? 'en' : parts.first;
}

bool _looksLikeEmail(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return false;
  return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);
}

bool _isValidSupervisorCode(String raw) {
  final value = raw.trim();
  return RegExp(r'^[A-Za-z0-9]{5}$').hasMatch(value);
}

String _textFor(String key, String lang) {
  final normalized = _normalizeLang(lang);
  final map = _historyTexts[key];
  if (map == null) return key;
  return map[normalized] ?? map['en'] ?? key;
}

const Map<String, Map<String, String>> _historyTexts = {
  'progress_reference': {
    'en': 'Progress Reference',
    'de': 'Fortschrittsreferenz',
    'ar': 'مرجع التقدم',
    'fr': 'Reference de progression',
    'es': 'Referencia de progreso',
    'it': 'Riferimento progresso',
    'ru': 'Ссылка на прогресс',
    'hi': 'प्रगति संदर्भ',
    'el': 'Αναφορά προόδου',
    'zh': '进度参考',
    'tr': 'Ilerleme referansi',
    'ja': '進捗参照',
  },
  'supervisor': {
    'en': 'Supervisor',
    'de': 'Supervisor',
    'ar': 'المشرف',
    'fr': 'Superviseur',
    'es': 'Supervisor',
    'it': 'Supervisore',
    'ru': 'Супервизор',
    'hi': 'पर्यवेक्षक',
    'el': 'Εποπτης',
    'zh': '督导',
    'tr': 'Supervisor',
    'ja': 'スーパーバイザー',
  },
  'supervisor_email': {
    'en': 'Supervisor email:',
    'de': 'Supervisor-E-Mail:',
    'ar': 'بريد المشرف:',
    'fr': 'E-mail du superviseur :',
    'es': 'Correo del supervisor:',
    'it': 'Email del supervisore:',
    'ru': 'Email супервизора:',
    'hi': 'पर्यवेक्षक ईमेल:',
    'el': 'Email εποπτη:',
    'zh': '督导邮箱:',
    'tr': 'Supervisor e-postasi:',
    'ja': 'スーパーバイザーのメール:',
  },
  'enter_email_address': {
    'en': 'Enter email address',
    'de': 'E-Mail-Adresse eingeben',
    'ar': 'ادخل البريد الالكتروني',
    'fr': 'Saisir ladresse e-mail',
    'es': 'Introduce direccion de correo',
    'it': 'Inserisci indirizzo email',
    'ru': 'Введите email',
    'hi': 'ईमेल पता दर्ज करें',
    'el': 'Εισαγωγη email',
    'zh': '输入邮箱地址',
    'tr': 'E-posta adresini girin',
    'ja': 'メールアドレスを入力',
  },
  'supervisor_code_5_digit': {
    'en': '5-character supervisor code:',
    'de': '5-stelliger Supervisor-Code (Buchstaben/Ziffern):',
    'ar': 'رمز المشرف من 5 ارقام:',
    'fr': 'Code superviseur a 5 chiffres :',
    'es': 'Codigo del supervisor de 5 digitos:',
    'it': 'Codice supervisore a 5 cifre:',
    'ru': '5-значный код супервизора:',
    'hi': '5-अंकीय पर्यवेक्षक कोड:',
    'el': '5ψηφιος κωδικος εποπτη:',
    'zh': '5位督导代码:',
    'tr': '5 haneli supervisor kodu:',
    'ja': '5桁のスーパーバイザーコード:',
  },
  'enter_code': {
    'en': 'Enter code',
    'de': 'Code eingeben',
    'ar': 'ادخل الرمز',
    'fr': 'Saisir le code',
    'es': 'Introduce el codigo',
    'it': 'Inserisci il codice',
    'ru': 'Введите код',
    'hi': 'कोड दर्ज करें',
    'el': 'Εισαγωγη κωδικου',
    'zh': '输入代码',
    'tr': 'Kodu girin',
    'ja': 'コードを入力',
  },
  'code_requires_registration': {
    'en': 'Code requires registration',
    'de': 'Code erfordert Registrierung',
    'ar': 'الرمز يتطلب التسجيل',
    'fr': 'Le code necessite une inscription',
    'es': 'El codigo requiere registro',
    'it': 'Il codice richiede registrazione',
    'ru': 'Код требует регистрации',
    'hi': 'कोड के लिए पंजीकरण आवश्यक है',
    'el': 'Ο κωδικος απαιτει εγγραφη',
    'zh': '代码需要注册',
    'tr': 'Kod icin kayit gereklidir',
    'ja': 'コードには登録が必要です',
  },
  'internal_name_for_learner': {
    'en': 'Internal name for learner (for your own reference):',
    'de': 'Interner Name fur Lernende (nur fur eigene Referenz):',
    'ar': 'اسم داخلي للمتعلم (لمرجعك الخاص):',
    'fr': 'Nom interne de lapprenant (pour votre reference) :',
    'es': 'Nombre interno del alumno (para tu referencia):',
    'it': 'Nome interno del discente (solo per riferimento):',
    'ru': 'Внутреннее имя ученика (только для вас):',
    'hi': 'शिक्षार्थी का आंतरिक नाम (आपके संदर्भ के लिए):',
    'el': 'Εσωτερικο ονομα μαθητη (για δικη σας αναφορα):',
    'zh': '学习者内部名称（仅供参考）:',
    'tr': 'Ogrenci icin dahili ad (kendi referansiniz icin):',
    'ja': '学習者の内部名（あなた専用の参照用）:',
  },
  'learner_consent': {
    'en': 'Learner consent',
    'de': 'Einwilligung der lernenden Person',
    'ar': 'موافقة المتعلم',
    'fr': 'Consentement de lapprenant',
    'es': 'Consentimiento del alumno',
    'it': 'Consenso del discente',
    'ru': 'Согласие ученика',
    'hi': 'शिक्षार्थी की सहमति',
    'el': 'Συγκαταθεση μαθητη',
    'zh': '学习者同意',
    'tr': 'Ogrenci onayi',
    'ja': '学習者の同意',
  },
  'consent_confirmed': {
    'en': 'Confirmed',
    'de': 'Bestatigt',
    'ar': 'تم التاكيد',
    'fr': 'Confirme',
    'es': 'Confirmado',
    'it': 'Confermato',
    'ru': 'Подтверждено',
    'hi': 'पुष्ट',
    'el': 'Επιβεβαιωθηκε',
    'zh': '已确认',
    'tr': 'Onaylandi',
    'ja': '確認済み',
  },
  'view_consent_information': {
    'en': 'View consent information',
    'de': 'Einwilligungsinformationen ansehen',
    'ar': 'عرض معلومات الموافقة',
    'fr': 'Voir les informations de consentement',
    'es': 'Ver informacion de consentimiento',
    'it': 'Visualizza informazioni sul consenso',
    'ru': 'Информация о согласии',
    'hi': 'सहमति जानकारी देखें',
    'el': 'Προβολη πληροφοριων συγκαταθεσης',
    'zh': '查看同意信息',
    'tr': 'Onay bilgilerini goruntule',
    'ja': '同意情報を表示',
  },
  'comment_optional': {
    'en': 'Comment (optional):',
    'de': 'Kommentar (optional):',
    'ar': 'تعليق (اختياري):',
    'fr': 'Commentaire (optionnel) :',
    'es': 'Comentario (opcional):',
    'it': 'Commento (opzionale):',
    'ru': 'Комментарий (необязательно):',
    'hi': 'टिप्पणी (वैकल्पिक):',
    'el': 'Σχολιο (προαιρετικο):',
    'zh': '备注（可选）:',
    'tr': 'Yorum (istege bagli):',
    'ja': 'コメント（任意）:',
  },
  'enter_comment': {
    'en': 'Enter comment',
    'de': 'Kommentar eingeben',
    'ar': 'ادخل تعليقا',
    'fr': 'Saisir un commentaire',
    'es': 'Introduce un comentario',
    'it': 'Inserisci un commento',
    'ru': 'Введите комментарий',
    'hi': 'टिप्पणी दर्ज करें',
    'el': 'Εισαγωγη σχολιου',
    'zh': '输入备注',
    'tr': 'Yorum girin',
    'ja': 'コメントを入力',
  },
  'reload': {
    'en': 'reload',
    'de': 'neu laden',
    'ar': 'اعادة تحميل',
    'fr': 'recharger',
    'es': 'recargar',
    'it': 'ricarica',
    'ru': 'обновить',
    'hi': 'रीलोड',
    'el': 'επαναφορτωση',
    'zh': '重新加载',
    'tr': 'yeniden yukle',
    'ja': '再読み込み',
  },
  'remove': {
    'en': 'remove',
    'de': 'entfernen',
    'ar': 'ازالة',
    'fr': 'supprimer',
    'es': 'eliminar',
    'it': 'rimuovi',
    'ru': 'удалить',
    'hi': 'हटाएं',
    'el': 'αφαιρεση',
    'zh': '移除',
    'tr': 'kaldir',
    'ja': '削除',
  },
  'are_you_sure': {
    'en': 'Are you sure?',
    'de': 'Sind Sie sicher?',
    'ar': 'هل انت متاكد؟',
    'fr': 'Etes-vous sur ?',
    'es': 'Estas seguro?',
    'it': 'Sei sicuro?',
    'ru': 'Вы уверены?',
    'hi': 'क्या आप सुनिश्चित हैं?',
    'el': 'Ειστε σιγουρος;',
    'zh': '你确定吗？',
    'tr': 'Emin misiniz?',
    'ja': '本当に実行しますか？',
  },
  'cancel': {
    'en': 'Cancel',
    'de': 'Abbrechen',
    'ar': 'الغاء',
    'fr': 'Annuler',
    'es': 'Cancelar',
    'it': 'Annulla',
    'ru': 'Отмена',
    'hi': 'रद्द करें',
    'el': 'Ακυρωση',
    'zh': '取消',
    'tr': 'Iptal',
    'ja': 'キャンセル',
  },
  'remove_action': {
    'en': 'Remove',
    'de': 'Entfernen',
    'ar': 'ازالة',
    'fr': 'Supprimer',
    'es': 'Eliminar',
    'it': 'Rimuovi',
    'ru': 'Удалить',
    'hi': 'हटाएं',
    'el': 'Αφαιρεση',
    'zh': '移除',
    'tr': 'Kaldir',
    'ja': '削除',
  },
  'ok': {
    'en': 'OK',
    'de': 'OK',
    'ar': 'موافق',
    'fr': 'OK',
    'es': 'Aceptar',
    'it': 'OK',
    'ru': 'OK',
    'hi': 'ठीक है',
    'el': 'OK',
    'zh': '确定',
    'tr': 'Tamam',
    'ja': 'OK',
  },
  'apply_action': {
    'en': 'apply',
    'de': 'umsetzen',
    'ar': 'تنفيذ',
    'fr': 'appliquer',
    'es': 'aplicar',
    'it': 'applica',
    'ru': 'применить',
    'hi': 'लागू करें',
    'el': 'εφαρμογη',
    'zh': '应用',
    'tr': 'uygula',
    'ja': '適用',
  },
  'apply_consent_required_hint': {
    'en': 'Step 1: confirm consent',
    'de': 'Schritt 1: Einwilligung bestatigen',
    'ar': 'الخطوة 1: تاكيد الموافقة',
    'fr': 'Etape 1 : confirmer le consentement',
    'es': 'Paso 1: confirmar consentimiento',
    'it': 'Passo 1: confermare il consenso',
    'ru': 'Шаг 1: подтвердите согласие',
    'hi': 'चरण 1: सहमति की पुष्टि करें',
    'el': 'Βημα 1: επιβεβαιωση συγκαταθεσης',
    'zh': '步骤1：确认同意',
    'tr': 'Adim 1: onayi dogrula',
    'ja': '手順1: 同意を確認',
  },
  'apply_supervisor_required_hint': {
    'en': 'Step 2: enter email and 5-character code',
    'de': 'Schritt 2: E-Mail und 5-stelligen Code eingeben',
    'ar': 'الخطوة 2: ادخل البريد والرمز من 5 ارقام',
    'fr': 'Etape 2 : saisir e-mail et code a 5 chiffres',
    'es': 'Paso 2: introduce correo y codigo de 5 digitos',
    'it': 'Passo 2: inserire email e codice a 5 cifre',
    'ru': 'Шаг 2: введите email и 5-значный код',
    'hi': 'चरण 2: ईमेल और 5-अंकीय कोड दर्ज करें',
    'el': 'Βημα 2: εισαγωγη email και 5ψηφιου κωδικου',
    'zh': '步骤2：输入邮箱和5位代码',
    'tr': 'Adim 2: e-posta ve 5 haneli kod girin',
    'ja': '手順2: メールと5桁コードを入力',
  },
  'status_userid_applied_no_history': {
    'en': 'User ID applied (no history found).',
    'de': 'User-ID ubernommen (kein Verlauf gefunden).',
    'ar': 'تم اعتماد معرف المستخدم (لم يتم العثور على سجل).',
    'fr': 'Identifiant utilisateur applique (aucun historique trouve).',
    'es': 'ID de usuario aplicada (no se encontro historial).',
    'it': 'ID utente applicata (nessuna cronologia trovata).',
    'ru': 'ID пользователя применен (история не найдена).',
    'hi': 'यूजर आईडी लागू की गई (कोई इतिहास नहीं मिला)।',
    'el': 'Το User ID εφαρμοστηκε (δεν βρεθηκε ιστορικο).',
    'zh': '用户ID已应用（未找到历史记录）。',
    'tr': 'Kullanici kimligi uygulandi (gecmis bulunamadi).',
    'ja': 'ユーザーIDを適用しました（履歴は見つかりませんでした）。',
  },
  'status_userid_updated': {
    'en': 'User ID updated.',
    'de': 'User-ID aktualisiert.',
    'ar': 'تم تحديث معرف المستخدم.',
    'fr': 'Identifiant utilisateur mis a jour.',
    'es': 'ID de usuario actualizada.',
    'it': 'ID utente aggiornata.',
    'ru': 'ID пользователя обновлен.',
    'hi': 'यूजर आईडी अपडेट की गई।',
    'el': 'Το User ID ενημερωθηκε.',
    'zh': '用户ID已更新。',
    'tr': 'Kullanici kimligi guncellendi.',
    'ja': 'ユーザーIDを更新しました。',
  },
  'status_userid_removed': {
    'en': 'User ID removed.',
    'de': 'User-ID entfernt.',
    'ar': 'تمت ازالة معرف المستخدم.',
    'fr': 'Identifiant utilisateur supprime.',
    'es': 'ID de usuario eliminada.',
    'it': 'ID utente rimossa.',
    'ru': 'ID пользователя удален.',
    'hi': 'यूजर आईडी हटाई गई।',
    'el': 'Το User ID αφαιρεθηκε.',
    'zh': '用户ID已移除。',
    'tr': 'Kullanici kimligi kaldirildi.',
    'ja': 'ユーザーIDを削除しました。',
  },
  'status_consent_link_failed': {
    'en': 'Consent information link could not be opened.',
    'de':
        'Link zu den Einwilligungsinformationen konnte nicht geoffnet werden.',
    'ar': 'تعذر فتح رابط معلومات الموافقة.',
    'fr': 'Impossible douvrir le lien des informations de consentement.',
    'es': 'No se pudo abrir el enlace de informacion de consentimiento.',
    'it': 'Impossibile aprire il link delle informazioni sul consenso.',
    'ru': 'Не удалось открыть ссылку с информацией о согласии.',
    'hi': 'सहमति जानकारी का लिंक नहीं खुल सका।',
    'el': 'Δεν ηταν δυνατο να ανοιξει ο συνδεσμος πληροφοριων συγκαταθεσης.',
    'zh': '无法打开同意信息链接。',
    'tr': 'Onay bilgisi baglantisi acilamadi.',
    'ja': '同意情報のリンクを開けませんでした。',
  },
  'status_register_link_failed': {
    'en': 'Registration link could not be opened.',
    'de': 'Registrierungslink konnte nicht geoffnet werden.',
    'ar': 'تعذر فتح رابط التسجيل.',
    'fr': 'Impossible douvrir le lien dinscription.',
    'es': 'No se pudo abrir el enlace de registro.',
    'it': 'Impossibile aprire il link di registrazione.',
    'ru': 'Не удалось открыть ссылку регистрации.',
    'hi': 'पंजीकरण लिंक नहीं खुल सका।',
    'el': 'Δεν ηταν δυνατο να ανοιξει ο συνδεσμος εγγραφης.',
    'zh': '无法打开注册链接。',
    'tr': 'Kayit baglantisi acilamadi.',
    'ja': '登録リンクを開けませんでした。',
  },
  'status_history_apply_failed': {
    'en': 'Could not load/save history information.',
    'de': 'Verlaufsinformationen konnten nicht geladen/gespeichert werden.',
  },
  'status_supervisor_missing_userid': {
    'en': 'Missing user ID for supervisor sync.',
    'de': 'Fehlende User-ID fur Supervisor-Abgleich.',
  },
  'status_supervisor_invalid_code': {
    'en': 'Supervisor code must be exactly 5 characters (letters and numbers).',
    'de':
        'Der Supervisor-Code muss genau 5 Zeichen haben (Buchstaben und Ziffern).',
  },
  'status_supervisor_invalid_email': {
    'en': 'Supervisor email address is invalid.',
    'de': 'Die Supervisor-E-Mail-Adresse ist ungueltig.',
    'ar': 'عنوان بريد المشرف غير صالح.',
    'fr': 'Ladresse e-mail du superviseur est invalide.',
    'es': 'La direccion de correo del supervisor no es valida.',
    'it': 'Lindirizzo email del supervisore non e valido.',
    'ru': 'Адрес email супервизора недействителен.',
    'hi': 'पर्यवेक्षक का ईमेल पता अमान्य है।',
    'el': 'Η διευθυνση email του εποπτη δεν ειναι εγκυρη.',
    'zh': '督导邮箱地址无效。',
    'tr': 'Supervisor e-posta adresi gecersiz.',
    'ja': 'スーパーバイザーのメールアドレスが無効です。',
  },
  'status_supervisor_consent_failed': {
    'en': 'Could not send consent information to backend.',
    'de':
        'Einwilligungsinformationen konnten nicht ans Backend gesendet werden.',
  },
  'status_supervisor_consent_saved_only': {
    'en': 'Consent updated. Pairing skipped because consent is off.',
    'de':
        'Einwilligung aktualisiert. Verknupfung ubersprungen, da Consent aus ist.',
  },
  'status_supervisor_missing_pair_fields': {
    'en': 'Supervisor email and 5-digit code are required.',
    'de': 'Supervisor-E-Mail und 5-stelliger Code sind erforderlich.',
  },
  'status_supervisor_pair_failed': {
    'en': 'Consent saved, but supervisor pairing failed.',
    'de':
        'Einwilligung gespeichert, aber Supervisor-Verknupfung fehlgeschlagen.',
  },
  'status_supervisor_pair_saved': {
    'en': 'Supervisor data sent and pairing saved.',
    'de': 'Supervisor-Daten gesendet und Verknupfung gespeichert.',
  },
  'status_supervisor_sync_unexpected': {
    'en': 'Supervisor sync failed due to an unexpected error.',
    'de':
        'Supervisor-Abgleich wegen eines unerwarteten Fehlers fehlgeschlagen.',
  },
  'status_consent_required_for_apply': {
    'en': 'Implementation requires confirmed learner consent.',
    'de': 'Zum Umsetzen ist die bestatigte Einwilligung erforderlich.',
  },
  'status_progress_reference_required': {
    'en': 'Progress reference is required.',
    'de': 'Fortschrittsreferenz ist erforderlich.',
  },
};

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
