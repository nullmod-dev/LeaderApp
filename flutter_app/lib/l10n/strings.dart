/// Every user-facing string in the app. Widgets import `S` and read a key —
/// no Arabic literals in widget code. When real localization is wired later,
/// only this file changes.
///
/// Keys grouped by feature.
abstract final class S {
  // ---------- App-wide ----------
  //
  // The product name, once. Every brand mention reads these — never a
  // literal. `MTM` survives only in protocol identifiers (team-code prefix,
  // plan ids, persisted keys, env keys), which are not the brand.
  static const productNameAr = 'ليدر';
  static const productNameEn = 'Leader';
  static const appName = productNameAr;
  static const retry = 'إعادة المحاولة';
  static const cancel = 'إلغاء';

  /// The dismiss button of a confirmation whose confirm label itself begins
  /// with «إلغاء» — cancelling an invitation, cancelling a replacement — so
  /// the two buttons never read as the same word.
  static const dismiss = 'تراجع';
  static const save = 'حفظ';
  static const confirm = 'تأكيد';
  static const close = 'إغلاق';
  static const search = 'بحث';
  static const filter = 'تصفية';

  /// Names a row of dataset filters for a screen reader. Generic on purpose:
  /// every list in the app filters by a state word, and one announcement is
  /// what makes them one control.
  static const filterByStatus = 'تصفية حسب الحالة';
  static const all = 'الكل';
  static const more = 'المزيد';
  static const details = 'التفاصيل';
  static const edit = 'تعديل';
  static const delete = 'حذف';
  static const create = 'إنشاء';
  static const done = 'تم';
  static const back = 'رجوع';
  static const next = 'التالي';
  static const previous = 'السابق';
  static const copy = 'نسخ';
  static const copied = 'تم النسخ';
  static const yes = 'نعم';
  static const no = 'لا';
  static const now = 'الآن';
  static const empty = 'لا يوجد بعد';

  // ---------- Bottom nav ----------
  static const navHome = 'الرئيسية';
  static const navDetachment = 'المفرزة';
  static const navWorkshop = 'الورشة';
  static const navMore = 'المزيد';

  // ---------- Detachment tabs ----------
  static const detachmentTeam = 'الفريق وأدواره';
  static const detachmentShifts = 'الشفتات';
  static const detachmentStorage = 'المخزن';
  static const detachmentStats = 'الإحصائيات';

  // ---------- Workshop tabs ----------
  static const workshopTeam = 'الفريق وأدواره';
  static const workshopMembers = 'الأعضاء والضيوف';
  static const workshopStats = 'الإحصائيات';

  // ---------- Auth ----------
  static const login = 'تسجيل الدخول';
  static const loginTitle = 'مرحباً بك في $productNameAr';
  static const loginSub = 'سجّل الدخول لإدارة فرقك وعملياتك';
  // Email only: sign-in has no username identity (Point 18B). A username
  // label here would promise an authentication path that does not exist.
  static const emailLabel = 'البريد الإلكتروني';
  static const signupEmailLabel = 'البريد الإلكتروني';
  static const passwordLabel = 'كلمة المرور';
  static const forgotPassword = 'نسيت كلمة المرور؟';
  // The Login CTA, and the same words wherever else the app offers a way
  // back in (session expired, the signed-out profile row). Written once as
  // [login] so the button and the screen can never drift apart.
  static const signIn = login;
  static const noAccount = 'ليس لديك حساب؟';
  static const createAccount = 'إنشاء حساب';

  // ---------- Development demo accounts (debug builds only) ----------
  //
  // Never present in a release artefact: every use sits behind
  // `demoAccountsAllowed` (`core/env/build_mode.dart`), a compile-time
  // constant that is `false` outside debug, so these constants are
  // tree-shaken out along with the section that renders them.
  static const demoAccountsTitle = 'حسابات التجربة';
  static const demoAccountsNote = 'متاحة في وضع التطوير فقط.';
  static const demoSuperAdmin = 'مدير المنصة';
  static const demoSuperAdminSub = 'المنصة كاملة — بلا فريق';
  static const demoMainAdmin = 'المدير الرئيسي';
  static const demoMainAdminSub = 'صلاحيات كاملة داخل الفريق';
  static const demoSimpleAdmin = 'مدير مساعد';
  static const demoSimpleAdminSub = 'صلاحيات محدودة ومفرزتان';

  /// **Retained only as the expected-absent text of a regression guard.**
  ///
  /// Login once offered "start a customer demo" directly. It does not any
  /// more — the trial is offered once, to a verified unlinked identity, on the
  /// onboarding chooser — and two tests assert this label appears nowhere on
  /// Login. Deleting the constant would delete the assertion with it, so it
  /// stays; nothing renders it.
  static const customerDemoAction = 'تجربة $productNameAr كعميل';
  static const customerDemoStarting = 'جارٍ تجهيز مساحة التجربة…';
  static const customerDemoUnavailable = 'تجربة العملاء غير متاحة حاليًا.';
  static const customerDemoExit = 'إنهاء التجربة';
  static const demoTrialNotice =
      'وضع التجربة — بيانات نموذجية داخل مساحة مستقلة، ولا تُحفظ خارجها.';
  static const demoExitConfirm =
      'ستنتهي التجربة وتُحذف التغييرات التجريبية. يمكنك الدخول مجددا واختيار فريق أو تجربة جديدة.';

  // ---------- Super Admin platform surface (Points 4–5) ----------
  //
  // The SaaS control plane. Short navigation labels, because the compact bar
  // shows all four at 320 dp; the fuller wording lives in each page's title.
  static const platformNavOverview = 'المنصة';
  static const platformNavTenants = 'الفرق';
  static const platformNavOperations = 'العمليات';
  static const platformNavMore = 'المزيد';
  static const platformNavLabel = 'أقسام المنصة';

  static const platformBrand = 'منصة $productNameAr';
  static const platformAccountAction = 'حساب مدير المنصة';

  static const platformOverviewTitle = 'المنصة';
  static const platformOverviewLead =
      'نظرة سريعة على حالة خدمة $productNameAr واشتراكاتها وما يحتاج إلى قرار.';
  static const platformOverviewRefresh = 'تحديث ملخص المنصة';
  static const platformOverviewUpdatedNow = 'حُدّث الآن';
  static const platformOverviewUpdatedPrefix = 'آخر تحديث قبل ';
  static const platformOverviewMinute = ' د';
  static const platformOverviewHour = ' س';
  static const platformOverviewDay = ' ي';
  static const platformOverviewAgoPrefix = 'قبل ';
  static const platformOverviewMinutesWord = ' دقيقة';
  static const platformOverviewHoursWord = ' ساعة';
  static const platformOverviewDaysWord = ' يوم';
  static const platformOverviewOfflineCached =
      'لا يوجد اتصال — تُعرض نسخة محفوظة في هذه الجلسة.';
  static const platformOverviewMinimalTitle = 'لا توجد بيانات منصة بعد';
  static const platformOverviewMinimalBody =
      'وصل الملخص بنجاح، لكنه لا يحتوي على فرق أو نشاط أو إشارات حالة.';
  static const platformOverviewAttention = 'يحتاج إلى انتباه';
  static const platformOverviewSummary = 'ملخص المنصة';

  /// The metric label for the customer teams the platform serves.
  /// «SaaS» is the business model, not a word a control panel should print.
  static const platformOverviewTenants = 'الفرق المشتركة';
  static const platformOverviewSubscriptions = 'اشتراكات نشطة';
  static const platformOverviewTrials = 'فترات تجريبية';
  static const platformOverviewTenantAttention = 'سماح أو إيقاف';
  static const platformOverviewDemos = 'تجارب عملاء نشطة';
  static const platformOverviewGrace = 'سماح';
  static const platformOverviewSuspended = 'موقوف';
  static const platformOverviewSimpleDemo = 'بسيطة';
  static const platformOverviewFullDemo = 'كاملة';
  static const platformOverviewDemoExpiring = 'تنتهي قريبا';
  static const platformOverviewOpenSection = 'فتح القسم';
  static const platformOverviewHealth = 'حالة المنصة';
  static const platformOverviewHealthHealthy = 'سليمة';
  static const platformOverviewHealthDegraded = 'متأثرة جزئيا';
  static const platformOverviewHealthUnavailable = 'غير متاحة';
  static const platformOverviewHealthUnknown = 'غير معروفة';
  static const platformOverviewActivity = 'آخر النشاطات';
  static const platformOverviewNoActivity = 'لا توجد نشاطات حديثة.';
  static const platformOverviewUsage = 'الاستخدام والسعة';
  static const platformOverviewStorage = 'التخزين عبر المنصة';
  static const platformOverviewStorageOf = ' من ';
  static const platformOverviewGigabyte = ' غ.ب';

  // ---------- Platform vocabulary shared by every control-plane screen ----------
  //
  // Phase 2 of the UI quality programme. The surface used to spell a snapshot
  // time as «٢٠٢٦/٠٩/٠٨ · ١٥:٠٤ UTC» — an ISO-ordered date, a separator that
  // renders as the Arabic-Indic zero, and a bare Latin token — inside an
  // interface that writes «٨ أيلول ٢٠٢٦» everywhere else.
  static const platformTimeUtc = 'بتوقيت UTC';

  /// The overview's one refresh control, beside the freshness it refreshes.
  /// The app-bar icon it replaced was the second of two affordances for the
  /// same action, and the further of the two from the sentence that made an
  /// operator want it.
  static const platformOverviewRefreshNow = 'تحديث';
  static const platformOverviewAttentionClearTitle = 'لا شيء يحتاج إلى قرار';
  static const platformOverviewAttentionClearBody =
      'لا توجد اشتراكات في فترة سماح ولا فرق موقوفة ولا تنبيهات أمنية مفتوحة '
      'في آخر لقطة متاحة.';
  static const platformOverviewDeletionPending = 'بانتظار الحذف';
  static const platformOverviewRisk = 'فرق تحتاج إلى متابعة';
  static const platformOverviewRiskClear = 'لا فرق موقوفة أو في فترة سماح.';
  static const platformOverviewScale = 'حجم المنصة';
  static const platformOverviewShortcuts = 'الحالة التشغيلية';

  // ---------- Operations: five groups, not one undifferentiated list ----------
  static const platformOperationsGroupMonitor = 'المراقبة';
  static const platformOperationsGroupCustomers = 'العملاء والتجارب';
  static const platformOperationsGroupCommerce = 'الجانب التجاري';
  static const platformOperationsGroupCritical = 'صلاحيات حسّاسة';
  static const platformOperationsGroupReview = 'المراجعة والتدقيق';
  static const platformOperationsCriticalNote =
      'يفتح هذا القسم صلاحية استثنائية على بيانات عميل، وكل استخدام له يُسجَّل '
      'باسم من طلبه.';
  static const platformOperationsBreakGlassActive = 'وصول نشط';
  static const platformOperationsDemoRunning = 'جلسات نشطة';
  static const platformOperationsCommerceLive = 'عروض مفعّلة';

  /// Short purpose lines for the operations index.
  ///
  /// Each row used to repeat the *destination page's own* lead paragraph — a
  /// two-line explanation of a screen the operator has not opened yet — which
  /// is what made the index read as documentation rather than navigation.
  static const platformOperationsRowHealth = 'إشارات الخدمة وحالتها';
  static const platformOperationsRowSecurity = 'التنبيهات الأمنية الحالية';
  static const platformOperationsRowDemo = 'السياسة والجلسات النشطة';
  static const platformOperationsRowCommerce = 'الأسعار والعروض والكوبونات';
  static const platformOperationsRowAudit = 'سجل الإجراءات الإدارية ومن نفّذها';
  static const platformOperationsRowReports = 'تقارير حالة المنصة';

  static const platformTenantsTitle = 'الفرق المشتركة';
  static const platformTenantsLead =
      'كل فريق مشترك في $productNameAr يُدار من هنا: إنشاؤه، مديره الأول، رمز الفريق، '
      'اشتراكه وحدوده ودورة حياته.';
  static const platformOperationsTitle = 'عمليات المنصة';
  static const platformOperationsLead =
      'الوحدات الإدارية التي تخدم المنصة كلها، ولا يحتاج أي منها مكانا دائما في '
      'شريط التنقل.';

  /// The state a section carries while its module belongs to a later stage.
  /// Not «لا توجد بيانات»: nothing failed and nothing is empty — the module is
  /// simply not built in this build, and saying so plainly is the honest state.
  static const platformSectionPendingBadge = 'قيد الإعداد';
  static const platformSectionPendingTitle = 'هذه الوحدة لم تُبنَ بعد';
  static const platformSectionPendingBody =
      'لا تُعرض هنا قائمة ولا إجراء قبل جاهزية الوحدة، حتى لا يكون في الواجهة زر '
      'لا يفعل شيئا.';
  static const platformSectionPlanned = 'ما ستضمّه هذه الوحدة';

  static const platformOpsDemo = 'الحسابات التجريبية';
  static const platformOpsSubscriptions = 'الاشتراكات والفترات التجريبية';
  static const platformOpsHealth = 'صحة المنصة';
  static const platformOpsAlerts = 'التنبيهات';
  static const platformOpsAudit = 'سجل التدقيق';
  static const platformAuditLead = 'راجع سجل الإجراءات الإدارية ومن نفّذها.';
  static const platformAuditTitle = 'سجل التدقيق';
  static const platformOpsBreakGlass = 'الوصول الطارئ';
  static const platformOpsReports = 'تقارير المنصة';

  // ---------- Customer Demo management (Super Admin only) ----------
  //
  // The only place in the product where Demo *policy* is administered. The
  // user-facing side of the feature — the one «تجربة ليدر» entry and the
  // in-trial banner — says nothing about policy, and nothing outside this
  // screen offers a Demo control.
  static const platformDemoTitle = 'إدارة الحسابات التجريبية';
  static const platformDemoLead =
      'سياسة التجربة العامة والجلسات التجريبية النشطة.';
  static const platformDemoPolicySection = 'السياسة';
  static const platformDemoAvailability = 'إتاحة التجربة';
  static const platformDemoAvailabilityOn = 'مفعّلة — يمكن بدء تجارب جديدة';
  static const platformDemoAvailabilityOff =
      'معطّلة — لا تُقبل تجارب جديدة، والجلسات الحالية تكمل مدتها';
  static const platformDemoDuration = 'المدة الافتراضية';
  static const platformDemoDurationNote =
      'تُطبَّق على الجلسات الجديدة فقط. الجلسات النشطة تحتفظ بموعد انتهائها.';
  static const platformDemoDurationDecrease = 'إنقاص المدة';
  static const platformDemoDurationIncrease = 'زيادة المدة';
  static const platformDemoDurationAtMinimum = 'أقل مدة ممكنة';
  static const platformDemoPolicyUpdatedBy = 'آخر تعديل';
  static const platformDemoPolicyNeverUpdated = 'لم تُعدَّل بعد';
  static const platformDemoRevision = 'مراجعة السياسة';

  static const platformDemoSummarySection = 'الجلسات';
  static const platformDemoCountActive = 'نشطة';
  static const platformDemoCountExpired = 'منتهية';
  static const platformDemoCountTerminated = 'مُنهاة إداريا';

  static const platformDemoActiveSection = 'الجلسات النشطة';
  static const platformDemoNoActive = 'لا توجد جلسات تجريبية نشطة الآن.';
  static const platformDemoSessionStarted = 'البدء';
  static const platformDemoSessionExpires = 'الانتهاء';
  static const platformDemoSessionRemaining = 'المتبقي';
  static const platformDemoSessionEndsSoon = 'على وشك الانتهاء';
  static const platformDemoTerminate = 'إنهاء الجلسة';

  static const platformDemoMaintenanceSection = 'إجراءات عامة';
  static const platformDemoTerminateAll = 'إنهاء جميع التجارب النشطة';
  static const platformDemoTerminateAllSub =
      'يُخرج كل مستخدم من تجربته فورا. الحسابات الحقيقية لا تتأثر.';
  static const platformDemoCleanExpired = 'تنظيف الجلسات المنتهية';
  static const platformDemoCleanExpiredSub =
      'يحذف سجلات الجلسات التي انتهت مدتها. الجلسات المُنهاة إداريا تبقى للمراجعة.';

  // Confirmations. Each names what changes and what does not, like every other
  // platform confirmation in this app.
  static const platformDemoDisableConfirmTitle = 'تعطيل التجربة؟';
  static const platformDemoDisableConfirmChange =
      'لن يتمكن أي مستخدم من بدء تجربة جديدة.';
  static const platformDemoDisableConfirmUnchanged =
      'الجلسات التجريبية النشطة تكمل مدتها ولا تُنهى.';
  static const platformDemoDisableConfirmAction = 'تعطيل';

  static const platformDemoTerminateConfirmTitle = 'إنهاء هذه الجلسة؟';
  static const platformDemoTerminateConfirmChange =
      'يخرج المستخدم من التجربة فورا وتُحذف بياناتها التجريبية.';
  static const platformDemoTerminateConfirmUnchanged =
      'حسابه الحقيقي يبقى كما هو، ويمكنه الانضمام برمز فريق أو بدء تجربة جديدة.';

  static const platformDemoTerminateAllConfirmTitle =
      'إنهاء جميع التجارب النشطة؟';
  static const platformDemoTerminateAllConfirmChange =
      'تُنهى كل الجلسات التجريبية النشطة فورا.';
  static const platformDemoTerminateAllConfirmUnchanged =
      'سياسة الإتاحة والمدة الافتراضية لا تتغير، والحسابات الحقيقية لا تتأثر.';

  static const platformDemoCleanConfirmTitle = 'تنظيف الجلسات المنتهية؟';
  static const platformDemoCleanConfirmChange =
      'تُحذف سجلات الجلسات التي انتهت مدتها.';
  static const platformDemoCleanConfirmUnchanged =
      'الجلسات النشطة والمُنهاة إداريا تبقى في القائمة.';

  // Outcomes.
  static const platformDemoEnabledDone = 'تم تفعيل التجربة.';
  static const platformDemoDisabledDone = 'تم تعطيل التجربة.';
  static const platformDemoDurationDone = 'تم تحديث المدة الافتراضية.';
  static const platformDemoTerminatedDone = 'تم إنهاء الجلسة.';
  static const platformDemoTerminatedAllDone = 'تم إنهاء %d جلسة نشطة.';
  static const platformDemoNothingToTerminate = 'لا توجد جلسات نشطة لإنهائها.';
  static const platformDemoCleanedDone = 'تم حذف %d سجل منتهٍ.';
  static const platformDemoNothingToClean = 'لا توجد سجلات منتهية.';
  static const platformDemoNotAuthorized = 'هذا الإجراء لمسؤول المنصة وحده.';
  static const platformDemoSessionGone = 'لم تعد هذه الجلسة نشطة.';

  // ---------- Point 13 — Platform Reports ----------
  static const platformReportsLead =
      'لقطات وملخصات للطبقة الإدارية للمنصة، للقراءة فقط ولمسؤول المنصة وحده.';
  static const platformReportsSectionCurrent = 'الحالة الحالية';
  static const platformReportsSectionPeriod = 'خلال فترة';
  static const platformReportKindSnapshot = 'لقطة حالية';
  static const platformReportKindPeriod = 'حسب الفترة';

  static const platformReportSubscriptionsTitle = 'الاشتراكات';
  static const platformReportSubscriptionsQuestion =
      'ما حالة اشتراكات الفرق الحالية؟';
  static const platformReportUsageLimitsTitle = 'الاستخدام والحدود';
  static const platformReportUsageLimitsQuestion =
      'أي الفرق يقترب من حدوده أو يتجاوزها؟';
  static const platformReportFeatureAvailabilityTitle = 'إتاحة الميزات';
  static const platformReportFeatureAvailabilityQuestion =
      'ما الميزات المفعّلة لكل فريق؟';
  static const platformReportActivityTitle = 'نشاط المنصة';
  static const platformReportActivityQuestion =
      'كم إجراءً إدارياً وقع خلال فترة معيّنة؟';

  static const platformReportUnsupportedTitle = 'تقرير غير مدعوم';
  static const platformReportUnsupportedBody =
      'هذا النوع من التقارير غير معروف في هذا الإصدار من التطبيق.';
  static const platformReportBackToCatalogue = 'العودة إلى تقارير المنصة';

  static const platformReportScopeNote =
      'يشمل الفرق النشطة والمعلّقة وقيد الحذف، ولا يشمل الفرق المحذوفة.';
  static const platformReportSourceAudit = 'المصدر: سجل تدقيق المنصة';
  static const platformReportLocalTimeNote = 'حسب توقيت الجهاز';
  static const platformReportStaleNote = 'تُعرض نسخة محفوظة من التقرير.';
  static const platformReportOfflineCachedNote =
      'أنت غير متصل. تُعرض آخر نسخة محفوظة من التقرير.';
  static const platformReportRefreshing = 'يُحدَّث الآن…';

  static const platformReportFiltersButton = 'تصفية';
  static const platformReportFiltersApply = 'تطبيق التصفية';
  static const platformReportFiltersClearAll = 'مسح الكل';
  static const platformReportFiltersAll = 'الكل';

  static const platformReportRowsLabel = 'الفرق';
  static const platformReportShowMore = 'عرض المزيد';
  static const platformReportLoadingMore = 'جارٍ تحميل المزيد…';
  static const platformReportOpenTenant = 'فتح تفاصيل الفريق';

  static const platformReportEmptyTeamsTitle = 'لا توجد فرق مسجلة';
  static const platformReportEmptyTeamsBody =
      'ستظهر هنا الفرق التي يشملها هذا التقرير عند وجودها.';
  static const platformReportEmptyActivityTitle =
      'لم يُسجَّل نشاط في هذه الفترة';
  static const platformReportEmptyActivityBody =
      'جرّب توسيع الفترة الزمنية المحددة.';
  static const platformReportWidenRange = 'توسيع الفترة';
  static const platformReportFilteredEmptyTitle =
      'لا نتائج ضمن عوامل التصفية الحالية';
  static const platformReportFilteredEmptyBody =
      'جرّب تعديل عوامل التصفية أو مسحها.';
  static const platformReportOfflineNoDataTitle = 'التقرير غير متاح دون اتصال';
  static const platformReportOfflineNoDataBody =
      'يحتاج هذا التقرير قراءة مباشرة من الخادم. أعد المحاولة عند عودة الاتصال.';
  static const platformReportNotPermittedTitle =
      'لا تملك صلاحية عرض هذا التقرير';
  static const platformReportFailureTitle = 'تعذّر تحميل التقرير';
  static const platformReportFailureBody = 'حاول مرة أخرى.';
  static const platformReportRetry = 'إعادة المحاولة';
  static const platformReportMustReloadTitle = 'تغيّرت بيانات التقرير';
  static const platformReportReload = 'إعادة التحميل';
  static const platformReportPageFailedNote =
      'تعذّر تحميل صفحة إضافية. لم تُفقد الصفوف المحمّلة.';
  static const platformReportOfflinePagingDisabled =
      'تحميل المزيد غير متاح دون اتصال.';
  static const platformReportUnsupportedValuesNote = 'غير مدعوم في هذا الإصدار';
  static const platformReportUnsupportedKeysNote =
      'بعض الحدود في هذه اللقطة غير مدعومة في هذا الإصدار ولا تُعرض.';
  static const platformReportUnsupportedFeatureKeysNote =
      'بعض الميزات في هذه اللقطة غير مدعومة في هذا الإصدار ولا تُعرض.';
  static const platformReportOtherActions = 'إجراءات أخرى';

  // ≥900 dp dense-row/table column headers (Point 13C §10) — supplement the
  // same facts the compact row tile already states, never new data.
  static const platformReportColumnTeam = 'الفريق';
  static const platformReportColumnSubscriptionStatus = 'حالة الاشتراك';
  static const platformReportColumnPlan = 'الخطة';
  static const platformReportColumnDate = 'التاريخ';
  static const platformReportColumnUsage = 'الاستخدام';
  static const platformReportColumnBand = 'النطاق';

  static const platformReportNoPlan = 'بلا خطة';
  static const platformUsageBandWithin = 'ضمن الحد';
  static const platformUsageBandAt = 'عند الحد';
  static const platformUsageBandOver = 'فوق الحد';
  static const platformUsageBandNoLimit = 'بلا خطة';
  static const platformUsageOverridden = 'مخصص';
  static const platformFeatureEnabled = 'مفعّلة';
  static const platformFeatureDisabled = 'معطّلة';
  static const platformFeatureUnknownState = 'غير معروفة';
  static const platformActivityGovernanceNote =
      'أحداث حوكمة مسجلة، وليست حوادث أمنية.';

  // ---------- Point 12 — Break-glass emergency access ----------
  static const breakGlassTitle = 'الوصول الطارئ';
  static const breakGlassLead =
      'وصول استثنائي مؤقت وللقراءة فقط، مرتبط بجلستك وبفريق نشط واحد.';
  static const breakGlassCurrentState = 'الحالة الحالية';
  static const breakGlassNoneTitle = 'لا يوجد وصول طارئ نشط';
  static const breakGlassNoneBody =
      'يُستخدم في حالة إدارية استثنائية، وينتهي تلقائياً في الوقت الذي يحدده الخادم.';
  static const breakGlassRequestAction = 'طلب وصول طارئ';
  static const breakGlassFactsTitle = 'حدود الوصول';
  static const breakGlassFactReadOnly = 'قراءة فقط للسجلات التشغيلية.';
  static const breakGlassFactOneTenant = 'مقيد بفريق نشط واحد وبهذه الجلسة.';
  static const breakGlassFactExpiry = 'ينتهي تلقائياً؛ لا يوجد تجديد.';
  static const breakGlassFactEntitlements =
      'لا يغيّر الاشتراك أو الميزات أو حدود الخطة.';
  static const breakGlassFactAudit =
      'التخويل والتدقيق يتمّان في المنصة، لا في هذا التطبيق.';
  static const breakGlassAuditAction = 'عرض سجل التدقيق';
  static const breakGlassActiveTitle = 'الوصول الطارئ نشط';
  static const breakGlassReadOnlyScope = 'قراءة فقط — السجلات التشغيلية';
  static const breakGlassTargetTeam = 'الفريق المستهدف';
  static const breakGlassIssuedAt = 'بدء الوصول';
  static const breakGlassExpiresAt = 'ينتهي في';
  static const breakGlassRemainingTime = 'الوقت المتبقي';
  static const breakGlassRemainingEnded = 'انتهت المدة';
  static const breakGlassRemainingLessThanMinute = 'ينتهي خلال أقل من دقيقة';
  static const breakGlassRemainingOneMinute = 'ينتهي خلال دقيقة واحدة';
  static const breakGlassRemainingTwoMinutes = 'ينتهي خلال دقيقتين';
  static const breakGlassRemainingMinutes = 'ينتهي خلال %d دقائق';
  static const breakGlassRemainingLessThanHour = 'ينتهي خلال أقل من ساعة';
  static const breakGlassRemainingOneHour = 'ينتهي خلال ساعة واحدة';
  static const breakGlassRemainingTwoHours = 'ينتهي خلال ساعتين';
  static const breakGlassRemainingHours = 'ينتهي خلال %d ساعات';
  static const breakGlassRemainingHoursMany = 'ينتهي خلال %d ساعة';
  static const breakGlassGrantId = 'معرّف المنحة';
  static const breakGlassReasonLabel = 'السبب الإداري';
  static const breakGlassVerified = 'مؤكد من الخادم';
  static const breakGlassUnverified = 'غير مؤكد — غير قابل للاستخدام';
  static const breakGlassUnverifiedShort = 'غير مؤكد';
  static const breakGlassNearExpiry = 'ينتهي خلال أقل من ١٠ دقائق.';
  static const breakGlassEndAction = 'إنهاء الوصول';
  static const breakGlassEndFullAction = 'إنهاء الوصول الطارئ';
  static const breakGlassEndedTitle = 'انتهى الوصول الطارئ';
  static const breakGlassExpiredTitle = 'انتهت مدة الوصول';
  static const breakGlassRevokedTitle = 'سُحب الوصول الطارئ';
  static const breakGlassTenantUnavailableTitle = 'الفريق لم يعد متاحاً';
  static const breakGlassUnsupportedTitle = 'حالة وصول غير مدعومة';
  static const breakGlassOfflineTitle = 'الوصول الطارئ غير متاح دون اتصال';
  static const breakGlassStaleTitle = 'تعذّر تأكيد الحالة الحالية';
  static const breakGlassFailureTitle = 'تعذّر تحميل الوصول الطارئ';
  static const breakGlassNotPermittedTitle = 'غير مسموح';
  static const breakGlassRetry = 'إعادة المحاولة';
  static const breakGlassRequestTitle = 'طلب الوصول الطارئ';
  static const breakGlassSelectTeam = 'اختر فريقاً نشطاً';
  static const breakGlassNoEligibleTeams = 'لا توجد فرق نشطة مؤهلة.';
  static const breakGlassReasonHint = 'اشرح الحاجة الإدارية بوضوح';
  static const breakGlassReasonRequired = 'السبب الإداري مطلوب.';
  static const breakGlassReasonTooLong = 'يجب ألا يتجاوز السبب ٢٨٠ حرفاً.';
  static const breakGlassServerDuration =
      'يحدد الخادم وقت الانتهاء بعد التفعيل.';
  static const breakGlassActivateAction = 'تفعيل الوصول الطارئ';
  static const breakGlassRecentAuthTitle = 'يلزم تسجيل دخول حديث';
  static const breakGlassRecentAuthBody =
      'لا يمكن للتطبيق إثبات حداثة المصادقة. سجّل الخروج ثم الدخول من جديد، وأنشئ طلباً جديداً.';
  static const breakGlassOfflineAction =
      'يتطلب هذا الإجراء اتصالاً بالخادم، ولن يُضاف إلى قائمة المزامنة.';
  static const breakGlassStaleAction =
      'تغيّرت الحالة. تم تحديثها؛ راجعها قبل المحاولة.';
  static const breakGlassNotPermittedAction =
      'لا تسمح الجلسة الحالية بهذا الإجراء.';
  static const breakGlassFailedAction =
      'تعذّر إتمام الإجراء بأمان. لم تتغير الحالة.';
  static const breakGlassEndedSnack = 'انتهى الوصول الطارئ.';
  static const breakGlassExpiredForTeam = 'انتهى الوصول الطارئ إلى %s.';
  static const breakGlassLoadRetryBody =
      'لم يُمنح أي وصول. أعد المحاولة بعد التحقق من الاتصال.';
  static const breakGlassLoadRefreshBody =
      'لم يُمنح أي وصول. حدّث الحالة قبل أي محاولة جديدة.';
  static const breakGlassStaleNoGrantBody =
      'تعذّر إثبات عدم وجود منحة نشطة، لذلك لا يمكن طلب وصول جديد الآن.';
  static const breakGlassExpiredBody = 'انتهت المدة التي حددها الخادم في %s.';
  static const breakGlassTenantUnavailableBody =
      'توقفت قابلية الاستخدام فوراً. الوصول الطارئ لا يتجاوز التعليق أو الحذف.';
  static const breakGlassUnsupportedBody =
      'لم يتعرف هذا الإصدار إلى الحالة أو النطاق، لذلك لم يُمنح أي وصول.';
  static const breakGlassActiveBody =
      'منح الخادم هذه الجلسة نطاقاً مؤقتاً للقراءة فقط.';
  static const breakGlassUnverifiedBody =
      'هذه نسخة غير مؤكدة. تُعرض للوعي فقط ولا تمنح وصولاً.';
  static const breakGlassTenantChanged = 'تغيّرت حالة الفريق، ولم يُرسل الطلب.';
  static const breakGlassActivationChange =
      'وصول مؤقت للقراءة فقط إلى السجلات التشغيلية لهذا الفريق.';
  static const breakGlassActivationUnchanged =
      'تبقى الميزات وحدود الخطة وقيود دورة حياة الفريق نافذة.';
  static const breakGlassActivationEffective =
      'يحدد الخادم وقت الانتهاء. السبب إداري، والتفعيل خاضع لتخويل الخادم وتدقيقه.';
  static const breakGlassSearchTeam = 'البحث باسم الفريق';
  static const breakGlassTenantActive = 'نشط';
  static const breakGlassTenantLoadFailure =
      'تعذّر تحميل الفرق النشطة. لم يُمنح أي وصول.';
  static const breakGlassEndTitle = 'إنهاء الوصول إلى %s؟';
  static const breakGlassEndChange =
      'ينتهي الوصول الاستثنائي فور تأكيد الخادم، ولن يمكن استخدامه بعدها.';
  static const breakGlassEndUnchanged =
      'لا يغيّر هذا حسابات الفريق أو إعداداته.';
  static const breakGlassEndEffective =
      'الاستعادة تتطلب طلباً جديداً بسبب جديد.';
  static const breakGlassStripUnverified = 'غير مؤكد وغير قابل للاستخدام';
  static const breakGlassStripNearExpiry = 'ينتهي قريباً';
  static const breakGlassOpenManagement = 'فتح إدارة الوصول الطارئ';
  static const breakGlassEndedByInitiator = 'أُنهي الوصول بواسطة مسؤول المنصة.';
  static const breakGlassEndedWithSession =
      'انتهى الوصول بانتهاء الجلسة المرتبطة به.';
  static const breakGlassEndedTenantUnavailable =
      'توقف الوصول لأن الفريق لم يعد في حالة نشطة.';
  static const breakGlassEndedRevoked =
      'سحبت المنصة هذا الوصول، ولم يعد قابلاً للاستخدام.';
  static const breakGlassEndedUnknown =
      'انتهى هذا الوصول ولم يعد قابلاً للاستخدام.';
  static const breakGlassProblemTenantNotFound =
      'لم يعد الفريق موجوداً. حدّث القائمة.';
  static const breakGlassProblemTenantNotEligible =
      'حالة الفريق لا تسمح بالوصول الطارئ.';
  static const breakGlassProblemTenantDeleted =
      'الفريق محذوف ولا يمكن إعادة إنشاء موارده.';
  static const breakGlassProblemInvalidReason =
      'أدخل سبباً إدارياً صالحاً لا يتجاوز ٢٨٠ حرفاً.';
  static const breakGlassProblemInvalidScope =
      'نطاق الوصول غير مدعوم، لذلك لم يُمنح أي وصول.';
  static const breakGlassProblemAlreadyActive =
      'يوجد وصول طارئ قد يظل نشطاً. راجع الحالة الحالية.';
  static const breakGlassProblemNotActive =
      'لم يعد هذا الوصول نشطاً. تم تحديث الحالة.';
  static const breakGlassProblemIdempotency =
      'تعارض معرّف العملية. راجع الحالة قبل طلب جديد.';
  static const breakGlassSignOutWarning =
      'ينهي تسجيل الخروج أي وصول طارئ مرتبط بهذه الجلسة.';

  // ---------- Point 10 — Platform Health & Security ----------
  static const platformOperationsCurrentModules = 'وحدات العمليات المتاحة';
  static const platformOperationsCurrentLead =
      'راجع أحدث لقطة لصحة المنصة والتنبيهات الأمنية الحالية.';
  static const platformOperationsOpenModule = 'فتح الوحدة';
  static const platformOperationsFutureTitle = 'وحدات لاحقة';
  static const platformOperationsFutureBody =
      'تقارير المنصة ليست متاحة في هذا الإصدار.';

  static const platformHealthTitle = 'صحة المنصة';
  static const platformHealthLead =
      'أحدث لقطة متاحة لإشارات الخدمة المعروفة، من دون ادعاء مراقبة مباشرة.';
  static const platformHealthOverall = 'الحالة العامة';
  static const platformHealthSignals = 'إشارات الصحة';
  static const platformHealthSnapshot = 'لقطة الصحة';
  static const platformHealthUpdated = 'وقت اللقطة';
  static const platformHealthPartialTitle = 'بيانات الصحة جزئية';
  static const platformHealthPartialBody =
      'بعض الإشارات متاحة، لكن اللقطة لا تحتوي على الحالة الكاملة.';
  static const platformHealthOfflineCached =
      'لا يوجد اتصال — تُعرض آخر لقطة متاحة في هذه الجلسة.';
  static const platformHealthOfflineTitle = 'لا يمكن جلب صحة المنصة دون اتصال';
  static const platformHealthOfflineBody =
      'لا توجد لقطة محفوظة يمكن عرضها الآن. أعد المحاولة بعد عودة الاتصال.';
  static const platformHealthFailureTitle = 'تعذّر تحميل صحة المنصة';
  static const platformHealthFailureBody =
      'لم تُحمّل لقطة الصحة. هذا لا يعني أن المنصة متدهورة.';
  static const platformHealthNoSignalsTitle = 'لا توجد إشارات صحة قابلة للعرض';
  static const platformHealthNoSignalsBody =
      'وصلت اللقطة من دون إشارات معروفة، لذلك تبقى الحالة غير معروفة.';
  static const platformHealthFresh = 'لقطة حديثة';
  static const platformHealthStale = 'لقطة قديمة';
  static const platformHealthStatusHealthy = 'سليمة';
  static const platformHealthStatusDegraded = 'متأثرة جزئيا';
  static const platformHealthStatusUnavailable = 'غير متاحة';
  static const platformHealthStatusUnknown = 'غير معروفة';
  static const platformHealthAttention = 'يحتاج إلى انتباه';
  static const platformHealthObserved = 'رُصدت';
  static const platformHealthRefresh = 'تحديث صحة المنصة';

  static const platformSecurityTitle = 'أمن المنصة';
  static const platformSecurityLead =
      'تنبيهات أمنية حالية من أحدث لقطة متاحة، للقراءة والمتابعة فقط.';
  static const platformSecurityCurrentState = 'الحالة الأمنية الحالية';
  static const platformSecurityAlerts = 'التنبيهات الحالية';
  static const platformSecuritySnapshot = 'لقطة التنبيهات';
  static const platformSecurityNoAlertsTitle = 'لا توجد تنبيهات أمنية حالية';
  static const platformSecurityNoAlertsBody =
      'لا تحتوي اللقطة المحمّلة على تنبيهات حالية. لا يعني ذلك ضمان الأمان الكامل.';
  static const platformSecurityOfflineCached =
      'لا يوجد اتصال — تُعرض آخر لقطة تنبيهات متاحة في هذه الجلسة.';
  static const platformSecurityOfflineTitle =
      'لا يمكن جلب تنبيهات المنصة دون اتصال';
  static const platformSecurityOfflineBody =
      'لا توجد لقطة محفوظة يمكن عرضها الآن. أعد المحاولة بعد عودة الاتصال.';
  static const platformSecurityFailureTitle = 'تعذّر تحميل تنبيهات المنصة';
  static const platformSecurityFailureBody =
      'لم تُحمّل لقطة التنبيهات. حاول مرة أخرى من دون كشف تفاصيل تقنية.';
  static const platformSecuritySeverityInfo = 'معلومة';
  static const platformSecuritySeverityWarning = 'تحذير';
  static const platformSecuritySeverityCritical = 'حرج';
  static const platformSecuritySeverityUnknown = 'خطورة غير معروفة';
  static const platformSecurityCategoryAuthentication = 'المصادقة والدخول';
  static const platformSecurityCategoryUnknown = 'فئة غير معروفة';
  static const platformSecuritySummaryInfo = 'تنبيهات معلوماتية';
  static const platformSecuritySummaryWarning = 'تنبيهات تحتاج مراجعة';
  static const platformSecuritySummaryCritical = 'تنبيه حرج يحتاج انتباها';
  static const platformSecuritySummaryUnknown =
      'توجد حالة تنبيه لم يتمكن هذا الإصدار من تفسيرها';
  static const platformSecurityDetected = 'وقت الرصد';
  static const platformSecurityAffectedTenant = 'الفريق المتأثر';

  /// The identifier under an affected team on Platform Security. Kept,
  /// because routing to a tenant by id is real operational work — but
  /// labelled, so it reads as a field rather than as something that leaked.
  static const platformSecurityTenantId = 'المعرّف';
  static const platformSecuritySeverityLabel = 'الخطورة';
  static const platformAuditPlatformScope = 'على مستوى المنصة';
  static const platformAuditDeletedTenant = 'فريق محذوف';
  static const platformAuditOpenEvent = 'فتح تفاصيل الحدث';
  static const platformAuditChangeFromTo = 'من %before% إلى %after%';
  static const platformAuditFilters = 'تصفية';
  static const platformAuditToday = 'اليوم';
  static const platformAuditYesterday = 'أمس';
  static const platformSecurityDeletedTenant = 'فريق محذوف';
  static const platformSecurityOpenTenant = 'فتح مورد الفريق في المنصة';
  static const platformSecurityRefresh = 'تحديث تنبيهات المنصة';

  static const platformTenantsList = 'قائمة الفرق وتفاصيل كل فريق';
  static const platformTenantsCreate = 'إنشاء فريق وتعيين مديره الأول';
  static const platformTenantsSubscription = 'الاشتراك والخطة والحدود';
  static const platformTenantsLifecycle = 'إيقاف الفريق أو إنهاؤه';

  // ---------- Point 6 — SaaS tenant / subscriber management ----------
  // «فريق» is MTM's own word for a customer, matching the platform navigation
  // label. A Super Admin never sees the tenant application, so there is no
  // collision with the tenant app's own «الفريق».

  static const platformTenantsHeading = 'الفرق المشتركة';
  static const platformTenantsSubtitle =
      'كل فريق هنا مشترك مستقل: اشتراكه وبياناته وحدوده منفصلة عن غيره.';
  static const platformTenantsSearchHint =
      'ابحث باسم الفريق أو المدير أو الرمز';
  static const platformTenantsSearchLabel = 'البحث في الفرق المشتركة';
  static const platformTenantsClearSearch = 'مسح البحث';
  static const platformTenantsFilterAll = 'الكل';
  static const platformTenantsFilterTrial = 'تجريبي';
  static const platformTenantsFilterActive = 'نشط';
  static const platformTenantsFilterGrace = 'سماح';
  static const platformTenantsFilterSuspended = 'موقوف';
  static const platformTenantsFilterLabel = 'تصفية حسب الحالة';

  /// **Superseded by `tenantResultCount`,** which handles the Arabic plural
  /// («٨ فرق», not «٨ فريق»). Kept for the singular case it is still correct
  /// for.
  static const platformTenantsResultCount = ' فريق';
  static const platformTenantsClearFilters = 'إزالة التصفية';
  static const platformTenantsCreateAction = 'فريق جديد';
  static const platformTenantsEmptyTitle = 'لا توجد فرق مشتركة بعد';
  static const platformTenantsEmptyBody =
      'أول فريق مشترك يظهر هنا فور إنشائه من هذه الشاشة.';
  static const platformTenantsNoResultsTitle = 'لا نتائج مطابقة';
  static const platformTenantsNoResultsBody =
      'جرّب اسما آخر أو أزل تصفية الحالة.';
  static const platformTenantsNoResultsAction = 'إظهار كل الفرق';
  static const platformTenantsLoadFailed = 'تعذّر تحميل قائمة الفرق.';
  static const platformTenantsOpen = 'فتح تفاصيل الفريق';
  static const platformTenantsMoreNote =
      'النتائج أكثر مما تعرضه هذه الصفحة. ضيّق البحث أو التصفية للوصول إلى '
      'الفريق المطلوب.';

  static const platformTenantStatusTrial = 'فترة تجريبية';
  static const platformTenantStatusActive = 'اشتراك نشط';
  static const platformTenantStatusGrace = 'فترة سماح';
  static const platformTenantStatusSuspended = 'موقوف';

  static const platformTenantTrialEnds = 'تنتهي التجربة ';
  static const platformTenantRenews = 'يتجدد ';
  static const platformTenantGraceEnds = 'ينتهي السماح ';
  static const platformTenantNoSubscriptionDate = 'لا يوجد تاريخ فعّال';

  // Detail
  static const platformTenantDetailTitle = 'تفاصيل الفريق';
  static const platformTenantIdentity = 'الفريق';
  static const platformTenantTeamCode = 'رمز الفريق';
  static const platformTenantTeamCodeNote =
      'رمز ربط تصدره المنصة عند الإنشاء ولا يمكن تعديله من داخل الفريق. ليس '
      'كلمة مرور، ولا يكفي وحده لتسجيل الدخول.';
  static const platformTenantCopyCode = 'نسخ رمز الفريق';
  static const platformTenantCopiedCode = 'نُسخ رمز الفريق';
  static const platformTenantCreatedAt = 'تاريخ الإنشاء';
  static const platformTenantUpdatedAt = 'آخر تغيّر في الحالة';

  static const platformTenantMainAdmin = 'المدير الأول';
  static const platformTenantAdminPending = 'لم يُكمل الإعداد الأول';
  static const platformTenantAdminActive = 'حساب مفعّل';
  static const platformTenantAdminPendingNote =
      'دعوة الإعداد الأول لم تُستكمل بعد. يتم التحقق من ملكية البريد ورمز '
      'الفريق وتغيير كلمة المرور عند أول دخول، خارج هذه الشاشة.';

  // Point 14B — Main Admin seat management (Platform only).
  static const mainAdminSummaryTitle = 'المدير الرئيسي';
  static const mainAdminSummaryOpen = 'إدارة حساب المدير الرئيسي';
  static const mainAdminSummaryLoading = 'جارٍ التحقق من حالة الحساب';
  static const mainAdminSummaryUnavailable = 'حالة الحساب غير متاحة';
  static const mainAdminSummaryPending = 'دعوة الإعداد لم تُستكمل بعد.';
  static const mainAdminSummaryActive = 'الحساب نشط ومهيأ للدخول.';
  static const mainAdminSummarySuspended =
      'حساب المدير الرئيسي موقوف؛ حالة الفريق مستقلة.';
  static const mainAdminSummaryReplacement =
      'هناك بديل ينتظر إكمال الإعداد؛ المدير الحالي ما زال يملك المقعد.';

  static const mainAdminTitle = 'حساب المدير الرئيسي';
  static const mainAdminSeatTitle = 'صاحب المقعد الحالي';
  static const mainAdminLoginEmail = 'بريد تسجيل الدخول';
  // Tenant access, labelled as the *team's* state so it can never be read as
  // the account's own status.
  static const mainAdminTenantAccessActive = 'وصول الفريق نشط';
  static const mainAdminTenantAccessSuspended = 'وصول الفريق موقوف';
  static const mainAdminTenantAccessDeletion = 'الفريق بانتظار الحذف';
  static const mainAdminAccountStatus = 'حالة حساب المدير الرئيسي';
  static const mainAdminStatusActive = 'حساب نشط';
  static const mainAdminStatusPending = 'بانتظار الإعداد';
  static const mainAdminStatusSuspended = 'حساب موقوف';
  static const mainAdminStatusUnsupported = 'حالة غير مدعومة';
  static const mainAdminReplacementPending = 'استبدال قيد الانتظار';
  static const mainAdminInvitationSent = 'أُرسلت الدعوة';
  static const mainAdminInvitationExpires = 'تنتهي الدعوة';
  static const mainAdminInvitationExpired = 'انتهت صلاحية الدعوة';
  static const mainAdminActivatedAt = 'فُعّل الحساب';
  static const mainAdminSuspendedAt = 'أُوقف الحساب';
  static const mainAdminPlatformReason = 'السبب (للمنصة فقط)';
  static const mainAdminDesignateTitle = 'المرشح لاستلام المقعد';
  static const mainAdminDesignateNotAuthorized =
      'هذا المرشح ليس مديراً رئيسياً بعد.';
  static const mainAdminReplacementRequested = 'طُلب الاستبدال';
  static const mainAdminReplacementKeepsCurrent =
      'يبقى %current% المدير الرئيسي حتى يكتمل إعداد حساب %designate%.';
  static const mainAdminTenantBlockedSuspended =
      'لأن وصول الفريق موقوف، لا تتاح إعادة تفعيل الحساب أو الاستبدال أو إعادة إرسال الدعوة حتى يعود الفريق نشطاً. إجراءات هذا الحساب لا تغيّر حالة الفريق.';
  static const mainAdminTenantBlockedDeletion =
      'لأن الفريق بانتظار الحذف، لا يمكن بدء وصول أو استعادته من هذه الصفحة.';
  static const mainAdminActionsTitle = 'الإجراءات المتاحة';
  static const mainAdminNoActions = 'لا توجد إجراءات متاحة لهذه الحالة.';
  static const mainAdminReadOnlyOffline =
      'تعرض هذه الصفحة آخر نسخة محفوظة دون اتصال. الإجراءات متاحة فقط بعد استعادة الاتصال وتحديث الحالة.';
  static const mainAdminReadOnlyStale =
      'هذه نسخة محفوظة لم تُحدَّث. حدّث الحالة لعرض الإجراءات المتاحة.';
  static const mainAdminLastRead = 'آخر تحديث';
  static const mainAdminRefresh = 'تحديث الحالة';
  static const mainAdminDismiss = 'تراجع';
  static const mainAdminResend = 'إعادة إرسال دعوة الإعداد';
  static const mainAdminResendDesignate = 'إعادة إرسال دعوة المرشح';
  static const mainAdminSuspend = 'إيقاف الحساب';
  static const mainAdminReactivate = 'إعادة تفعيل الحساب';
  static const mainAdminReplace = 'استبدال المدير الرئيسي';
  static const mainAdminChangeInvitee = 'تغيير المدعو';
  static const mainAdminCancelReplacement = 'إلغاء الاستبدال';
  static const mainAdminLimitationsTitle = 'ما لا تفعله هذه الصفحة';
  static const mainAdminLimitationsBody =
      'لا تعرض أو تغيّر كلمات المرور، أو المصادقة المتعددة، أو الجلسات، ولا تسجل الدخول بصفة المدير. يستعيد المدير كلمة مروره من شاشة تسجيل الدخول.';

  static const mainAdminResendConfirmTitle = 'إعادة إرسال الدعوة؟';
  static const mainAdminResendConfirmChange =
      'يرسل الخادم دعوة إعداد جديدة إلى هذا البريد، ويتوقف رابط الدعوة السابق عن العمل.';
  static const mainAdminResendConfirmUnchanged =
      'يبقى صاحب المقعد الحالي دون تغيير.';
  static const mainAdminSuspendConfirmTitle = 'إيقاف حساب المدير الرئيسي؟';
  static const mainAdminSuspendConsequences =
      'تنتهي جميع جلسات هذا الحساب فوراً، ويتعذر الدخول به حتى إعادة تفعيله.';
  static const mainAdminSuspendUnchanged =
      'يواصل المديرون الآخرون والفريق العمل، ولا تتغير حالة الفريق.';
  static const mainAdminReactivateConfirmTitle = 'إعادة تفعيل الحساب؟';
  static const mainAdminReactivateConfirmChange =
      'يستطيع صاحب الحساب تسجيل الدخول مجدداً.';
  static const mainAdminReactivateConfirmUnchanged =
      'لا تُستعاد الجلسات السابقة، ولا تتغير حالة الفريق.';
  static const mainAdminCancelConfirmTitle = 'إلغاء الاستبدال؟';
  static const mainAdminCancelConfirmChange =
      'ستتوقف دعوة %name% وتنتهي أي جلسة إعداد مرتبطة بها.';
  static const mainAdminCancelConfirmUnchanged =
      'لن يتغيّر المدير الرئيسي الحالي.';
  static const mainAdminReasonLabel = 'السبب الإداري';
  static const mainAdminReasonHint = 'اكتب سبباً موجزاً وواضحاً';
  static const mainAdminReasonHelp =
      'للمنصة فقط؛ لا يظهر هذا السبب لمستخدمي الفريق.';
  static const mainAdminReasonRequired = 'السبب الإداري مطلوب.';

  static const mainAdminReplaceTitle = 'استبدال المدير الرئيسي';
  static const mainAdminReplaceImmediateMode =
      'المدعو الحالي لم يُكمل الإعداد. عند التأكيد تتوقف دعوته فوراً وتصبح الهوية الجديدة هي المدعو الوحيد.';
  static const mainAdminReplacePendingMode =
      'يبقى المدير الحالي صاحب المقعد حتى تكتمل عملية إعداد الهوية الجديدة في الخادم.';
  static const mainAdminNewName = 'اسم المدير الجديد';
  static const mainAdminNewEmail = 'بريد تسجيل الدخول الجديد';
  static const mainAdminEmailImmutableHelp =
      'البريد هو هوية دخول ثابتة؛ تغييره يتم باستبدال الحساب.';
  static const mainAdminReplaceSubmit = 'مراجعة الاستبدال';
  static const mainAdminVerifyEmail = 'تحقّق من البريد';
  static const mainAdminReplaceImmediateChange =
      'ستتوقف دعوة %old% فوراً، ويصبح %new% المدعو الوحيد.';
  static const mainAdminReplacePendingChange =
      'يبقى %old% المدير الرئيسي حتى يكتمل إعداد حساب %new%؛ ثم ينقل الخادم المقعد وينهي جلسات الحساب السابق.';
  static const mainAdminReplaceUnchanged =
      'لا يتغيّر المقعد قبل أن يؤكد الخادم العملية؛ نتيجته هي المرجع.';
  static const mainAdminNameRequired = 'اسم المدير مطلوب.';
  static const mainAdminNameTooLong = 'الاسم أطول من الحد المسموح.';
  static const mainAdminEmailRequired = 'بريد تسجيل الدخول مطلوب.';
  static const mainAdminEmailInvalid = 'اكتب عنوان بريد صحيحاً.';
  static const mainAdminEmailTooLong = 'عنوان البريد أطول من الحد المسموح.';
  static const mainAdminEmailSame =
      'استخدم بريداً مختلفاً عن هوية المدير الحالي.';
  static const mainAdminEmailUnavailable =
      'لا يمكن استخدام هذه الهوية. اختر بريداً آخر.';

  static const mainAdminSuccessResent = 'أُعيد إرسال الدعوة';
  static const mainAdminSuccessSuspended = 'أُوقف الحساب';
  static const mainAdminSuccessReactivated = 'أُعيد تفعيل الحساب';
  static const mainAdminSuccessReplacementStarted = 'بدأ الاستبدال';
  static const mainAdminSuccessReplaced = 'تم تغيير المدعو';
  static const mainAdminSuccessReplacementCancelled = 'أُلغي الاستبدال';
  static const mainAdminOfflineAction = 'لا يمكن تنفيذ هذا الإجراء دون اتصال.';
  static const mainAdminStaleAction =
      'تغيّرت حالة الحساب منذ فتحها — راجعها ثم أعد المحاولة.';
  static const mainAdminIdempotencyConflict =
      'تعذّر التحقق من هذه المحاولة. راجع الحالة قبل محاولة جديدة.';
  static const mainAdminNotPermitted = 'لا يسمح حسابك بإدارة هذا الحساب.';
  static const mainAdminFailure =
      'تعذّر إتمام الإجراء بأمان. حدّث الحالة ثم حاول مجدداً.';
  static const mainAdminInvalidTransition =
      'لم يعد هذا الإجراء متاحاً لحالة الحساب الحالية.';
  static const mainAdminResendThrottled =
      'أُرسلت دعوة مؤخراً. انتظر قبل إعادة المحاولة.';
  static const mainAdminReplacementAlreadyPending =
      'يوجد استبدال قيد الانتظار بالفعل.';
  static const mainAdminTenantUnavailable =
      'لا تسمح حالة الفريق الحالية بهذا الإجراء.';
  static const mainAdminUnsupportedTitle =
      'تعذّر عرض حالة الحساب في هذا الإصدار';
  static const mainAdminUnsupportedBody =
      'حدّث التطبيق قبل إدارة هذا الحساب. لم يُفترض أي إجراء.';
  static const mainAdminOfflineNoData =
      'لا توجد نسخة محفوظة لحساب المدير الرئيسي.';
  static const mainAdminRecentAuthTitle = 'يتطلب هذا الإجراء تسجيل دخول حديثاً';
  static const mainAdminRecentAuthBody =
      'سجّل الخروج ثم الدخول مجدداً، ثم أعد الإجراء. ستفقد أي بيانات غير محفوظة.';

  static const platformTenantSubscription = 'الاشتراك';
  static const platformTenantSubscriptionReadOnly =
      'عرض فقط في هذه المرحلة. تعديل الاشتراك والخطة والحدود يأتي لاحقا.';

  static const platformTenantUsage = 'الاستخدام';
  static const platformTenantStorage = 'التخزين';
  static const platformTenantLastActivity = 'آخر نشاط';
  static const platformTenantMegabyte = ' م.ب';
  static const platformTenantNoAllowance = 'لا سعة محدّدة';
  static const platformTenantNoActivity = 'لا نشاط مسجّل';

  static const platformTenantOrganisation = 'حجم المؤسسة';
  static const platformTenantGroups = 'مجموعات المفارز';
  static const platformTenantDetachments = 'المفارز';
  static const platformTenantMembers = 'الأعضاء';
  static const platformTenantWorkshops = 'الورش';
  static const platformTenantCountsNote =
      'أرقام مجمّعة تصل مع سجل الفريق. لا تُقرأ من بيانات الفريق التشغيلية.';

  static const platformTenantHistory = 'سجل الحالة';
  static const platformTenantHistoryNote =
      'تسلسل حالة الاشتراك. ليس سجل تدقيق المنصة.';
  static const platformTenantHistoryEmpty = 'لا توجد أحداث مسجّلة.';
  static const platformTenantHistoryFailed = 'تعذّر تحميل سجل الحالة.';
  static const platformTenantEventCreated = 'أُنشئ الفريق';
  static const platformTenantEventTrialStarted = 'بدأت الفترة التجريبية';
  static const platformTenantEventTrialEnded = 'انتهت الفترة التجريبية';
  static const platformTenantEventActivated = 'فُعّل الاشتراك';
  static const platformTenantEventGrace = 'انتقل إلى فترة السماح';
  static const platformTenantEventSuspended = 'أُوقف الفريق';

  static const platformTenantNotFoundTitle = 'هذا الفريق غير موجود';
  static const platformTenantNotFoundBody =
      'قد يكون الرابط قديما أو الرقم غير صحيح.';
  static const platformTenantBackToList = 'العودة إلى قائمة الفرق';

  // Create
  static const platformTenantCreateTitle = 'فريق مشترك جديد';
  static const platformTenantCreateLead =
      'يسجّل هذا النموذج مشتركا جديدا ويحدّد مديره الأول. يبدأ الفريق بفترة '
      'تجريبية، ولا تُنشأ هنا أي كلمة مرور.';
  static const platformTenantNameLabel = 'اسم الفريق';
  static const platformTenantNameHint = 'الاسم كما يعرفه الفريق نفسه';
  static const platformTenantAdminNameLabel = 'اسم المدير الأول';
  static const platformTenantAdminEmailLabel = 'بريد المدير الأول';
  static const platformTenantAdminEmailHelp =
      'إليه تُرسل دعوة الإعداد الأول، وبه يُتحقق من ملكية الحساب لاحقا.';
  static const platformTenantCodeLabel = 'رمز الفريق';

  /// The Latin example is wrapped in an LTR isolate (U+2066 … U+2069) and
  /// written with non-breaking hyphens, so an RTL paragraph cannot reorder its
  /// pieces or split it across a line — the exact defect a bidirectional
  /// layout produces with a hyphenated Latin token inside Arabic text.
  static const platformTenantCodeHelp =
      'ثابت بعد الإنشاء. اقبل الرمز المقترح أو اكتب رمزا بالصيغة '
      '\u2066MTM\u2011XXXX\u2011XXXX\u2069.';
  static const platformTenantCodeSuggest = 'اقترح رمزا آخر';
  static const platformTenantTrialNote = 'يبدأ الفريق بفترة تجريبية مدتها ';
  static const platformTenantTrialDays = ' يوما.';
  static const platformTenantProvisioningNote =
      'يُنشأ المدير الأول بحالة «لم يُكمل الإعداد». لا تُولّد المنصة كلمة مرور '
      'مؤقتة ولا تعرضها: يُثبت المستخدم ملكية بريده ويضع كلمة مروره بنفسه عند '
      'أول دخول.';
  static const platformTenantCreateSubmit = 'إنشاء الفريق';
  static const platformTenantCreateSubmitting = 'جارٍ الإنشاء…';
  static const platformTenantCreateDone = 'أُنشئ الفريق';
  static const platformTenantCreateOpen = 'فتح الفريق';
  static const platformTenantCreateInvalid = 'راجع الحقول المميّزة.';
  static const platformTenantCreateFailed = 'تعذّر إنشاء الفريق.';
  static const platformTenantCreateOffline =
      'لا يمكن إنشاء فريق بدون اتصال. لم يُرسل شيء ولم يُحفظ شيء.';
  static const platformTenantCodeTaken = 'هذا الرمز مستخدم لفريق آخر.';

  static const platformTenantFieldRequired = 'هذا الحقل مطلوب.';
  static const platformTenantFieldTooLong = 'النص أطول من المسموح.';
  static const platformTenantFieldEmail = 'اكتب بريدا إلكترونيا صحيحا.';
  static const platformTenantFieldCode =
      'الصيغة المطلوبة \u2066MTM\u2011XXXX\u2011XXXX\u2069.';

  static const platformMoreTitle = 'المزيد';
  static const platformMoreScopeNote =
      'إعدادات هذا الحساب والتطبيق فقط. إعدادات الفرق ومنظماتها تُدار داخل كل '
      'فريق، لا من هنا.';

  /// Shown instead of the tenant capability rows on the Super Admin's own
  /// account screen. Truthful: this account holds none of the tenant keys, and
  /// platform authority is not expressed in that model at all.
  static const platformProfileAccessNote =
      'يدير هذا الحساب منصة $productNameAr. صلاحيات المنصة تُدار خارج نموذج صلاحيات الفرق، '
      'فلا تظهر هنا صلاحيات فريق ولا مؤسسة.';

  // ---------- Unsupported access state (Point 3 follow-up) ----------
  static const accessUnsupportedTitle = 'هذا الإصدار لا يعرف حالة هذا الحساب';
  static const accessUnsupportedBody =
      'أرسل الخادم حالة وصول لا يفهمها هذا الإصدار من التطبيق. لم يُفتح أي قسم، '
      'لأن تخمين معنى هذه الحالة قد يفتح ما يجب أن يبقى مغلقا.';
  static const accessUnsupportedDetail =
      'حدّث التطبيق إلى أحدث إصدار ثم سجّل الدخول من جديد. إن بقيت الرسالة، '
      'تواصل مع الدعم.';
  static const devStatesUnknownAccount = 'حالة حساب غير معروفة';
  static const devStatesUnknownTenant = 'حالة فريق غير معروفة';
  static const devStatesUnknownDemo = 'وضع تجربة غير معروف';
  static const mfaSetupTitle = 'تفعيل التحقق بخطوتين';
  static const mfaSetupSub =
      'امسح رمز QR باستخدام تطبيق مصادقة، أو أدخل السرّ يدويا.';
  static const mfaManualSecret = 'السرّ اليدوي';
  static const mfaBackupCodesTitle = 'رموز الاستعادة';
  static const mfaBackupCodesSub =
      'احفظ هذه الرموز في مكان آمن — كل رمز يُستخدم مرة واحدة فقط.';
  static const mfaChallengeTitle = 'أدخل رمز التحقق';
  static const mfaCodeRejected = 'الرمز غير صحيح. حاول مرة أخرى.';
  static const mfaChallengeSub =
      'أدخل الرمز المكوّن من ٦ أرقام من تطبيق المصادقة.';
  static const forgotTitle = 'إعادة تعيين كلمة المرور';
  static const forgotSub = 'أدخل بريدك، وسنرسل لك رمز تحقق مكوّنا من ٦ أرقام.';
  static const otpTitle = 'رمز التحقق';
  static const otpSub = 'أدخل الرمز الذي أرسلناه إلى بريدك.';
  static const newPasswordTitle = 'كلمة مرور جديدة';
  static const newPasswordSub = '٨ أحرف على الأقل، تتضمن حرفا كبيرا ورقما.';
  static const sessionExpiredTitle = 'انتهت الجلسة';
  static const sessionExpiredSub = 'لأمانك، طُلب منك تسجيل الدخول مرة أخرى.';
  static const newDeviceTitle = 'جهاز جديد';
  static const newDeviceSub =
      'رصدنا محاولة دخول من جهاز لا نعرفه. أكّد أنه أنت.';
  static const yesItsMe = 'نعم، هذا أنا';
  static const notMe = 'ليس أنا';

  // ---------- Home ----------
  static const homeGreeting = 'أهلا';
  static const activeShift = 'شفتك الآن';
  static const noActiveShift = 'لا يوجد شفت نشط الآن';
  static const timeRemaining = 'الوقت المتبقي';
  static const attendanceProgress = 'الحضور';
  static const primaryAction = 'تسجيل حضور';
  static const needsYourDecision = 'يحتاج قرارك';
  static const secondaryStats = 'لمحة عامة';
  static const unfilledShifts = 'شفتات غير مكتملة';
  static const expiringStock = 'مخزون قارب على الانتهاء';
  static const pendingJoinRequests = 'طلبات انضمام معلّقة';
  static const workshopsThisWeek = 'ورش هذا الأسبوع';
  static const attendanceRate = 'نسبة الحضور';
  static const stockLow = 'أدوية منخفضة';

  // ---------- Detachment ----------
  static const detachments = 'المفرزات';
  static const detachmentListTitle = 'المفرزات';
  static const filterActive = 'نشطة';
  static const filterArchived = 'الأرشيف';
  static const filterAll = 'الكل';
  static const searchDetachments = 'ابحث عن مفرزة أو مركز';
  static const createDetachment = 'مفرزة جديدة';
  static const editDetachment = 'تعديل المفرزة';
  static const detachmentName = 'اسم المفرزة';
  static const detachmentRegion = 'المنطقة';
  static const detachmentCenter = 'المركز الرئيسي';
  static const detachmentNotes = 'ملاحظات';
  static const memberCount = 'الأعضاء';
  static const shiftCount = 'الشفتات هذا الأسبوع';
  static const coverage = 'التغطية';
  static const emptyDetachments = 'لا مفرزات بعد.';
  static const emptyDetachmentsSub =
      'أنشئ مفرزتك الأولى لتبدأ بجدولة الشفتات وإدارة الفريق.';

  // ---------- Archive & history ----------
  // An archived detachment is a finished one. The words stay plain on
  // purpose: the person reading them is an administrator, not a database.
  static const archiveHint = 'مفرزات انتهى عملها. يمكنك مراجعتها وتصديرها فقط.';
  static const emptyArchive = 'لا مفرزات منتهية.';
  static const emptyArchiveSub =
      'المفرزات التي تُؤرشف بعد انتهاء عملها تظهر هنا.';
  static const noMatchingDetachments = 'لا نتائج مطابقة.';
  static const noMatchingDetachmentsSub =
      'جرّب اسما آخر، أو امسح البحث لعرض كل المفرزات.';
  static const clearDetachmentSearch = 'مسح البحث';
  static const historicalDetachment = 'مفرزة منتهية';
  static const historicalReadOnly = 'للاطّلاع فقط';
  static const historicalDetachmentFormNote =
      'انتهى عمل هذه المفرزة. بياناتها للاطّلاع فقط، ويمكن إعادة تنشيطها من '
      'حالة المفرزة أدناه.';
  // `detachment.archive` without `detachment.edit`: status yes, details no.
  static const detachmentStatusOnlyNote =
      'يمكنك تغيير حالة هذه المفرزة فقط. تعديل اسمها وبياناتها يحتاج صلاحية '
      'غير ممنوحة لحسابك.';
  static const historicalRosterNote =
      'الأعضاء المسجّلون في هذه المفرزة كما هم الآن؛ لا يحفظ النظام نسخة '
      'منفصلة لفريقها وقت انتهائها.';
  static const historicalNoShiftsInWeek = 'لا شفتات في هذا الأسبوع.';
  static const historicalNoShiftsInWeekSub =
      'استخدم أسهم الأسبوع للتنقّل في أيام عمل المفرزة.';
  static const historicalEmptyTeam = 'لا أعضاء مسجّلين في هذه المفرزة.';
  static const historicalEmptyTeamSub =
      'انتهى عمل هذه المفرزة ولم يبق على قائمتها أحد.';
  static const historicalEmptyInventory = 'لا مواد مسجّلة في مخزن هذه المفرزة.';
  static const historicalEmptyInventorySub =
      'انتهى عمل هذه المفرزة ولم يبق في سجلّ مخزنها أصناف.';

  // ---------- Team ----------
  static const teamListTitle = 'أعضاء الفريق';
  static const roleShiftSupervisor = 'مشرف الشفت';
  static const roleAdministrator = 'إداري';
  static const roleFollowUp = 'متابعة';
  static const roleMember = 'عضو';
  static const changeRole = 'تغيير الدور';
  static const assignRole = 'تعيين دور';
  static const emptyTeam = 'لا أعضاء في هذه المفرزة بعد.';
  static const emptyTeamSub = 'أضف أول عضو لتبدأ بتوزيع الأدوار والشفتات.';
  static const addMember = 'أضف عضوا';

  // ---------- Member form ----------
  static const newMember = 'عضو جديد';
  static const editMember = 'تعديل بيانات العضو';
  static const memberName = 'الاسم';
  static const memberNamePlaceholder = 'مثال: أحمد كنعان';
  static const memberDepartment = 'القسم';
  static const memberDepartmentPlaceholder = 'مثال: الإسعاف';
  static const memberNumber = 'الرقم الشخصي';
  static const memberNumberPlaceholder = 'مثال: ١٠٧';
  static const memberNumberHelp = 'رقم يختاره العضو، لا يتكرر داخل المفرزة.';
  static const memberNumberDigitsOnly = 'أدخل أرقاما فقط.';
  static const memberRole = 'الدور في المفرزة';
  static const deleteMember = 'حذف العضو';
  static const deleteMemberBody =
      'سيُحذف العضو من مفرزته ومن كل شفت لم يبدأ بعد. لا يمكن التراجع.';
  static const deleteMemberUnchanged =
      'يبقى حضوره المسجَّل في الشفتات المنتهية وفي التقارير كما هو.';
  static const memberDeleted = 'تم حذف العضو';

  // ---------- Shifts ----------
  static const shiftsTitle = 'شفتات اليوم';
  static const coverageGap = 'نقص في التغطية';
  static const assignVolunteer = 'إسناد متطوع';
  static const checkIn = 'تسجيل الحضور';
  static const notCheckedIn = 'لم يسجل الدخول';
  static const checkedIn = 'سجّل الدخول';
  static const checkedOut = 'سجّل الخروج';
  static const absent = 'غائب';
  static const emptyShifts = 'لا شفتات اليوم.';
  static const emptyShiftsSub = 'أنشئ شفتا جديدا لبدء تسجيل الحضور.';
  static const newShift = 'شفت جديد';

  // ---------- Inventory ----------
  static const storageTitle = 'المخزن';
  static const stockIn = 'إدخال';
  static const stockOut = 'صرف';
  static const currentStock = 'المخزون الحالي';
  static const expiresOn = 'تنتهي في';
  static const daysToExpiry = 'يوم للانتهاء';
  static const belowMinimum = 'أقل من الحد الأدنى';
  static const movementSheet = 'حركة مخزون';
  static const quantity = 'الكمية';
  static const reason = 'السبب';
  static const emptyInventory = 'المخزن فارغ.';
  static const emptyInventorySub = 'أضف صنفا لتبدأ بتتبع الحركة والصلاحية.';

  // ---------- Workshops ----------
  static const workshopsTitle = 'الورش';
  static const emptyWorkshops = 'لا ورش مجدولة.';
  static const emptyWorkshopsSub = 'أنشئ ورشة جديدة لفتح باب التسجيل.';
  static const createWorkshop = 'ورشة جديدة';
  static const editWorkshop = 'تعديل الورشة';
  static const workshopName = 'اسم الورشة';
  static const workshopDate = 'التاريخ';
  static const workshopCapacity = 'السعة';
  static const workshopLocation = 'المكان';
  static const registeredMembers = 'المسجّلون';
  static const guests = 'الضيوف';
  static const markAttendance = 'وضع الحضور';
  static const capacity = 'السعة';
  static const full = 'مكتملة';

  // ---------- Stats ----------
  static const statsWeekly = 'أسبوعي';
  static const statsMonthly = 'شهري';
  static const consumption = 'الاستهلاك';

  // ---------- Settings (المزيد) ----------
  static const settingsProfile = 'حسابي';
  static const settingsSecurity = 'الأمان';
  static const settingsSessions = 'الجلسات النشطة';
  static const settingsDevices = 'الأجهزة المربوطة';

  /// Ends one *other* session. Deliberately not 'إلغاء' — that is [cancel],
  /// and the revoke confirmation put the two words side by side.
  static const settingsRevoke = 'إنهاء';
  static const settingsNotifications = 'التنبيهات';
  static const settingsOrg = 'المؤسسة';
  static const settingsAppearance = 'المظهر';
  static const settingsMotion = 'جودة الحركة والأداء';
  static const settingsMotionSub =
      'اختر مستوى الحركة المناسب لجهازك. المستويات الأخف تختصر مدة الحركة '
      'وتوقف التأثيرات المكلفة لتبقى الواجهة سريعة الاستجابة.';
  static const settingsMotionPerformance = 'أداء أعلى';
  static const settingsMotionLow = 'خفيف';
  static const settingsMotionBalanced = 'متوازن';
  static const settingsMotionHigh = 'جودة عالية';
  static const settingsMotionMaximum = 'أعلى سلاسة';
  static const settingsMotionPerformanceHint =
      'يوقف الحركات والمؤثرات غير الضرورية، فتظهر الشاشات مباشرة. الأنسب '
      'للأجهزة الضعيفة أو البطيئة.';
  static const settingsMotionLowHint =
      'حركات قصيرة ومؤثرات أقل، مع بقاء الواجهة كاملة.';
  static const settingsMotionBalancedHint = 'الخيار الموصى به لمعظم الأجهزة.';
  static const settingsMotionHighHint =
      'انتقالات أنعم ومؤثرات أوضح، للأجهزة الحديثة.';
  static const settingsMotionMaximumHint =
      'يستخدم مؤثرات وحركات أكثر على الأجهزة القوية.';
  static const settingsMotionOsNotice =
      'نظام الجهاز يطلب إيقاف الحركة، وهذا الطلب مطبَّق حاليا فوق المستوى '
      'المختار.';
  // ---- Themes & Performance (one canonical screen) ----
  static const sectionThemesPerformance = 'السمات والأداء';
  static const settingsThemeSection = 'السمة';
  static const settingsThemeSectionSub = 'اختر سمة التطبيق. تُطبَّق فورا.';
  static const settingsPerformanceSection = 'الأداء';
  // The three product themes.
  static const settingsThemeDarkCyber = 'Dark Cyber';
  static const settingsThemeDarkCyberSub =
      'مظهر داكن بلمسة سماوية. الخيار الافتراضي.';
  static const settingsThemePurpleArena = 'Purple Arena';
  static const settingsThemePurpleArenaSub = 'مظهر داكن بلمسة بنفسجية.';
  static const settingsThemeLight = 'السمة الفاتحة';
  static const settingsThemeLightSub = 'مظهر فاتح وواضح في الإضاءة القوية.';
  static const settingsThemeSelected = 'مختار';

  // ---------- Brand logo (Settings → السمات والأداء) ----------
  //
  // Which of the three approved Leader marks the app draws on its own
  // surfaces. Cosmetic and local: it never reaches auth, roles, the tenant
  // or the backend, and it never changes the launcher icon — that one is
  // fixed to Clean Layer for everyone.
  static const settingsLightMode = 'المظهر';
  static const settingsLightModeSub =
      'اختر المظهر الفاتح أو الداكن، أو اتبع إعداد الجهاز.';
  static const settingsQuality = 'مستوى الأداء';
  static const settingsQualitySub =
      'يحدد مقدار الحركات والمؤثرات في التطبيق. الخيارات الأخف تجعل الجهاز '
      'أسرع استجابة.';
  static const settingsFrameRate = 'معدل الإطارات';
  static const settingsFrameRateSub =
      'المعدل المطلوب من شاشة الجهاز. التطبيق لا يسقط إطارات، بل يطلب من '
      'النظام وضع العرض المناسب.';
  // Shown when the lightest quality level is paired with a high frame rate:
  // a note, not an override — the user's two choices are both respected.
  static const settingsFrameRatePerformanceNote =
      'مع وضع «أداء أعلى» تكون الحركات موقوفة، فالمعدل المرتفع يستهلك '
      'البطارية دون فائدة تُذكر.';
  static const settingsFrameRateAuto = 'تلقائي';
  static const settingsFrameRate30 = '٣٠ إطار/ث';
  static const settingsFrameRate60 = '٦٠ إطار/ث';
  static const settingsFrameRate90 = '٩٠ إطار/ث';
  static const settingsFrameRate120 = '١٢٠ إطار/ث';
  static const settingsFrameRateAutoHint =
      'يترك الاختيار للنظام: يخفض المعدل على الشاشات الساكنة ويرفعه عند '
      'التمرير. الخيار الآمن على كل الأجهزة.';
  static const settingsFrameRateFixedHint =
      'يطلب من النظام تثبيت وضع عرض بهذا المعدل طوال استخدام التطبيق.';
  static const settingsFrameRateUnsupported =
      'هذا الجهاز لا يتيح للتطبيقات اختيار معدل الإطارات، لذا يبقى الوضع '
      'التلقائي هو الخيار الوحيد.';
  static const settingsFrameRateCurrent = 'المعدل الحالي للشاشة';
  static const settingsFrameRateNearest =
      'أقرب معدل تدعمه الشاشة هو المستخدَم فعليا.';
  static const settingsFrameRateHz = 'هرتز';

  // ---- Shifts: day copy, template dates, card summary ----
  static const copyPreviousDay = 'انسخ اليوم السابق';
  static const copyPreviousDayDone = 'تم نسخ شفتات اليوم السابق.';
  static const copyPreviousDayEmpty = 'لا شفتات في اليوم السابق للنسخ.';
  static const shiftManager = 'مسؤول الشفت';
  static const shiftManagerUnset = 'لم يُحدَّد مسؤول للشفت';
  static const templateEditTitle = 'أيام القالب';
  static const templateEditSub =
      'اختر الأيام التي يتكرر فيها هذا الشفت. إضافة يوم تنشئ شفتا عليها، '
      'وإزالة يوم تحذف شفته إن كان فارغا فقط — اليوم الذي عليه أفراد يبقى '
      'كما هو.';
  static const templateEdit = 'تعديل الأيام';
  static const templateSaved = 'تم تحديث أيام القالب.';
  static const templateLockedDay = 'يوم عليه أفراد — لا يمكن إزالته.';
  static const templateNeedsTwoDays =
      'قالب بيوم واحد لم يعد تكرارا، وسيتوقف عند الحفظ.';

  // ---- Workshop statistics (dashboard, detail, export) ----
  static const workshopStatsTitle = 'إحصائيات الورشة';
  static const workshopStatsSubtitle = 'تقرير الأداء والحضور';
  static const statsGroupParticipants = 'طلاب/ضيوف';
  static const statsGroupTeam = 'الفريق';
  static const statsAttendanceSection = 'معدلات الحضور';
  static const statsFinanceSection = 'الملخص المالي';
  static const statsDetailSection = 'التفصيل';
  static const statsPresentAbsent = 'حاضر / غائب';
  static const statsPayers = 'الدافعون';
  static const statsNonPayers = 'غير دافع/غير محدد';
  static const statsTotalCollected = 'الإجمالي';
  static const statsRegistrationFee = 'رسم الاشتراك';
  static const statsFreeWorkshop = 'ورشة مجانية — لا رسم اشتراك';
  static const paymentPaid = 'دافع';
  static const paymentUnpaid = 'غير دافع';
  static const paymentUnspecified = 'غير محدد';
  static const participantGuest = 'ضيف';
  static const participantMember = 'متطوع';
  static const currencyUnit = 'ل.س';
  static const statsColCategory = 'الفئة';
  static const statsColPresent = 'الحاضر';
  static const statsColAbsent = 'الغائب';
  static const statsColName = 'الاسم';
  static const statsColRole = 'الدور';
  static const statsColAttendance = 'الحضور';
  static const statsColPayment = 'الدفع';
  static const statsCopyTitle = 'نسخ الأسماء';
  static const statsCopySub =
      'نسخ سريع لأسماء الدافعين فقط بصيغة "رقم - اسم" للصق المباشر في '
      'المحادثات والقوائم.';
  static const statsCopyParticipants = 'نسخ المشاركين';
  static const statsCopyTeam = 'نسخ الفريق';
  static const statsCopyEmpty = 'لا توجد أسماء في هذه القائمة بعد';
  static const statsCopyNoPayers = 'لا يوجد دافعون في هذه القائمة بعد';
  static const statsCopyDone = 'تم نسخ أسماء الدافعين';
  static const statsExportTitle = 'تصدير التقرير الكامل';
  static const statsExportSub =
      'ملف واحد يشمل ملخص الحضور والدفع مع الإجمالي المالي، وقائمة المشاركين '
      'وقائمة الفريق بالأسماء والأدوار.';
  static const statsExportCustom = 'تصدير مخصص';
  static const statsExportCustomSub =
      'اختر الأقسام التي تريد تضمينها في ملف تقرير الورشة.';
  static const statsSecSummary = 'ملخص الحضور والدفع';
  static const statsSecSummarySub = 'حضور وغياب ودفع كل فئة مع الإجمالي المالي';
  static const statsSecParticipants = 'قائمة المشاركين';
  static const statsSecParticipantsSub = 'الأسماء مرقمة مع الحضور وحالة الدفع';
  static const statsSecTeam = 'قائمة أعضاء الفريق';
  static const statsSecTeamSub = 'الأسماء مرقمة مع الدور والحضور وحالة الدفع';
  static const statsExportEmpty = 'لا توجد بيانات لتصديرها بعد';
  static const statsNoParticipants = 'لا يوجد مشاركون مسجلون بعد.';
  static const statsNoTeam = 'لا يوجد أعضاء فريق مسجلون بعد.';
  static const statsFinancialTotalLine = 'الإجمالي المالي';
  static const statsPayerMultiplier = 'دافع ×';

  static const settingsMotionFull = 'حركة كاملة';
  static const settingsMotionReduced = 'حركة مخففة';
  static const settingsPaletteMedical = 'طبّي';
  static const settingsPaletteSlate = 'Slate';
  static const settingsPaletteCopper = 'Copper';
  static const settingsPaletteClay = 'Clay';
  static const settingsPaletteIndigo = 'Indigo';
  static const settingsPaletteTeal = 'Teal';
  static const settingsPaletteMedicalSub =
      'ألوان سريرية هادئة وواضحة للعمل اليومي.';
  static const settingsPaletteSlateSub = 'رمادي متوازن مع لمسة حمراء دافئة.';
  static const settingsPaletteCopperSub = 'لوحة محايدة بلمسة نحاسية عملية.';
  static const settingsPaletteClaySub = 'درجات ترابية دافئة ومريحة.';
  static const settingsPaletteIndigoSub = 'أزرق نيلي بتركيز بصري واضح.';
  static const settingsPaletteTealSub = 'أخضر مزرق هادئ بوضوح مرتفع.';
  static const settingsModeLight = 'فاتح';
  static const settingsModeDark = 'داكن';
  static const settingsEyeProtect = 'حماية العين';
  static const settingsEyeProtectSub =
      'يخفف سطوع الألوان لراحة أكبر أثناء الاستخدام الطويل.';
  static const settingsEyeProtectOn = 'مفعّلة';
  static const settingsEyeProtectOff = 'متوقفة';
  // The whole point of the screen: it is a comfort filter, not a theme.
  static const settingsEyeProtectIndependent =
      'إعداد مستقل: لا يغيّر السمة المختارة، ولا يبدّل بين الفاتح والداكن. '
      'يمكن تشغيله مع أي سمة.';
  static const settingsEyeProtectPreview = 'معاينة الألوان';
  static const settingsEyeProtectPreviewSub =
      'ألوان التنبيهات تبقى واضحة عند تشغيل حماية العين.';
  static const settingsEyeProtectSampleOk = 'مكتمل';
  static const settingsEyeProtectSampleWarn = 'تحذير';
  static const settingsEyeProtectSampleCrit = 'خطأ';
  static const settingsEyeProtectSampleBody = 'نص عادي كما يظهر داخل التطبيق.';
  static const signOut = 'تسجيل الخروج';
  static const signOutConfirm = 'هل تريد تسجيل الخروج فعلا؟';

  // ---------- States (loading / empty / error / offline) ----------
  static const errTitle = 'تعذّر التحميل';
  static const errGeneric =
      'حدث خطأ أثناء جلب البيانات. تحقق من اتصالك ثم أعد المحاولة.';
  static const offlineTitle = 'بدون اتصال';
  static const offlineSub = 'تعرض بيانات محلية. آخر تحديث ';
  static const staleData = 'بيانات محفوظة — لم يتم التحديث';
  static const partialRefreshFailed = 'تعذّر التحديث في الخلفية';

  // ---------- Forced upgrade (blocking app state) ----------
  static const upgradeTitle = 'التطبيق يحتاج إلى تحديث';
  static const upgradeBody =
      'هذا الإصدار لم يعد مدعوما. يرجى تحديث $productNameAr للاستمرار في استخدام التطبيق.';
  static const upgradeCurrentVersion = 'الإصدار الحالي';
  static const upgradeMinimumVersion = 'الحد الأدنى المدعوم';
  static const upgradeAction = 'تحديث التطبيق';
  static const upgradeChecking = 'جارٍ التحقق من الإصدار';
  static const upgradeCheckFailedTitle = 'تعذّر التحقق من التحديث';
  static const upgradeCheckFailedBody =
      'تعذّر الاتصال للتحقق من التحديث. تحقق من اتصال الإنترنت وحاول مرة أخرى.';
  static const upgradeLinkCopied = 'نُسخ رابط التحديث';
  static const upgradeLinkUnavailable = 'رابط التحديث غير متاح حاليا.';

  // ---------- Problem / error taxonomy ----------
  // Frontend-owned copy for known problem codes. Widgets never show backend
  // `detail` text for these — see FRONTEND-BACKEND-INTEGRATION.md §2.
  static const problemUnexpectedTitle = 'تعذر إكمال العملية';
  static const problemUnexpectedBody = 'حدث خطأ غير متوقع. حاول مرة أخرى.';
  static const errNotFound = 'لم يُعثر على العنصر المطلوب.';
  static const errNotPermittedTitle = 'صلاحية غير متوفرة';
  static const errNotPermitted = 'ليس لديك صلاحية لتنفيذ هذا الإجراء.';
  // `feature_disabled` / `plan_limit_reached`: organisation-wide refusals, not
  // this account's permission — so neither says "صلاحية".
  static const errFeatureDisabledTitle = 'الميزة غير مفعّلة';
  static const errFeatureDisabled =
      'هذه الميزة غير مفعّلة لهذا الفريق حاليًا، ولم تُحذف أي بيانات.';
  static const errPlanLimitTitle = 'بلغ الفريق حد الخطة';
  static const errPlanLimit =
      'لا يمكن إضافة المزيد لأن الفريق بلغ الحد الذي تسمح به خطته. راجع '
      '«الخطة والاشتراك» في الإعدادات أو تواصل مع الدعم.';
  static const errConflictTitle = 'تغيّر هذا العنصر';
  static const errConflict =
      'حدّثه شخص آخر قبلك. أعد التحميل ثم حاول مرة أخرى.';
  // Optimistic-concurrency stale write (`ProblemCode.staleWrite`) — distinct
  // from errConflict above. No blind retry is offered: resubmitting the same
  // write against the same (now-stale) version fails the same way again: see
  // FRONTEND-BACKEND-INTEGRATION.md §4.
  static const errStaleWriteTitle = 'تغيّر هذا العنصر من جهاز آخر';
  static const errStaleWrite =
      'حدَّثه شخص آخر منذ أن بدأت تعديلك. راجع الفروقات ثم اختر النسخة المناسبة.';
  static const errValidation = 'تحقّق من الحقول المميّزة ثم أعد المحاولة.';
  static const errServer =
      'تعذّر إكمال الطلب على الخادم. حاول مرة أخرى بعد قليل.';
  static const errNetwork =
      'تعذّر الوصول إلى الخادم. تحقّق من الاتصال وحاول مجددا.';
  // Label for a safe support reference on a substantial unexpected-error
  // screen. Only shown when the backend actually provides an id.
  static const problemReferenceLabel = 'مرجع الدعم';

  // ---------- Conflict resolution ----------
  // Feature adapters own field labels and formatted values. These strings
  // describe only the shared resolution workflow; no backend message or raw
  // field path is presented by the generic screen.
  static const conflictReviewTitle = 'مراجعة التعارض';
  static const conflictTitle = 'وجد تعارض في التعديلات';
  static const conflictDescription =
      'تم تعديل هذه البيانات من جهاز آخر قبل مزامنة تعديلاتك. راجع النسختين واختر التعديل المناسب.';
  static const conflictLocalVersion = 'نسختك';
  static const conflictLocalVersionSub = 'تعديلاتك غير المزامنة';
  static const conflictCurrentVersion = 'النسخة الحالية';
  static const conflictCurrentVersionSub = 'آخر نسخة تمت مزامنتها مع الفريق';
  static const conflictDifferencesTitle = 'التعديلات المختلفة';
  static const conflictDifferencesBody =
      'تظهر هنا الحقول التي تختلف بين النسختين فقط.';
  static const conflictUseLocal = 'استخدام تعديلي';
  static const conflictUseCurrent = 'استخدام النسخة الحالية';
  static const conflictReviewLater = 'مراجعة لاحقاً';
  static const conflictDecisionFailed =
      'تعذّر حفظ اختيارك. لم يُغلق التعارض، ويمكنك المحاولة مرة أخرى.';
  static const conflictUnavailableTitle = 'التعارض غير متاح الآن';
  static const conflictUnavailableBody =
      'ارجع إلى المزامنة أو قائمة المراجعة وافتح التعارض من هناك.';
  static const conflictShiftRecord = 'الشفت';
  static const conflictShiftDate = 'التاريخ';
  static const conflictShiftTime = 'الوقت';

  // Choosing the shared version throws away an unsynced local edit, so it is
  // the one choice on this screen that asks first (roadmap §17).
  static const conflictUseCurrentConfirmTitle = 'استخدام النسخة الحالية؟';
  static const conflictUseCurrentConfirmBody =
      'سيؤدي هذا إلى تجاهل تعديلك غير المزامن، ولا يمكن التراجع عنه.';

  // Why a resolution could not be applied. Each answers the same three
  // questions: what happened, is my data safe, what can I do now.
  static const conflictAlreadyResolved = 'تم حل هذا التعارض بالفعل.';
  static const conflictRecordChanged =
      'تغيرت هذه البيانات مرة أخرى. افتح التعارض من جديد لمراجعة أحدث نسخة.';
  static const conflictRecordDeleted =
      'تم حذف هذا السجل من جهاز آخر، ولم يعد من الممكن تطبيق تعديلك عليه.';
  static const conflictNotPermitted =
      'لا تملك صلاحية تنفيذ هذا التغيير. تعديلك محفوظ ولم يُفقد.';
  static const conflictOfflineDecision =
      'يحتاج هذا الاختيار اتصالا بالإنترنت. تعديلك محفوظ ولم يُفقد.';

  // ---------- Needs Review inbox ----------
  // The explicit list of changes waiting on a human decision. Plain language
  // only: no operation id, no idempotency key, no wire code, no backend
  // state name (FRONTEND-BACKEND-INTEGRATION.md §3, §10, §16).
  static const needsReviewTitle = 'تغييرات تحتاج مراجعة';
  static const needsReviewIntro =
      'حفظت هذه التغييرات على جهازك، وتغيّرت البيانات نفسها من جهاز آخر قبل مزامنتها. افتح كل تغيير واختر النسخة المناسبة.';
  static const needsReviewOpen = 'مراجعة';
  static const needsReviewEmptyTitle = 'لا توجد تغييرات تحتاج مراجعة';
  static const needsReviewEmptyBody =
      'تُزامَن تغييراتك تلقائيًا. سيظهر هنا أي تغيير يحتاج قرارك.';
  // Listed, but with nothing safe to compare on this device yet. The change
  // itself is still saved and still waiting — never presented as a loss.
  static const needsReviewUnavailable =
      'تفاصيل هذا التغيير غير متاحة على هذا الجهاز';
  static const needsReviewUnavailableBody =
      'تغييرك محفوظ ولم يُفقد. أعد المزامنة عند توفر الاتصال لعرض الفروقات.';
  static const needsReviewDetectedPrefix = 'ظهر ';
  // Fallback names for the kind of record involved, so an internal grouping
  // tag never reaches the screen. See `needsReviewRecordLabel`.
  static const needsReviewRecordShift = 'تغيير على شفت';
  static const needsReviewRecordInventory = 'تغيير على المخزون';
  static const needsReviewRecordMember = 'تغيير على عضو فريق';
  static const needsReviewRecordGeneric = 'تغيير غير مزامن';

  // ---------- Time labels ----------
  static const secondsAgo = 'قبل ثوانٍ';
  static const minAgo = 'قبل دقيقة';
  static const minsAgo = 'قبل %d دقيقة';
  static const hourAgo = 'قبل ساعة';
  static const hoursAgo = 'قبل %d ساعات';
  static const today = 'اليوم';
  static const tomorrow = 'غدا';
  static const yesterday = 'أمس';

  // ---------- Batch 0 · item D screens ----------

  // Shared form / action labels
  static const required = 'هذا الحقل مطلوب';
  static const saveChanges = 'حفظ التعديلات';
  static const savedOk = 'تم الحفظ';
  static const noCachedCopy = 'لا نسخة محفوظة.';
  static const optional = 'اختياري';
  static const status = 'الحالة';
  static const percentSign = '٪';

  // Detachment create / edit
  static const newDetachment = 'مفرزة جديدة';
  static const detachmentNamePlaceholder = 'مثال: مفرزة دمشق المركزية';
  static const detachmentRegionPlaceholder = 'مثال: ريف دمشق';
  static const detachmentCenterPlaceholder = 'مثال: مركز داريا';
  static const detachmentNotesPlaceholder = 'ملاحظات داخلية عن المفرزة';
  static const statusActive = 'نشطة';
  static const statusArchived = 'مؤرشفة';
  static const archiveDetachment = 'أرشفة المفرزة';
  static const restoreDetachment = 'إعادة تنشيط المفرزة';

  // Shifts tab
  static const shiftAssignedOfNeeded = 'المسندون';
  static const shiftAttendees = 'المسجّلون';
  static const shiftNoAttendees = 'لا أحد مسند لهذا الشفت بعد.';
  static const shiftCoverageOk = 'التغطية مكتملة';
  static const assignSheetTitle = 'إسناد متطوع';
  static const attendanceSheetTitle = 'تسجيل الحضور';
  static const allMembersAssigned = 'كل أعضاء المفرزة مسندون لهذا الشفت.';
  static const shiftNeeded = 'المطلوب';

  // Storage tab
  static const minimumLevel = 'الحد الأدنى';
  static const noExpiry = 'بلا تاريخ انتهاء';
  static const expired = 'منتهية';
  static const stockOk = 'متوفّر';
  static const stockLowLabel = 'منخفض';
  static const stockEmpty = 'نفد';
  static const itemMovements = 'آخر الحركات';
  static const noMovements = 'لا حركات مسجّلة على هذا الصنف.';
  static const movementIn = 'إدخال';
  static const movementOut = 'صرف';
  static const quantityPlaceholder = 'مثال: ٦';
  static const reasonPlaceholder = 'مثال: صرف لشفت المساء';
  static const record = 'تسجيل';

  // Stats tabs
  static const statsAttendance = 'نسبة الحضور';
  static const statsCoverage = 'نسبة التغطية';
  static const statsStock = 'الاستهلاك اليومي';
  static const noStats = 'لا إحصائيات بعد.';
  static const noStatsSub = 'ستظهر الأرقام بعد أول أسبوع من التشغيل.';
  // A permission, not missing data: the session lacks `stats.view` here.
  static const statsNotPermittedTitle = 'إحصائيات هذه المفرزة غير متاحة لحسابك';
  static const statsNotPermittedBody =
      'عرضها يحتاج صلاحية الإحصائيات في هذه المفرزة، وهي غير ممنوحة لحسابك. '
      'يمكن لمن يدير حسابات المشرفين في مؤسستك منحك إياها.';
  static const highest = 'الأعلى';
  static const average = 'المتوسط';

  // Workshop list / edit
  static const searchWorkshops = 'ابحث عن ورشة أو مكان';
  static const filterUpcoming = 'قادمة';
  static const filterPast = 'منتهية';
  static const workshopScheduled = 'مجدولة';
  static const workshopOngoing = 'جارية';
  static const workshopDone = 'منتهية';
  static const newWorkshop = 'ورشة جديدة';
  static const workshopNamePlaceholder = 'مثال: الإسعاف الأولي المتقدم';
  static const workshopLocationPlaceholder = 'مثال: قاعة الشعلان الكبرى';
  static const workshopCapacityPlaceholder = 'مثال: ٢٠';
  static const workshopSeatsLeft = 'مقاعد متبقية';
  static const workshopInvalidCapacity = 'السعة يجب أن تكون رقما أكبر من صفر.';
  static const workshopInvalidDate = 'اختر تاريخا ووقتا للورشة.';
  static const pickDate = 'اختيار التاريخ';
  static const pickTime = 'اختيار الوقت';

  // Workshop tabs
  static const emptyWorkshopTeam = 'لا فريق منظِّم لهذه الورشة.';
  static const emptyWorkshopTeamSub = 'أضف منظِّما ليظهر هنا.';
  static const emptyParticipants = 'لا مشاركين مسجّلين.';
  static const emptyParticipantsSub = 'أضف عضوا أو ضيفا لتبدأ تسجيل الحضور.';
  static const searchWorkshopParticipants = 'ابحث عن مشارك';
  static const noMatchingWorkshopParticipants = 'لا مشاركين يطابقون البحث.';
  static const noMatchingWorkshopParticipantsSub =
      'جرّب اسما آخر، أو اعرض كل الأعضاء والضيوف.';
  static const clearWorkshopParticipantFilters = 'مسح البحث والتصفية';
  static const addParticipant = 'أضف مشاركا';
  static const kindMember = 'عضو';
  static const kindGuest = 'ضيف';
  static const totalParticipants = 'إجمالي المشاركين';
  static const workshopAddMember = 'إضافة عضو';
  static const workshopAddGuest = 'إضافة ضيف';
  static const workshopAddOrganizer = 'إضافة منظِّم';
  static const workshopPickMembersTitle = 'إضافة أعضاء إلى الورشة';
  static const workshopPickOrganizersTitle = 'إضافة إلى الفريق المنظِّم';
  static const workshopPickSearch = 'ابحث بالاسم أو القسم أو المفرزة';
  static const workshopPickNone = 'لا أعضاء في الفريق بعد.';
  static const workshopPickNoneSub =
      'أضف أعضاء إلى إحدى المفارز أولا، ثم عد لتسجيلهم في الورشة.';
  static const workshopPickNoMatch = 'لا أحد يطابق البحث.';
  static const workshopPickAlreadyParticipant = 'مسجّل';
  static const workshopPickAlreadyOrganizer = 'منظِّم';
  static const workshopPickNoSeats = 'لا مقاعد متبقية في الورشة.';
  static const workshopPickConfirm = 'إضافة';
  static const workshopPickEmptySelection = 'اختر عضوا واحدا على الأقل';
  static const workshopSeatsTaken = 'مقعدا مشغولا من';
  static const workshopGuestName = 'اسم الضيف';
  static const workshopGuestNameHint = 'الاسم الكامل كما يُكتب في الشهادة';
  static const workshopPersonActions = 'الحضور والدفع';
  static const workshopPaymentSection = 'الدفع';
  static const workshopAttendanceSection = 'الحضور';
  static const workshopRemoveParticipant = 'إزالة من الورشة';
  static const workshopRemoveOrganizer = 'إزالة من الفريق المنظِّم';
  static const workshopRemoveConfirmTitle = 'إزالة من الورشة؟';
  static const workshopRemoveOrganizerTitle = 'إزالة من الفريق المنظِّم؟';
  static const workshopRemoveOrganizerBody =
      'يُحذف من الفريق المنظِّم لهذه الورشة فقط، ويبقى عضوا في الفريق.';
  static const workshopRemoveMemberBody =
      'يُحذف من سجل هذه الورشة فقط، ويبقى عضوا في الفريق.';
  static const workshopRemoveGuestBody =
      'يُحذف الضيف وحضوره ودفعه من سجل هذه الورشة.';
  static const workshopRemove = 'إزالة';
  static const workshopRemoved = 'أُزيل من الورشة.';
  static const workshopAdded = 'تمت الإضافة إلى الورشة.';
  static const workshopArchivedBanner =
      'ورشة مؤرشفة — للقراءة والتصدير فقط. استعدها لتعديلها.';
  static const workshopArchive = 'أرشفة الورشة';
  static const workshopRestore = 'استعادة الورشة';
  static const workshopArchiveConfirmBody =
      'تبقى الورشة وسجلها وإحصائياتها متاحة للقراءة، ولا يمكن تعديلها حتى تُستعاد.';

  /// The same fact as [workshopArchiveConfirmBody], split into the two halves
  /// a confirmation states separately: what the operation changes, and what
  /// it leaves alone.
  static const workshopArchiveChange =
      'تُغلق الورشة أمام أي تعديل حتى تُستعاد.';
  static const workshopArchiveUnchanged =
      'يبقى سجلها وأعضاؤها وإحصائياتها متاحة للقراءة والتصدير.';
  static const workshopArchivedOk = 'أُرشفت الورشة.';
  static const workshopRestoredOk = 'استُعيدت الورشة.';
  static const workshopMoreActions = 'إجراءات الورشة';
  static const workshopFee = 'رسم الاشتراك';
  static const workshopFeeHint = '٠ = ورشة مجانية';
  static const workshopInvalidFee = 'اكتب رقما صفرا أو أكبر.';
  static const workshopStatusLabel = 'الحالة';
  static const presentCount = 'الحاضرون';
  static const attendancePercent = 'نسبة الحضور';
  static const attendanceDate = 'تاريخ الحضور';
  static const absenceDate = 'تاريخ الغياب';
  static const checkInTime = 'الدخول';
  static const checkOutTime = 'الخروج';
  static const presentTotal = 'إجمالي الحضور';
  static const absentTotal = 'إجمالي الغياب';
  static const completedTotal = 'الحضور المكتمل';
  static const memberFilter = 'تصفية حسب العضو';
  static const allMembers = 'كل الأعضاء';
  static const attendanceDetails = 'تفاصيل الحضور';
  static const attendanceSummary = 'ملخص حضور الأعضاء';
  static const pendingTotal = 'دون تسجيل حضور';
  static const reportPage = 'صفحة';
  static const reportOf = 'من';
  static const pdfReady = 'تم إنشاء ملف PDF.';
  static const pdfError = 'تعذّر إنشاء ملف PDF.';
  static const capacityUsage = 'إشغال السعة';
  static const filterMembers = 'الأعضاء';
  static const filterGuests = 'الضيوف';

  // Settings (المزيد)
  static const settingsTitle = 'المزيد';
  static const sectionAccount = 'الحساب';
  static const sectionAppearance = 'المظهر';
  static const sectionApp = 'التطبيق';
  static const sectionOrgManagement = 'المؤسسة والإدارة';
  static const sectionSync = 'المزامنة';

  // ---------- Sync (local-first writes) ----------
  // The app saves locally first and synchronises afterwards. These strings
  // describe that to the user in plain terms — no ids, no wire codes, no
  // backend state names (see FRONTEND-BACKEND-INTEGRATION.md §3, prompt §10).
  static const syncNow = 'مزامنة الآن';
  static const syncStatusLabel = 'حالة المزامنة';
  static const syncAllSynced = 'كل التغييرات متزامنة';
  static const syncInProgress = 'جارٍ المزامنة…';
  static const syncPendingOne = 'تغيير واحد بانتظار المزامنة';
  // %d → Arabic-Indic count.
  static const syncPendingMany = '%d تغييرات بانتظار المزامنة';
  static const syncLastAtPrefix = 'آخر مزامنة ';
  static const syncNever = 'لم تتم المزامنة بعد';
  static const syncOfflineNote =
      'لا يوجد اتصال. تُحفظ تغييراتك محليًا وتُزامَن تلقائيًا عند عودة الاتصال.';
  static const syncFailedNote =
      'تعذّرت المزامنة الآن. تغييراتك محفوظة وستتم إعادة المحاولة تلقائيًا.';
  static const syncDoneNote = 'اكتملت المزامنة.';
  // Some changes went through and some did not — never reported as either a
  // clean success or a flat failure.
  static const syncPartialNote =
      'تمت مزامنة بعض التغييرات، وبقيت تغييرات أخرى بانتظار المزامنة.';
  // Shown after a local save that still has to travel.
  static const savedPendingSync = 'تم الحفظ · بانتظار المزامنة';
  // A run found at least one stale-write conflict (see conflict resolution
  // strings below) — never shown as a generic failure.
  static const syncNeedsReviewNote =
      'توجد تغييرات تحتاج مراجعة قبل إكمال المزامنة.';
  // The quiet Settings attention row for operations waiting on a human
  // conflict decision. %d → Arabic-Indic count.
  static const syncReviewOne = 'تغيير واحد يحتاج مراجعة';
  static const syncReviewMany = '%d تغييرات تحتاج مراجعة';
  // The attention row is the way in to the Needs Review list.
  static const syncReviewOpenHint = 'افتح قائمة المراجعة';

  // ---------- Sync Center (roadmap §6) ----------
  // One headline the admin can read in a second, one supporting sentence,
  // and counts in plain words. The headline strings below are deliberately
  // distinct from the count lines so the screen never says the same thing
  // twice, and none of them names a queue, a revision or a transport.
  static const syncHeadlinePending = 'توجد تغييرات بانتظار المزامنة';
  static const syncHeadlineOffline = 'لا يوجد اتصال بالإنترنت';
  static const syncHeadlineFailed = 'تعذر إكمال المزامنة';
  static const syncHeadlineNeedsReview = 'توجد تغييرات تحتاج مراجعتك';

  // The supporting sentence under the headline: what it means and what the
  // user can do about it. Distinct from the snackbar notes above on purpose —
  // a note reports one run, these describe the standing situation.
  static const syncBodyUpToDate = 'كل تغييراتك محفوظة ووصلت إلى الفريق.';
  static const syncBodyPending =
      'تُرسل تغييراتك تلقائيا، ويمكنك المزامنة الآن.';
  static const syncBodySyncing = 'يجري إرسال تغييراتك الآن.';
  static const syncBodyOffline =
      'أنت غير متصل بالإنترنت. ستتم المزامنة عند عودة الاتصال.';
  static const syncBodyFailed =
      'تعذر إكمال بعض التغييرات. يمكنك إعادة المحاولة.';
  static const syncBodyNeedsReview =
      'يوجد تعديل يحتاج مراجعتك قبل إكمال المزامنة.';

  // The connection chip. Shown only when a sync run actually proved one way
  // or the other — the app has no separate connectivity source to ask.
  static const syncConnected = 'متصل';
  static const syncDisconnected = 'غير متصل';

  static const syncLastSuccessPrefix = 'آخر مزامنة ناجحة: ';
  // Changes that were attempted and did not go through. Still saved, still
  // owed to the server. %d → Arabic-Indic count.
  static const syncFailedOne = 'تغيير واحد تعذر إرساله';
  static const syncFailedMany = '%d تغييرات تعذر إرسالها';
  static const syncNeedsInternet = 'المزامنة تحتاج اتصالا بالإنترنت.';
  // The one reassurance every sync/conflict error state has to carry.
  static const syncDataSafeNote = 'تغييراتك محفوظة على جهازك ولن تُفقد.';
  static const syncStatusLoading = 'جارٍ تحميل حالة المزامنة…';
  static const syncLoadFailedTitle = 'تعذر عرض حالة المزامنة';
  static const syncLoadFailedBody =
      'تغييراتك محفوظة على جهازك. أعد المحاولة لعرض الحالة.';
  static const settingsPalette = 'لوحة الألوان';
  static const settingsMode = 'السمة';
  static const settingsModeSystem = 'حسب النظام';
  static const appVersion = 'إصدار التطبيق';

  // ---- Settings hub (Point 1: hub + nested category screens) ----
  // The hub row/page title for quality + frame-rate. "Themes" reuses
  // settingsAppearance below; "Sync" reuses sectionSync above — the same
  // word already labels both the hub's section and its one row for
  // Organization, so this follows that existing pattern rather than adding
  // a near-duplicate string.
  static const settingsPerformanceTitle = 'الأداء والحركة';

  // ---------- Today / operations dashboard ----------
  // The landing screen answers one question: what is happening today, and
  // what needs a decision. Every line below describes a record that exists —
  // nothing here is raised speculatively (see `today_selectors.dart`).
  static const dashboardNoDetachmentTitle = 'لا مفرزة متاحة';
  static const dashboardNoDetachmentBody =
      'لا توجد مفرزة نشطة ضمن صلاحياتك. اطلب من المسؤول إضافتك إلى مفرزة '
      'لتظهر شفتات اليوم هنا.';
  static const dashboardSwitchDetachment = 'تبديل المفرزة';
  static const dashboardPickDetachment = 'اختر المفرزة';
  static const dashboardNoShiftsToday = 'لا شفتات اليوم في هذه المفرزة.';
  static const dashboardNoShiftNow = 'لا شفت يعمل الآن.';
  static const dashboardNextShift = 'الشفت التالي';
  static const dashboardNoNextShift = 'لا شفت قادم مجدول.';
  static const dashboardTomorrow = 'غدا';
  static const dashboardOpenShift = 'فتح الشفت';
  static const dashboardViewSchedule = 'عرض الجدول';
  // Attendance line on the running shift: present / assigned, with what is
  // still open beside it.
  static const dashboardPresent = 'حاضر';
  static const dashboardAwaiting = 'بلا تسجيل';
  // Alerts. %d → Arabic-Indic count.
  static const alertUnderstaffedTitle = 'شفت ناقص التغطية';
  static const alertUnderstaffedBody = 'ينقصه %d متطوعين';
  static const alertUnderstaffedBodyOne = 'ينقصه متطوع واحد';
  static const alertMissingAttendanceTitle = 'حضور غير مسجّل';
  static const alertMissingAttendanceBody = '%d أعضاء بلا تسجيل حضور';
  static const alertMissingAttendanceBodyOne = 'عضو واحد بلا تسجيل حضور';
  static const alertLowStockTitle = 'نقص في المخزن';
  static const alertLowStockBody = '%d أصناف عند حدّها الأدنى أو أقل';
  static const alertLowStockBodyOne = 'صنف واحد عند حدّه الأدنى أو أقل';
  static const alertExpiringTitle = 'أصناف قرب انتهائها';
  static const alertExpiringBody = '%d أصناف تنتهي قريبا';
  static const alertExpiringBodyOne = 'صنف واحد ينتهي قريبا';
  static const alertSyncFailedTitle = 'تعذّرت المزامنة';
  static const alertOpenAction = 'فتح';
  static const alertReviewAction = 'مراجعة';

  // ---------- Members module ----------
  static const membersApply = 'تطبيق';
  static const membersClearSearch = 'مسح البحث';
  static const membersEmptySearchSub =
      'جرّب اسما آخر، أو أزل التصفية لعرض كل الأعضاء.';
  static const membersFilters = 'تصفية';
  static const membersFiltersTitle = 'تصفية الأعضاء';
  static const membersFilterRole = 'الدور';
  static const membersFilterDepartment = 'القسم';
  static const membersClearFilters = 'إزالة التصفية';
  static const membersShowingCount = 'ظاهر %d من %d';
  static const memberContactSection = 'التواصل';
  static const memberContactHidden = 'بيانات التواصل غير متاحة لصلاحيتك.';
  static const memberNoPhone = 'لا رقم مسجّل لهذا العضو.';
  static const memberPhone = 'الهاتف';
  static const memberIdentitySection = 'البيانات';
  static const memberTodaySection = 'اليوم';
  static const memberNoAssignmentToday = 'لا إسناد لهذا العضو اليوم.';
  static const memberDetachmentLabel = 'المفرزة';
  static const memberRemovedTitle = 'لم يعد هذا العضو موجودا';
  static const memberRemovedBody =
      'ربما حُذف السجل من جهاز آخر. عد إلى قائمة الأعضاء.';
  static const memberBackToRoster = 'العودة إلى الأعضاء';

  // Profile — the signed-in administrator's own account.
  //
  // Only administrative accounts sign in to MTM (one main admin and a handful
  // of others), so this copy is about an account and its grant, never about a
  // volunteer's shifts, attendance or specialty. Those belong to the Members
  // module, which manages *other* people's records.
  static const profileName = 'الاسم';
  static const profileEmail = 'البريد الإلكتروني';
  static const profileOrg = 'المؤسسة';
  static const profileNoSession = 'لا جلسة نشطة.';
  static const profileNoSessionSub = 'سجّل الدخول لعرض حسابك.';
  static const profileAccountSection = 'بيانات الحساب';
  static const profileAccessSection = 'الصلاحيات';
  static const profileSecuritySection = 'الأمان والجلسات';
  static const profileAccessLevel = 'مستوى الصلاحيات';
  static const profileAccessFull = 'صلاحيات كاملة على المؤسسة';
  static const profileAccessOrg = 'صلاحيات على مستوى المؤسسة';
  static const profileAccessScoped = 'صلاحيات ضمن مفارز محددة';
  static const profileAccessNone = 'لا صلاحيات ممنوحة';
  static const profileAccessNote =
      'تُمنح صلاحيات حسابك من مشرف الحسابات، ويطبّقها الخادم على كل طلب.';
  static const profileManagesAdmins = 'إدارة حسابات المشرفين';
  static const profileEditsOrg = 'تعديل بيانات المؤسسة';
  static const profileScope = 'نطاق الصلاحيات';
  static const profileScopeOrgWide = 'كل المؤسسة';
  // %d → Arabic-Indic count of detachments carrying a grant.
  static const profileScopeOneDetachment = 'مفرزة واحدة';
  static const profileScopeManyDetachments = '%d مفارز';
  static const profileReadOnlyNote =
      'تعديل بيانات الحساب غير متاح من التطبيق حاليا. راجع مشرف الحسابات.';
  static const profileSecurityRow = 'الجلسات والتحقق بخطوتين';
  static const profilePasswordReset = 'إعادة تعيين كلمة المرور';
  static const profilePasswordResetSub =
      'يُرسل رمز تحقق إلى بريدك، ثم تختار كلمة مرور جديدة.';
  static const profileSignOutFailed = 'تعذّر تسجيل الخروج. حاول مرة أخرى.';
  static const profileGranted = 'ممنوحة';
  static const profileNotGranted = 'غير ممنوحة';

  // Security & sessions — `/more/security`.
  //
  // Plain administrative Arabic throughout: "التحقق بخطوتين" not MFA/TOTP,
  // "الجلسات النشطة" not tokens, "تسجيل الخروج" not revoke-current-token.
  static const securityAccountSection = 'حالة الحساب';
  static const securityMfa = 'التحقق بخطوتين';

  /// The server sends no MFA state — `AuthUser` has no such field and
  /// `API_CONTRACT.md` has no endpoint for one. Saying "مفعّل" here would be
  /// inventing a fact, so the screen says what is actually known.
  static const securityMfaUnknown = 'غير معروفة';
  static const securityMfaNote =
      'لا يذكر الخادم حالة التحقق بخطوتين لهذا الحساب، لذلك لا يمكن عرضها هنا. '
      'يمكنك بدء الإعداد أو إعادته في أي وقت.';
  static const securityMfaManage = 'إعداد';
  static const securitySessionsNote = 'الأجهزة التي سجّلت الدخول بهذا الحساب.';
  static const securitySessionsOne = 'جلسة نشطة واحدة';
  // %d → Arabic-Indic count of active sessions.
  static const securitySessionsMany = '%d جلسات نشطة';
  static const securityCurrentSession = 'هذه الجلسة';
  static const securityCurrentSessionNote =
      'لإنهاء هذه الجلسة استخدم تسجيل الخروج في أسفل الصفحة.';
  static const securityRevokeConfirm = 'إنهاء هذه الجلسة؟';
  static const securityRevokeConfirmBody =
      'سيُطلب تسجيل الدخول من جديد على ذلك الجهاز.';
  static const securityRevokeDone = 'أُنهيت الجلسة.';
  static const securityRevokeGone = 'هذه الجلسة لم تعد نشطة.';
  static const securityRevokeFailed =
      'تعذّر إنهاء هذه الجلسة. لم يتغيّر شيء. حاول مرة أخرى.';
  static const securityRevokeNotPermitted =
      'لا تملك صلاحية إنهاء هذه الجلسة. لم يتغيّر شيء.';
  static const securityRevokeOffline =
      'لا اتصال بالخادم. لم تُنهَ الجلسة. حاول بعد عودة الاتصال.';
  static const emptySessions = 'لا جلسات أخرى.';
  static const emptySessionsSub = 'هذا هو الجهاز الوحيد المسجّل حاليا.';
  static const startedAt = 'بدأت';

  // Notifications
  static const notifShiftReminders = 'تذكير بالشفتات';
  static const notifShiftRemindersSub = 'تنبيه قبل بداية شفتك بساعة.';
  static const notifStockAlerts = 'تنبيهات المخزون';
  static const notifStockAlertsSub = 'عند انخفاض صنف عن حدّه الأدنى.';
  static const notifWorkshopUpdates = 'تحديثات الورش';
  static const notifWorkshopUpdatesSub = 'تغيّر موعد أو مكان ورشة مسجّل فيها.';
  static const notifJoinRequests = 'طلبات الانضمام';
  static const notifJoinRequestsSub = 'عند تقديم طلب انضمام جديد لمفرزتك.';

  // ---------- Detachment groups (الجهات) ----------
  static const navDetachmentGroups = 'الجهات';
  static const detachmentGroupsTitle = 'الجهات';
  static const detachmentGroup = 'الجهة';
  static const searchDetachmentGroups = 'ابحث عن جهة';
  static const newDetachmentGroup = 'جهة جديدة';
  static const createDetachmentGroup = 'أنشئ جهة';
  static const editDetachmentGroup = 'تعديل الجهة';
  static const detachmentGroupName = 'اسم الجهة';
  static const detachmentGroupNamePlaceholder =
      'مثال: الهلال الأحمر — فرع دمشق';
  static const detachmentGroupNotes = 'وصف مختصر';
  static const detachmentGroupNotesPlaceholder = 'اختياري — لمن تتبع هذه الجهة';
  static const detachmentGroupDetachments = 'المفرزات';
  static const detachmentGroupMembers = 'الأعضاء';
  static const emptyDetachmentGroups = 'لا جهات بعد.';
  static const emptyDetachmentGroupsSub =
      'الجهة هي المظلّة التي تجمع مفرزاتك. أنشئ واحدة ثم أضف مفرزاتها.';
  static const deleteDetachmentGroup = 'حذف الجهة';
  static const deleteDetachmentGroupBody =
      'سيُحذف كل ما داخل هذه الجهة: المفرزات وأعضاؤها وشفتاتها ومخزونها. لا يمكن التراجع.';
  static const detachmentGroupDeleted = 'تم حذف الجهة';
  static const detachmentGroupEmptyDetachments = 'لا مفرزات في هذه الجهة بعد.';
  static const detachmentGroupEmptyDetachmentsSub =
      'أضف أول مفرزة لتبدأ بجدولة الشفتات وإدارة الفريق والمخزن.';
  static const openDetachmentGroup = 'فتح';
  static const detachmentGroupHint =
      'الجهة تجمع عدة مفرزات في نفس المكان تحت إدارة واحدة.';

  // ---------- Detachment lifecycle ----------
  static const deleteDetachment = 'حذف المفرزة';
  static const deleteDetachmentBody =
      'سيُحذف كل ما داخل المفرزة: الأعضاء والشفتات والمخزون. لا يمكن التراجع.';
  static const detachmentDeleted = 'تم حذف المفرزة';
  static const belongsTo = 'ضمن';

  // ---------- Schedule (الجدول) ----------
  static const scheduleTitle = 'جدول الشفتات';
  static const weekOf = 'أسبوع';
  static const thisWeek = 'هذا الأسبوع';
  static const nextWeek = 'الأسبوع القادم';
  static const prevWeek = 'الأسبوع السابق';
  static const daySat = 'السبت';
  static const daySun = 'الأحد';
  static const dayMon = 'الإثنين';
  static const dayTue = 'الثلاثاء';
  static const dayWed = 'الأربعاء';
  static const dayThu = 'الخميس';
  static const dayFri = 'الجمعة';
  static const addShift = 'أضف شفتا';
  static const editShift = 'تعديل الشفت';
  static const deleteShift = 'حذف الشفت';
  static const deleteShiftBody =
      'سيُحذف الشفت ومن أُسند إليه. لا يمكن التراجع.';
  static const shiftDeleted = 'تم حذف الشفت';
  static const shiftSaved = 'تم حفظ الشفت';
  static const shiftPeriod = 'الفترة';
  static const periodMorning = 'صباحي';
  static const periodEvening = 'مسائي';
  static const periodNight = 'ليلي';
  static const periodCustom = 'مخصص';
  static const periodMorningTime = '٠٨:٠٠ – ١٤:٠٠';
  static const periodEveningTime = '١٤:٠٠ – ٢٠:٠٠';
  static const periodNightTime = '٢٠:٠٠ – ٠٢:٠٠';
  static const shiftStart = 'من';
  static const shiftEnd = 'إلى';
  static const shiftCenter = 'المركز';
  static const shiftNeededLabel = 'عدد المطلوبين';
  static const shiftNeededHelp = 'كم شخصا يحتاج هذا الشفت ليكتمل؟';
  static const repeatWeekly = 'كرّره كل أسبوع';
  static const repeatWeeklyHelp =
      'سيظهر تلقائيا في نفس اليوم من كل أسبوع، ويمكنك إيقافه لاحقا.';
  static const repeatOnDays = 'كرّر الشفت في أيام محددة';
  static const repeatOnDaysHelp =
      'اختر الأيام التي يتكرر فيها هذا الشفت. تُنشأ نسخة لكل يوم، وتُدار كل واحدة على حدة. اليوم المقفل به مسندون ولا يُحذف.';
  static const daysUnit = 'أيام';
  static const crossesMidnight = 'ينتهي بعد منتصف الليل';
  static const copyLastWeek = 'انسخ الأسبوع السابق';
  static const copyLastWeekDone = 'تم نسخ شفتات الأسبوع السابق';
  static const copyLastWeekEmpty = 'لا شفتات في الأسبوع السابق لنسخها.';
  static const applyTemplates = 'طبّق الشفتات المتكررة';
  static const applyTemplatesDone = 'تمت إضافة الشفتات المتكررة';
  static const applyTemplatesEmpty = 'لا شفتات متكررة محفوظة بعد.';
  static const templatesTitle = 'الشفتات المتكررة';
  static const templatesSub =
      'قوالب تتكرر أسبوعيا. أوقف أيّها متى شئت دون أن تفقد سجلّ الأسابيع الماضية.';
  static const templateStop = 'إيقاف التكرار';
  static const templateStopped = 'تم إيقاف التكرار';
  static const noShiftsToday = 'لا شفتات في هذا اليوم.';
  static const noShiftsTodaySub = 'أضف شفتا، أو انسخ جدول الأسبوع السابق.';
  static const manageShiftTitle = 'إدارة الشفت';
  static const shiftMembersSection = 'المسندون';
  static const moreMembers = 'آخرون';
  static const templatesButton = 'القوالب';
  static const templateDays = 'أيام';
  static const weekCoverage = 'تغطية الأسبوع';
  static const weekShifts = 'شفتات الأسبوع';
  static const weekGaps = 'شفتات ناقصة';
  static const assignedLabel = 'مسند';
  static const removeFromShift = 'إزالة من الشفت';
  static const shiftConflict = 'هذا العضو مسند لشفت آخر يتقاطع مع هذا الوقت.';
  static const quickFill = 'إسناد سريع';
  static const quickFillHelp = 'يملأ النقص بأعضاء متاحين في هذا الوقت.';
  static const quickFillDone = 'تمت تعبئة النقص';
  static const quickFillNone = 'لا يوجد أعضاء متاحون في هذا الوقت.';
  static const availableNow = 'متاح';
  static const busyNow = 'مشغول في شفت آخر';
  static const searchMembers = 'ابحث عن عضو';
  static const selectedMembers = 'الأعضاء المسندون';
  static const unselectedMembers = 'أعضاء المفرزة المتاحون';
  static const dragMembersHere = 'اضغط على العضو أو اسحبه إلى هنا';
  static const manualMemberName = 'إدخال اسم عضو يدويا';
  static const addAndAssign = 'إضافة وإسناد';
  static const duplicateMemberName =
      'يوجد عضو بهذا الاسم. اختر العضو الموجود بدلا من إنشاء سجل مكرر.';
  static const memberCreatedAndAssigned = 'تمت إضافة العضو وإسناده للشفت.';
  static const memberAssigned = 'تم إسناد العضو للشفت.';
  static const noMatchingMembers = 'لا يوجد أعضاء مطابقون للبحث.';
  static const checkInDateTime = 'تاريخ ووقت الدخول';
  static const checkOutDateTime = 'تاريخ ووقت الخروج';
  static const editCheckIn = 'تعديل الدخول';
  static const editCheckOut = 'تعديل الخروج';
  static const checkoutRequiresCheckin = 'سجّل الدخول أولا قبل تسجيل الخروج.';
  static const checkoutBeforeCheckin =
      'لا يمكن أن يكون وقت الخروج قبل وقت الدخول.';
  static const startAfterEnd = 'وقت البداية يجب أن يختلف عن وقت النهاية.';
  static const guideAddShift =
      'ابدأ باختيار فترة جاهزة — يمكنك تعديل الوقت بعدها.';

  // ---------- Attendance edit window & corrections ----------
  static const attendanceWindowExpired =
      'انتهت مهلة التعديل الاعتيادي لهذا الشفت (ساعة واحدة بعد نهايته).';
  static const attendanceWindowClosedOrdinary =
      'انتهت المهلة الاعتيادية لتعديل هذا الحضور. المعروض هنا للاطلاع فقط، '
      'ولا يمكن تعديله من هذه الشاشة بعد الآن.';
  static const addCorrection = 'إضافة تصحيح';
  static const correctionHistoryTitle = 'سجل التصحيحات';
  static const noCorrectionsYet = 'لا تصحيحات مسجّلة على هذا الحضور.';
  static const correctionReasonLabel = 'سبب التصحيح';
  static const correctionReasonPlaceholder = 'اشرح سبب هذا التصحيح — إلزامي';
  static const correctionReasonRequired = 'سبب التصحيح مطلوب.';
  static const correctionBefore = 'قبل';
  static const correctionAfter = 'بعد';
  static const correctedBy = 'صحّحه';
  static const saveCorrection = 'حفظ التصحيح';
  static const cancelCorrection = 'إلغاء';

  // ---------- Inventory lifecycle ----------
  static const newItem = 'صنف جديد';
  static const editItem = 'تعديل الصنف';
  static const itemName = 'اسم الصنف';
  static const itemNamePlaceholder = 'مثال: أدرينالين ١ ملغ/مل';
  static const itemUnit = 'الوحدة';
  static const itemUnitPlaceholder = 'مثال: أمبولة';
  static const itemOpeningStock = 'الكمية الحالية';
  static const packagingUnit = 'وحدة التعبئة';
  static const packagingIndividual = 'وحدة فردية';
  static const packagingStrip = 'شريط';
  static const packagingCarton = 'كرتونة';
  static const individualUnitsCount = 'عدد الوحدات الفردية';
  static const stripsCount = 'عدد الشرائط';
  static const cartonsCount = 'عدد الكراتين';
  static const unitsPerStrip = 'الوحدات الفردية في كل شريط';
  static const stripsPerCarton = 'الشرائط في كل كرتونة';
  static const baseUnits = 'وحدة فردية';
  static const availableBreakdown = 'المتاح';
  static const convertedQuantity = 'ما يعادل بالوحدات الفردية';
  static const cartonsLabel = 'كرتونة';
  static const stripsLabel = 'شريط';
  static const individualUnitsLabel = 'وحدة فردية';
  static const stockBeforeAfter = 'الرصيد قبل/بعد';
  static const recordedBy = 'سجّلها';
  static const packagingMetadataRequired =
      'حدّد عدد الوحدات في الشريط وعدد الشرائط في الكرتونة قبل اختيار هذه التعبئة.';
  static const positiveIntegerRequired = 'أدخل عددا صحيحا أكبر من صفر.';
  static const insufficientStock = 'الكمية المطلوبة أكبر من المخزون المتاح.';
  static const itemMinimum = 'الحد الأدنى';
  static const itemMinimumHelp = 'عند نزول الكمية تحت هذا الرقم يظهر تنبيه.';
  static const itemExpiry = 'تاريخ الانتهاء';
  static const itemNoExpiry = 'بلا تاريخ انتهاء';
  static const clearItemExpiry = 'مسح تاريخ الانتهاء';
  static const deleteItem = 'حذف الصنف';
  static const deleteItemBody = 'سيُحذف الصنف وكل حركاته. لا يمكن التراجع.';
  static const deleteItemUnchanged =
      'لا تتأثر بقية أصناف المخزون ولا بيانات المفرزة.';
  static const itemDeleted = 'تم حذف الصنف';
  static const itemSaved = 'تم حفظ الصنف';
  static const addItem = 'أضف صنفا';
  static const filterLow = 'منخفض';
  static const filterExpiring = 'قارب الانتهاء';
  static const searchItems = 'ابحث عن صنف';
  static const noMatchingInventory = 'لا أصناف تطابق البحث.';
  static const noMatchingInventorySub = 'جرّب اسما آخر، أو اعرض كل الأصناف.';
  static const clearInventoryFilters = 'مسح البحث والتصفية';
  static const invalidNumber = 'أدخل رقما صحيحا.';

  // ---------- Stats + export ----------
  static const statsOverview = 'لمحة';
  static const statsMembers = 'الفريق';
  static const statsShifts = 'الشفتات';
  static const statsStorage = 'المخزن';
  static const exportReport = 'تصدير تقرير';
  static const exportTitle = 'بناء التقرير';
  static const exportSub = 'اختر ما تريد ظهوره في الملف، ثم عاين قبل التصدير.';
  static const exportSections = 'أقسام التقرير';
  static const exportFormat = 'صيغة الملف';
  static const exportPdf = 'PDF';
  static const exportExcel = 'Excel (CSV)';
  static const exportPreview = 'معاينة';
  static const exportRange = 'المدى الزمني';
  static const rangeWeek = 'أسبوع';
  static const rangeMonth = 'شهر';
  static const rangeQuarter = 'ثلاثة أشهر';
  static const secSummary = 'الملخّص العام';
  static const secSummarySub = 'اسم المفرزة، الجهة، التغطية، عدد الأعضاء.';
  static const secMembers = 'جدول الأعضاء';
  static const secMembersSub = 'الاسم، القسم، الرقم، الدور، الحضور.';
  static const secShifts = 'جدول الشفتات';
  static const secShiftsSub = 'اليوم، الوقت، المركز، المسندون، النقص.';
  static const secStorage = 'جرد المخزن';
  static const secStorageSub = 'الصنف، الكمية، الحد الأدنى، الصلاحية.';
  static const secStorageLow = 'الأصناف المنخفضة فقط';
  static const secStorageLowSub = 'قائمة مختصرة لما يحتاج تزويدا.';
  static const secAttendance = 'الحضور';
  static const secAttendanceSub =
      'الإجماليات، وسجل أيام كل عضو، ونسبة الحضور اليومية خلال المدى المختار.';
  static const secCoverage = 'منحنى التغطية';
  static const secCoverageSub = 'نسبة تغطية الشفتات اليومية.';
  static const secConsumption = 'استهلاك المخزون';
  static const secConsumptionSub = 'الوحدات المصروفة يوميا.';
  static const exportNothingSelected = 'اختر قسما واحدا على الأقل.';
  static const exportCopy = 'نسخ محتوى الملف';
  static const exportCopied = 'نُسخ محتوى التقرير إلى الحافظة';
  static const exportSelectAll = 'تحديد الكل';
  static const exportClearAll = 'إلغاء التحديد';
  static const reportGeneratedAt = 'أُنشئ في';
  static const reportFor = 'تقرير مفرزة';
  static const noData = 'لا بيانات';
  static const sectionsChosen = 'قسم مختار';

  // ---------- Detachment status strip ----------
  // Shown under the detail-shell app bar, on every tab. The lifecycle line
  // is copied from the legacy details header (نشط / غير نشط); the storage
  // line is new — a rollup of the stock the detachment holds.
  static const detachmentStatusStrip = 'حالة المفرزة';
  static const storageStatusHealthy = 'المخزن مكتمل';
  static const storageStatusLow = 'نقص في المخزن';
  static const storageStatusExpiring = 'أصناف قرب انتهائها';
  static const storageStatusDepleted = 'أصناف نفدت';
  static const storageStatusEmpty = 'لا مخزن';

  // ---------- Member status page ----------
  static const memberStatusTitle = 'حالة العضو';
  static const memberStatusCurrent = 'الحالة الآن';
  static const memberAttendanceLog = 'سجل الحضور';
  static const memberAttendanceLogSub =
      'كل يوم أُسند إليه فيه شفت، ووقت الدخول والخروج.';
  static const noAttendanceRecords = 'لا سجل حضور بعد';
  static const noAttendanceRecordsSub =
      'لم يُسنَد هذا العضو إلى أي شفت خلال هذه المدة.';
  static const notCheckedInShort = 'بلا تسجيل دخول';

  // ---------- Notifications Center ----------
  // The operational feed at `/notifications`. Distinct from
  // `settingsNotifications` ("التنبيهات"), which is the push-preference
  // screen at `/more/notifications` — one is what happened, the other is what
  // the device is allowed to interrupt you for.
  static const notificationsTitle = 'الإشعارات';
  static const notificationsOpen = 'فتح الإشعارات';
  static const notificationsUnreadOne = 'إشعار واحد غير مقروء';
  static const notificationsUnreadMany = '%d إشعارات غير مقروءة';
  static const notificationsNoneUnread = 'لا إشعارات غير مقروءة';
  static const notificationsEmptyTitle = 'لا إشعارات';
  static const notificationsEmptyBody =
      'كل شيء على ما يرام. سيظهر هنا ما يحتاج انتباهك في مفرزتك.';
  static const notificationsMarkAllRead = 'تعليم الكل كمقروء';
  static const notificationsMarkAllReadDone = 'تم تعليم الإشعارات كمقروءة';
  static const notificationsMarkReadFailed = 'تعذّر حفظ حالة القراءة.';
  static const notificationsTargetGone = 'لم يعد هذا السجل متاحا.';
  static const notificationsUnreadDot = 'غير مقروء';
  static const notificationsGroupUpcoming = 'قادم';
  static const notificationsGroupToday = 'اليوم';
  static const notificationsGroupYesterday = 'أمس';
  static const notificationsGroupEarlier = 'أقدم';

  // One title and one short line per supported kind. Every kind here is
  // derived from a real record — nothing is worded for a condition the app
  // cannot actually observe.
  static const notifShiftUnderstaffedTitle = 'شفت ناقص التغطية';
  static const notifShiftUnderstaffedBody = 'ينقص %d متطوعا';
  static const notifShiftAttendanceTitle = 'حضور غير مسجّل';
  static const notifShiftAttendanceBody = 'بقي %d بلا تسجيل';
  static const notifShiftSoonTitle = 'شفت يبدأ قريبا';
  static const notifShiftSoonBody = 'يبدأ %s';
  static const notifStockDepletedTitle = 'صنف نفد من المخزن';
  static const notifStockDepletedBody = 'لا يوجد رصيد';
  static const notifStockLowTitle = 'صنف تحت الحد الأدنى';
  static const notifStockLowBody = 'بقي %d';
  static const notifStockExpiringTitle = 'صنف قرب انتهاء صلاحيته';
  static const notifStockExpiringBody = 'ينتهي %s';
  static const notifSyncConflictTitle = 'تغيير يحتاج مراجعة';
  static const notifSyncConflictBody = 'تعديلك يتعارض مع النسخة الحالية';
  static const notifSyncFailedTitle = 'تعذّرت مزامنة تغيير';
  static const notifSyncFailedBody = 'ما زال محفوظا على جهازك';

  // ---------- Admin experience (presentation labels) ----------
  //
  // How *broad* one session's UI is, derived from capability breadth inside
  // the tenant application. Not the account's product surface — that is
  // `AuthRole` and the three labels below it. The mapping is stated once, in
  // `core/access/admin_experience.dart`.
  static const adminExperienceFull = 'إدارة كاملة';
  static const adminExperienceScoped = 'إدارة محددة';

  // ---------- Account role (product surface) ----------
  //
  // The human-readable name of the account level the server asserted
  // (`AuthUser.role`). Identity only — nothing opens because of it; every
  // action still resolves through `Capabilities.canIn`.
  static const roleSuperAdmin = 'مدير المنصة';
  static const roleMainAdmin = 'المدير الرئيسي';
  static const roleSimpleAdmin = 'مدير مساعد';
  static const roleCustomerDemo = 'تجربة عميل';
  static const simpleAdminsTitle = 'المديرون المساعدون';
  static const simpleAdminsRowSub = 'الحسابات والدعوات والصلاحيات';
  static const simpleAdminsLead =
      'إدارة حسابات المديرين المساعدين ودعواتهم وصلاحياتهم داخل هذه المؤسسة.';
  static const simpleAdminInvite = 'دعوة مدير مساعد';
  static const simpleAdminsCurrent = 'الحسابات الحالية';
  static const simpleAdminsCurrentEmpty = 'لا توجد حسابات مدير مساعد حاليًا.';
  static const simpleAdminInvitations = 'الدعوات';
  static const simpleAdminInvitationsEmpty = 'لا توجد دعوات بعد.';
  static const simpleAdminActive = 'حساب نشط';
  static const simpleAdminSuspended = 'حساب موقوف';
  static const simpleAdminEditCapabilities = 'تعديل الصلاحيات';
  static const simpleAdminCancelInvitation = 'إلغاء الدعوة';
  static const simpleAdminCancelInvitationTitle = 'إلغاء هذه الدعوة؟';
  static const simpleAdminCancelInvitationBody =
      'لن يتمكن هذا البريد من إكمال الربط بهذه الدعوة. لا يتأثر أي حساب حالي.';

  /// The two halves of [simpleAdminCancelInvitationBody], stated separately.
  static const simpleAdminCancelInvitationChange =
      'لن يتمكن هذا البريد من إكمال الربط بهذه الدعوة.';
  static const simpleAdminCancelInvitationUnchanged =
      'لا يتأثر أي حساب حالي، ويمكن إرسال دعوة جديدة لاحقا.';
  static const simpleAdminInvitationCancelled = 'أُلغيت الدعوة.';
  static const simpleAdminInvitationPending = 'بانتظار إكمال الإعداد';
  static const simpleAdminInvitationCancelledStatus = 'ملغاة';
  static const simpleAdminInvitationAccepted = 'مقبولة';
  static const simpleAdminInvitationExpired = 'منتهية';
  static const simpleAdminOnboardingNote =
      'تُربط الدعوة بالمؤسسة والبريد والصلاحيات. يثبت المدعو ملكية البريد ويكمل تدفق الانضمام؛ لا ينشئ هذا القسم كلمة مرور أو حسابًا نشطًا.';
  static const simpleAdminInviteLead =
      'حدّد البريد والصلاحيات الأولية. يحدد الخادم المؤسسة ودور المدير المساعد من جلستك الحالية.';
  static const simpleAdminNameRequired = 'أدخل الاسم المقترح.';
  static const simpleAdminNameLabel = 'الاسم المقترح';
  static const simpleAdminSaving = 'جارٍ الحفظ…';
  static const simpleAdminEmailInvalid = 'أدخل بريدًا إلكترونيًا صالحًا.';
  static const simpleAdminCapabilities = 'الصلاحيات الأولية';
  static const simpleAdminCapabilitiesLead =
      'لا تظهر صلاحيات الوحدات غير المتاحة في خطة المؤسسة. يظل الخادم صاحب القرار النهائي.';
  static const simpleAdminCapabilityRequired = 'اختر صلاحية واحدة على الأقل.';
  static const simpleAdminSendInvitation = 'إرسال الدعوة';
  static const simpleAdminNoPasswordNote =
      'لا توجد كلمة مرور مؤقتة. ينشئ المدعو بيانات دخوله بنفسه ضمن تدفق الانضمام الآمن.';
  static const simpleAdminInvitationSent = 'أُرسلت دعوة المدير المساعد.';
  static const simpleAdminDuplicateInvitation =
      'يوجد حساب أو دعوة معلّقة لهذا البريد.';
  static const simpleAdminActionFailed =
      'تعذّر إكمال الإجراء. حدّث الصفحة وحاول مجددًا.';
  static const simpleAdminLoadFailed = 'تعذّر تحميل حسابات المديرين المساعدين.';
  // Point 18B polish — grouped capability control and a grant summary.
  static const simpleAdminCapabilitiesGranted = 'الصلاحيات الممنوحة';
  static const simpleAdminCapabilityCountSuffix = ' صلاحية مفعّلة';
  static const simpleAdminGroupTeam = 'المفرزات والأعضاء';
  static const simpleAdminGroupShifts = 'الشفتات والحضور';
  static const simpleAdminGroupInventory = 'المخزون';
  static const simpleAdminGroupWorkshops = 'الورش';
  static const simpleAdminGroupInsights = 'الإحصاءات والإعلانات';
  static const profileRole = 'نوع الحساب';

  // ---------- Global Search ----------
  //
  // One screen, four data categories, and no command palette: every row is a
  // record that exists somewhere else in the app and opens the surface that
  // already owns it. Which categories a session is offered is decided once,
  // by `AdminView.searchableCategories`.
  static const globalSearchTitle = 'البحث';
  static const globalSearchOpen = 'بحث';
  static const globalSearchHint = 'اكتب اسما أو كلمة';
  static const globalSearchClear = 'مسح البحث';
  static const globalSearchCategoryFilter = 'تصفية حسب النوع';

  /// Singular nouns, composed into the prompt from the categories this
  /// session may actually search — never the full four when only two are
  /// theirs.
  static const searchNounMember = 'عضو';
  static const searchNounDetachment = 'مفرزة';
  static const searchNounShift = 'شفت';
  static const searchNounItem = 'صنف';

  /// Group headings and the category chips.
  static const searchGroupMembers = 'الأعضاء';
  static const searchGroupDetachments = 'المفارز';
  static const searchGroupShifts = 'الشفتات';
  static const searchGroupInventory = 'المخزن';

  static const globalSearchPromptTitle = 'ابدأ بالبحث';
  static const globalSearchPromptBody = 'ابدأ بالبحث عن %s...';
  static const globalSearchShortTitle = 'أكمل الكلمة';
  static const globalSearchShortBody = 'اكتب حرفين على الأقل.';
  static const globalSearchNoResultsTitle = 'لا توجد نتائج مطابقة.';
  static const globalSearchNoResultsBody = 'جرّب اسما أو كلمة أخرى.';
  static const globalSearchRestrictedTitle = 'لا يوجد ما يمكن البحث فيه';
  static const globalSearchRestrictedBody =
      'لم تُمنح صلاحية على بيانات قابلة للبحث بعد. راجع مسؤول المؤسسة.';
  static const globalSearchOfflineBody =
      'لا توجد نسخة محفوظة على هذا الجهاز للبحث فيها.';

  /// One source failed while the others answered — the page keeps what it
  /// has and names only what is missing.
  static const globalSearchDegraded = 'تعذّر تحميل: %s';
  static const globalSearchResultGone = 'لم يعد هذا العنصر متاحًا.';

  static const globalSearchResultsOne = 'نتيجة واحدة';
  static const globalSearchResultsMany = '%d نتائج';
  static const globalSearchMoreResults = 'و%d نتيجة أخرى';

  /// A shift row names the person answerable for it when one is assigned.
  static const searchShiftSupervisedBy = 'بإشراف %s';

  // ---------- Announcements (internal admin notices) ----------
  //
  // An internal operational notice one administrator sends to the
  // administrators of one or more detachments. Not advertising, not a public
  // announcement, and never seen by volunteers — nobody but an administrator
  // signs into this app.
  //
  // The vocabulary is deliberately the four words a beginner already uses:
  // the notice, the detachment, where it shows, how long it lasts. Nothing
  // here names an audience resolver, a delivery scope, a queue or a TTL.
  static const announcementsTitle = 'الإعلانات';
  static const announcementsManage = 'إدارة الإعلانات';
  static const announcementLabel = 'إعلان إداري';
  static const announcementNew = 'إعلان جديد';
  static const announcementCompose = 'نشر إعلان';
  static const announcementText = 'نص الإعلان';
  static const announcementTextHint =
      'اكتب ما تريد إبلاغه لمسؤولي المفرزة. مثال: تنبيه بخصوص شفت ٤:٠٠–١٠:٠٠ '
      'اليوم، يرجى الحضور قبل بداية الشفت بـ١٥ دقيقة.';
  static const announcementTargets = 'المفرزة';
  static const announcementAddTarget = 'إضافة مفرزة أخرى';
  static const announcementRemoveTarget = 'إزالة المفرزة';
  static const announcementPickTarget = 'اختر مفرزة';
  static const announcementPlacements = 'مكان الظهور';
  static const announcementPlacementNotifications = 'الإشعارات';
  static const announcementPlacementNotificationsHelp =
      'دائما. يبقى الإعلان في سجل الإشعارات.';
  static const announcementPlacementHome = 'الرئيسية';
  static const announcementPlacementHomeHelp = 'يظهر أعلى الرئيسية لمدة ساعة.';
  static const announcementPlacementDetachment = 'داخل المفرزة';
  static const announcementPlacementDetachmentHelp =
      'يظهر في صفحة المفرزة حتى انتهاء مدة الإعلان.';
  static const announcementDuration = 'مدة الإعلان';
  static const announcementDurationHour = 'ساعة';
  static const announcementDurationSixHours = '٦ ساعات';
  static const announcementDurationTwelveHours = '١٢ ساعة';
  static const announcementDurationDay = 'يوم';
  static const announcementDurationTwoDays = 'يومان';
  static const announcementDurationCustom = 'تاريخ محدد';
  static const announcementPickDate = 'اختر تاريخ الانتهاء';
  static const announcementEndsAt = 'ينتهي %s';
  static const announcementPublish = 'نشر الإعلان';
  static const announcementPublished = 'تم نشر الإعلان';
  static const announcementWithdraw = 'إيقاف الإعلان';
  static const announcementWithdrawTitle = 'إيقاف الإعلان؟';
  static const announcementWithdrawBody =
      'سيتوقف ظهوره في الرئيسية وداخل المفرزة. يبقى في سجل الإشعارات.';
  static const announcementWithdrawn = 'تم إيقاف الإعلان';

  /// The refusals, one line each. Resolved from `AnnouncementRefusal` so a
  /// test asserts on the value and never on this text.
  static const announcementTextRequired = 'اكتب نص الإعلان.';
  static const announcementTextTooShort = 'النص قصير جدا.';
  static const announcementTextTooLong = 'النص طويل جدا.';
  static const announcementTargetRequired = 'اختر مفرزة واحدة على الأقل.';
  static const announcementTargetNotPermitted =
      'لم تعد لديك صلاحية النشر في إحدى المفارز المختارة. راجع الاختيار.';
  static const announcementTargetArchived =
      'إحدى المفارز المختارة مؤرشفة، ولا يمكن نشر إعلان جديد فيها.';
  static const announcementExpiryInvalid = 'اختر وقت انتهاء في المستقبل.';
  static const announcementNeedsConnection =
      'يحتاج هذا الإجراء إلى اتصال بالإنترنت.';

  /// Lifetime, as the management list states it.
  static const announcementStateActive = 'نشط';
  static const announcementStateExpired = 'انتهى';
  static const announcementStateWithdrawn = 'موقوف';
  static const announcementOnHomeNow = 'على الرئيسية الآن';
  static const announcementTargetsCountOne = 'مفرزة واحدة';
  static const announcementTargetsCountMany = '%d مفارز';

  /// The dashboard promotion.
  static const announcementHomeMore = 'يوجد %d إعلانات أخرى';
  static const announcementHomeMoreOne = 'يوجد إعلان آخر';
  static const announcementOpenAll = 'عرض الإعلانات';

  /// Empty and restricted states.
  static const announcementsEmptyTitle = 'لا إعلانات';
  static const announcementsEmptyBody =
      'لم يُنشر أي إعلان بعد. أنشئ إعلانا ليصل مسؤولي المفرزة.';
  static const announcementsRestrictedTitle = 'لا صلاحية للنشر';
  static const announcementsRestrictedBody =
      'لم تُمنح صلاحية نشر الإعلانات. راجع مسؤول المؤسسة.';
  static const announcementNoTargetsTitle = 'لا توجد مفرزة متاحة';
  static const announcementNoTargetsBody =
      'لا توجد مفرزة نشطة يمكنك النشر فيها.';
  static const announcementGone = 'لم يعد هذا العنصر متاحًا.';

  // ---------- Clear notifications ----------
  //
  // Deliberately not "mark all read": one hides a badge, the other removes
  // history. The confirmation names exactly what goes and what stays, because
  // an administrator must never discover afterwards that a shift warning was
  // deleted along with a notice.
  static const notificationsClear = 'مسح الإشعارات';
  static const notificationsClearTitle = 'مسح سجل الإعلانات؟';
  static const notificationsClearBody =
      'يُمسح سجل الإعلانات من هذه القائمة. تنبيهات الشفتات والمخزن والمزامنة '
      'تبقى لأنها تصف حالة قائمة الآن، ولا يُحذف أي سجل من سجلات العمل.';
  static const notificationsClearDone = 'تم مسح سجل الإعلانات';
  static const notificationsClearNothing = 'لا يوجد سجل إعلانات لمسحه';
  static const notificationsClearFailed = 'تعذّر مسح السجل.';

  // ---------- Pricing ----------
  static const sectionSubscription = 'الاشتراك';
  static const pricingTitle = 'الاشتراك والأسعار';
  static const pricingRowSub = 'الخطط والأسعار وطرق الاشتراك';
  static const pricingIntroTitle = 'خطط واضحة لمنتج واحد كامل';
  static const pricingIntro = 'أعجبتك $productNameAr؟ شاهد الخطط';
  static const pricingFullAccess =
      'جميع مدد الاشتراك تتضمن كامل ميزات $productNameAr.';
  static const pricingOneMonth = 'شهر واحد';
  static const pricingThreeMonths = '٣ أشهر';
  static const pricingSixMonths = '٦ أشهر';
  static const pricingTwelveMonths = '١٢ شهرا';
  static const pricingPerMonth = ' / شهر';
  static const pricingBestValue = 'أفضل قيمة';
  static const pricingSave = 'وفّر ';
  static const pricingSpecialOffer = 'عرض خاص';
  static const pricingActiveOffer = 'عرض عام متاح الآن';
  static const pricingCouponTitle = 'لديك كوبون؟';
  static const pricingCouponHint = 'رمز الكوبون';
  static const pricingCouponValidate = 'تحقق من الكوبون';
  static const pricingCouponValid = 'الكوبون صالح.';
  static const pricingCouponInvalid = 'الكوبون غير صالح أو غير متاح.';
  static const pricingCouponWrongDuration =
      'الكوبون صالح لمدة أخرى. اختر المدة المخصصة له لرؤية السعر.';
  static const pricingCouponOfferBetter =
      'الكوبون صالح، لكن العرض الحالي يمنحك سعراً أفضل أو مساوياً.';
  static const pricingContactTitle = 'للاشتراك تواصل معنا';
  static const pricingContactBody =
      'اختر وسيلة التواصل المناسبة وأخبرنا بمدة الاشتراك المختارة.';
  static const pricingTelegram = 'Telegram';
  static const pricingWhatsApp = 'WhatsApp';
  static const pricingEmail = 'البريد الإلكتروني';
  static const pricingOpen = 'فتح';
  static const pricingContactCopied = 'تم نسخ بيانات التواصل';
  static const pricingContactUnsupported =
      'تعذّر فتح التطبيق على هذا الجهاز. يمكنك نسخ بيانات التواصل.';
  static const pricingSelected = 'الخطة المحددة';
  static const demoSeePlans = 'شاهد الخطط';
  static const demoPricingPrompt = 'أعجبتك $productNameAr؟ شاهد الخطط';

  // Platform commerce — local development/test controls only.
  static const platformOpsCommerce = 'الأسعار والعروض';
  static const platformCommerceTitle = 'الأسعار والعروض';
  static const platformCommerceLead =
      'الأسعار والعروض والكوبونات التي يراها العملاء عند الاشتراك.';

  /// The truthful caveat, kept — this build does not take payment — but as a
  /// note at the foot of the panel rather than a warning chip under its
  /// title. A commercial control panel that opens by announcing it is a test
  /// build reads as unfinished on every other screen too.
  static const platformCommerceDevOnly = 'ملاحظة عن هذا البناء';
  static const platformCommerceDevOnlyNote =
      'تُحفظ هذه الإعدادات محليا في هذا الجهاز، ولا يتم عبرها أي دفع. '
      'يتولى الخادم التسعير والتحصيل عند وصله.';
  static const platformCommerceBasePrices = 'الأسعار الأساسية';
  static const platformCommerceBasePricesNote =
      'تُعرض الأسعار هنا للقراءة فقط ولا تُعدّل من هذا البناء.';
  static const platformCommerceOffers = 'العروض العامة';
  static const platformCommerceCoupons = 'الكوبونات';
  static const platformCommerceCreateOffer = 'إنشاء عرض عام';
  static const platformCommerceEditOffer = 'تعديل العرض العام';
  static const platformCommerceCreateCoupon = 'إنشاء كوبون';
  static const platformCommerceEditCoupon = 'تعديل الكوبون';
  static const platformCommerceEnabled = 'مفعّل';
  static const platformCommerceDisabled = 'معطّل';
  static const platformCommerceTarget = 'المدة المستهدفة';
  static const platformCommerceDiscountType = 'نوع الخصم';
  static const platformCommercePercentage = 'نسبة مئوية';
  static const platformCommerceFixedPrice = 'سعر نهائي ثابت';
  static const platformCommerceValue = 'القيمة';
  static const platformCommerceOfferTitle = 'عنوان العرض (اختياري)';
  static const platformCommerceCouponCode = 'رمز الكوبون';
  static const platformCommerceAssignment = 'التخصيص';
  static const platformCommercePublic = 'أي شخص يملك الرمز';
  static const platformCommerceTargeted = 'حساب محدد';
  static const platformCommerceAccountId = 'معرّف الحساب';
  static const platformCommerceInternalNote = 'ملاحظة داخلية (اختيارية)';
  static const platformCommerceNoOffers = 'لا توجد عروض عامة.';
  static const platformCommerceNoCoupons = 'لا توجد كوبونات.';
  static const platformCommerceSaved = 'تم حفظ الإعداد المحلي.';
  static const platformCommerceInvalid = 'تحقق من الحقول والقيمة.';
  static const platformCommerceConflict =
      'يوجد عرض عام مفعّل لهذه المدة بالفعل.';
  static const platformCommerceCodeTaken = 'رمز الكوبون مستخدم بالفعل.';
  static const platformCommerceRemove = 'إزالة';
  static const platformCommerceDisableTitle = 'تعطيل هذا العنصر؟';
  static const platformCommerceRemoveTitle = 'إزالة هذا العنصر؟';
  static const platformCommerceConfirmBody =
      'هذا التغيير محلي ومؤقت في بناء التطوير الحالي.';

  // ---------- Commerce, as a control panel rather than a dev fixture ----------
  //
  // The menu used to offer the *state adjective* as the command: an enabled
  // offer's menu item read «معطّل», which is what it is, where «تعطيل» — what
  // the tap does — belongs. A list of nouns is not a list of actions.
  static const platformCommerceEnable = 'تفعيل';
  static const platformCommerceDisable = 'تعطيل';
  static const platformCommerceRemoveOffer = 'حذف العرض';
  static const platformCommerceRemoveCoupon = 'حذف الكوبون';
  static const platformCommerceRowActions = 'إجراءات هذا العنصر';
  static const platformCommerceEnableTitle = 'تفعيل هذا العنصر؟';
  static const platformCommerceEnableChange =
      'سيظهر هذا الخصم لكل من تنطبق عليه شروطه عند عرض الأسعار.';
  static const platformCommerceDisableChange =
      'سيتوقف ظهور هذا الخصم فوراً عند عرض الأسعار.';
  static const platformCommerceRemoveChange =
      'سيُحذف هذا العنصر من هذا الجهاز نهائياً، ولا يمكن التراجع.';

  /// The reassurance slot used to be filled with the page's own description
  /// paragraph, which answers a different question than "what does this not
  /// touch".
  static const platformCommerceUnchanged =
      'لا تتغير الأسعار الأساسية ولا أي عرض أو كوبون آخر، ولا يتأثر أي اشتراك '
      'قائم.';
  static const platformCommerceMonthlyEquivalent = 'ما يعادل شهرياً';
  static const platformCommerceBasePrice = 'السعر الأساسي';
  static const platformCommerceFinalPrice = 'السعر بعد الخصم';
  static const platformCommerceDiscountLabel = 'الخصم';
  static const platformCommercePublicShort = 'كوبون عام';
  static const platformCommerceTargetedShort = 'كوبون مخصص';
  static const platformCommerceAccountShort = 'الحساب';
  static const platformCommerceOfferLead =
      'خصم عام على مدة واحدة، يراه كل عميل عند عرض الأسعار ما دام مفعّلاً.';
  static const platformCommerceCouponLead =
      'خصم يُفعَّل برمز. يمكن أن يكون متاحاً لكل من يملك الرمز أو مخصصاً لحساب '
      'واحد.';
  static const platformCommerceSectionDiscount = 'الخصم';
  static const platformCommerceSectionIdentity = 'الرمز والتخصيص';
  static const platformCommerceSectionAvailability = 'الإتاحة';
  static const platformCommerceAvailabilityOn = 'يظهر للعملاء المؤهلين الآن.';
  static const platformCommerceAvailabilityOff = 'محفوظ ولا يظهر لأي عميل.';
  static const platformCommercePreview = 'المعاينة';
  static const platformCommerceNoOffersHint =
      'أنشئ عرضاً ليظهر الخصم لكل العملاء على المدة التي تختارها.';
  static const platformCommerceNoCouponsHint =
      'أنشئ كوبوناً لمنح خصم برمز، عاماً أو مخصصاً لحساب واحد.';
  static const platformCommerceEligibleNote =
      'العروض والكوبونات متاحة على مدتي شهر واحد وثلاثة أشهر فقط.';

  // ---------- About the app, and support ----------
  //
  // One screen (`/more/about`): what Leader is, which build is installed, and
  // the
  // two approved ways to reach support. Every capability listed below is one
  // the app actually ships — no claim about encryption, uptime or data safety
  // appears here, because nothing in this build could back one.
  // The screen is named after the product, not after «التطبيق»: a user looking
  // for what this is looks for its name. Built from `productNameAr` like every
  // other occurrence — the brand is never a literal (see CLAUDE.md §Brand).
  static const aboutTitle = 'حول $productNameAr';
  static const aboutAppName = productNameAr;
  static const aboutAppFullName = productNameEn;
  static const aboutDescription =
      'إدارة وتنظيم الفرق، المفارز، الورش، الأعضاء، الشفتات، المخزون '
      'والإحصائيات من مكان واحد.';
  static const aboutCapabilities = 'ما يقوم به التطبيق';
  static const aboutCapabilityDetachments = 'إدارة المفارز';
  static const aboutCapabilityShifts = 'تنظيم الشفتات';
  static const aboutCapabilityTeam = 'إدارة الفريق';
  static const aboutCapabilityWorkshops = 'الورش والمشاركون';
  static const aboutCapabilityAttendance = 'الحضور';
  static const aboutCapabilityStorage = 'المخزن';
  static const aboutCapabilityStats = 'الإحصائيات والتقارير';
  static const aboutCapabilitySync = 'المزامنة والعمل دون اتصال';
  // The honest form of "security-oriented": this build really does gate every
  // control on a capability grant. It claims a design property it has, not an
  // assurance about data nobody in this client could make good on.
  static const aboutCapabilityRoles = 'صلاحيات محدّدة حسب الدور';
  static const aboutCapabilityArabic = 'واجهة عربية بالكامل';

  static const aboutAppInfo = 'معلومات التطبيق';
  // `appVersion` above already labels the display version.
  static const aboutBuildNumber = 'رقم البناء';

  /// The one line the product signs itself with.
  ///
  /// It closes the About screen and the Settings hub, and nothing else. It is
  /// a statement of origin, not a link, not a credit list and not a place to
  /// grow a footer — anything that wanted to join it would be a second thing
  /// competing with the only thing worth saying there.
  static const madeInIraq = 'صنع بفخر في العراق';

  static const aboutSupport = 'الدعم';
  static const aboutSupportBody =
      'للاستفسارات والمشكلات، تواصل عبر البريد الإلكتروني أو Telegram.';
  static const aboutSupportEmailLabel = 'البريد الإلكتروني';
  static const aboutSupportTelegramLabel = 'Telegram';
  static const aboutSupportEmailAction = 'مراسلة عبر البريد';
  static const aboutSupportTelegramAction = 'فتح Telegram';
  static const aboutEmailCopied = 'تم نسخ البريد الإلكتروني';
  static const aboutTelegramCopied = 'تم نسخ معرف Telegram';
  // Two failure sentences, because they need two different answers from the
  // user: nothing on the device handles the link (copy it and use another
  // device or app), or the handoff itself failed (try again).
  static const aboutEmailUnsupported =
      'لا يوجد تطبيق بريد على هذا الجهاز. انسخ العنوان واستخدمه في مكان آخر.';
  static const aboutTelegramUnsupported =
      'تعذّر فتح Telegram على هذا الجهاز. انسخ المعرف واستخدمه في تطبيق '
      'Telegram.';
  static const aboutLaunchFailed = 'تعذّر فتح التطبيق. حاول مرة أخرى.';

  // ---------- Startup / session states (Point 3) ----------
  // One sentence per state, and each one has to answer a different question
  // the reader is actually asking. "تعذّر" (something failed) is deliberately
  // absent from the account-lifecycle screens: a withdrawn account is not a
  // failed request, and phrasing it as one invites a retry that cannot work.
  static const startupRestoring = 'جارٍ فتح التطبيق';
  static const startupRestoringSub = 'يتم استعادة الجلسة على هذا الجهاز.';

  static const sessionInvalidTitle = 'بيانات الحساب غير صالحة';
  static const sessionInvalidBody =
      'وصلت بيانات هذا الحساب بشكل غير مكتمل، ولا يمكن فتح التطبيق بها.';
  static const sessionInvalidDetail =
      'سجّل الخروج ثم سجّل الدخول مرة أخرى. إذا تكرر الأمر، تواصل مع الدعم.';
  static const backToLogin = 'العودة إلى تسجيل الدخول';

  static const accessNotAssignedTitle = 'لم يتم تعيين صلاحيات لهذا الحساب بعد';
  static const accessNotAssignedBody =
      'الحساب صالح ومرتبط بالفريق، لكن لم تُمنح له أي صلاحية استخدام حتى الآن.';
  static const accessNotAssignedDetail =
      'اطلب من مدير الفريق تعيين الصلاحيات المناسبة، ثم أعد تسجيل الدخول.';

  static const accountSuspendedTitle = 'تم إيقاف الحساب مؤقتاً';
  static const accountSuspendedBody =
      'الوصول إلى هذا الحساب موقوف مؤقتاً. لا يمكن فتح بيانات الفريق الآن.';
  static const accountSuspendedDetail = 'للاستفسار، تواصل مع الدعم.';

  static const accountRevokedTitle = 'لم يعد لهذا الحساب صلاحية وصول';
  static const accountRevokedBody =
      'تم سحب وصول هذا الحساب إلى التطبيق. هذه ليست مشكلة اتصال أو خطأ مؤقت.';
  static const accountRevokedDetail = 'للاستفسار، تواصل مع الدعم.';

  static const tenantSuspendedTitle = 'وصول الفريق موقوف مؤقتاً';
  static const tenantSuspendedBody =
      'وصول هذا الفريق موقوف حالياً، لذلك لا يمكن فتح التطبيق التشغيلي أو بياناته.';
  static const tenantSuspendedDetail =
      'لا تعني هذه الحالة حذف بيانات الفريق. سجّل الخروج أو تواصل مع الدعم لمعرفة الخطوة التالية.';

  static const tenantDeletionPendingTitle = 'حذف الفريق قيد الانتظار';
  static const tenantDeletionPendingBody =
      'جدولت إدارة المنصة حذف هذا الفريق، وأوقفت الوصول التشغيلي إليه أثناء الانتظار.';
  static const tenantDeletionPendingDetail =
      'لا يمكن فتح التطبيق التشغيلي الآن. سجّل الخروج أو تواصل مع الدعم للاستفسار.';

  static const tenantDeletedTitle = 'لم تعد علاقة الحساب بهذا الفريق متاحة';
  static const tenantDeletedBody =
      'انتهى المورد التشغيلي للفريق، لذلك لا يمكن فتح تطبيق الفريق من هذه الجلسة.';
  static const tenantDeletedDetail =
      'لا يعني ذلك بالضرورة حذف هوية حسابك. سجّل الخروج أو تواصل مع الدعم للاستفسار.';

  static const accountSetupTitle = 'إكمال إعداد الحساب';
  static const accountSetupBody =
      'تم تسجيل الدخول، لكن الإعداد الأول لهذا الحساب لم يكتمل بعد.';
  static const accountSetupDetail =
      'خطوة الإكمال ستتوفر في هذا التطبيق لاحقاً. حتى ذلك الحين تواصل مع '
      'مدير الفريق أو مع الدعم.';

  // Point 17A holding screens — the real steps are Point 17B's.
  static const emailVerificationTitle = 'تأكيد البريد الإلكتروني';
  static const emailVerificationBody =
      'لم يُؤكَّد البريد الإلكتروني لهذا الحساب بعد، لذلك لا يمكن متابعة إعداده.';
  static const emailVerificationDetail =
      'شاشة إدخال رمز التأكيد ستتوفر في هذا التطبيق لاحقاً. سجّل الخروج أو '
      'تواصل مع الدعم.';
  static const teamLinkTitle = 'ربط الحساب بفريق';
  static const teamLinkBody =
      'تم تأكيد هذا الحساب، لكنه غير مرتبط بأي فريق بعد.';
  static const teamLinkDetail =
      'يتم الربط برمز الفريق مع دعوة موجّهة إلى بريدك. سجّل الخروج أو تواصل '
      'مع مدير فريقك أو مع الدعم.';

  // Point 17B — production onboarding screens.
  static const onboardingOfflineNotice = 'يتطلب هذا الإجراء اتصالاً بالإنترنت.';
  static const showPassword = 'إظهار كلمة المرور';
  static const hidePassword = 'إخفاء كلمة المرور';
  static const continueWithGoogle = 'المتابعة باستخدام Google';
  // Point 18B — Google as a first-class alternative on `/login`.
  static const continuingWithGoogle = 'جارٍ المتابعة مع Google…';
  static const authMethodsDivider = 'أو';

  // Point 18B — the verified, unlinked identity's one decision.
  static const onboardingChoiceTitle = 'كيف تريد المتابعة؟';
  static const onboardingChoiceLead =
      'تم تأكيد بريدك، وحسابك غير مرتبط بأي فريق. اختر طريقة واحدة للمتابعة.';
  static const onboardingChoiceTeam = 'الانضمام إلى فريق';
  static const onboardingChoiceTeamSub =
      'انضم إلى فريق قائم في $productNameAr باستخدام رمز الفريق الذي وصلك.';
  static const onboardingChoiceDemo = 'تجربة $productNameAr';
  static const onboardingChoiceDemoSub =
      'استكشف $productNameAr في مساحة تجريبية مؤقتة ومعزولة، من دون الانضمام إلى فريق حقيقي.';
  static const onboardingChoiceBack = 'العودة إلى الخيارات';

  static const signupTitle = 'إنشاء حساب جديد';
  static const signupSub = 'للمسؤولين فقط — الأعضاء لا ينشئون حسابات';
  static const signUpAction = 'إنشاء الحساب';
  static const haveAccountAlready = 'لديّ حساب بالفعل';
  static const passwordAdvisoryHint = '٨ أحرف على الأقل';

  static const verificationCodeLabel = 'رمز التأكيد';
  static const verifyEmailAction = 'تأكيد';
  static const resendCode = 'إعادة الإرسال';
  static const resendingCode = 'جارٍ الإرسال…';
  static const resendCodeCountdown = 'يمكنك إعادة الإرسال بعد ';
  static const useAnotherEmail = 'استخدام بريد آخر';
  static const attemptsRemainingLabel = 'المحاولات المتبقية: ';

  static const signedInAs = 'مسجَّل باسم ';
  static const teamCodeLabel = 'رمز الفريق';
  static const teamCodeHint = 'MTM-XXXX-XXXX';
  static const linkTeamAction = 'ربط';
  static const teamLinkWithdrawnNotice = 'سُحبت الدعوة السابقة.';
  // Point 17C — the invited Simple Admin's way off the Team Code screen.
  static const teamLinkInvitationHint =
      'هل دعاك مدير فريقك؟ لا تحتاج إلى رمز الفريق: اطلب منه إرسال الدعوة '
      'إلى هذا البريد، ثم تحقّق منها هنا.';
  static const checkInvitationAction = 'التحقق من الدعوة';
  static const noInvitationYet = 'لا توجد دعوة صالحة لهذا البريد بعد.';

  static const displayNameLabel = 'الاسم الظاهر';
  static const completeSetupAction = 'إكمال الإعداد';
  static const settingUpNotice = 'جارٍ إنهاء الإعداد…';

  // Onboarding error copy — one sentence per `OnboardingErrorKind`, never a
  // raw backend code (`HANDOFF.md` "POINT 17A" §19).
  static const onboardingInvalidCredentials =
      'البريد الإلكتروني أو كلمة المرور غير صحيحة.';
  static const onboardingPasswordRejected =
      'كلمة المرور هذه غير مقبولة. جرّب كلمة مرور أخرى.';
  static const onboardingInvalidInput = 'تحقق من البيانات المُدخلة.';
  static const onboardingCodeInvalid = 'الرمز غير صحيح.';
  static const onboardingCodeExpired =
      'انتهت صلاحية هذا الرمز. اطلب رمزاً جديداً.';
  static const onboardingVerificationEnded =
      'انتهت محاولات التأكيد. سجّل الدخول أو أنشئ الحساب من جديد.';
  static const onboardingResendThrottled = 'انتظر قليلاً قبل طلب رمز جديد.';
  static const onboardingGoogleRetry =
      'تعذّرت المتابعة عبر Google. حاول مرة أخرى.';
  static const onboardingGoogleUnavailable =
      'المتابعة عبر Google غير متاحة في هذا الإصدار. استخدم البريد وكلمة المرور.';
  static const onboardingMethodLinkRequired =
      'هذا البريد مسجَّل بكلمة مرور. سجّل الدخول بكلمة المرور.';
  static const onboardingUnsupportedMethod =
      'طريقة الدخول هذه غير متاحة حالياً.';
  static const onboardingTeamCodeMalformed = 'صيغة رمز الفريق غير صحيحة.';
  static const onboardingTeamCodeRejected =
      'تعذّر الربط بهذا الرمز. تأكد من الرمز ومن أنك تستخدم البريد الذي '
      'دُعيت به.';
  static const onboardingInvitationExpired = 'اطلب دعوة جديدة.';
  static const onboardingAccountAlreadyLinked =
      'هذا الحساب مرتبط بفريق آخر بالفعل.';
  static const onboardingTenantUnavailable =
      'فريقك غير متاح حالياً. تواصل مع الدعم.';
  static const onboardingSetupUnavailable =
      'تعذّر إكمال الإعداد. حدّث الصفحة وحاول مجدداً.';
  static const onboardingSetupAlreadyCompleted =
      'اكتمل إعداد هذا الحساب من جهاز آخر. سجّل الدخول من جديد.';
  static const onboardingAccountUnavailable =
      'هذا الحساب غير متاح حالياً. تواصل مع الدعم.';
  static const onboardingSessionEnded =
      'انتهت هذه الجلسة. سجّل الدخول من جديد.';
  static const onboardingRateLimited = 'محاولات كثيرة. حاول لاحقاً.';
  static const onboardingTemporaryFailure = 'حدث خطأ مؤقت. حاول مرة أخرى.';
  static const onboardingUnknownError = 'حدث خطأ غير متوقع.';

  // There is deliberately no «بيئة تجريبية» holding screen any more: the trial
  // *is* the application, and what used to be a page saying so is now
  // `DemoTrialBar`, which travels with the user instead of being read once and
  // dismissed. Only the *expired* state still needs a screen of its own,
  // because at that point there is no application left to stand behind a bar.
  static const demoExpiredTitle = 'انتهت مدة التجربة';
  static const demoExpiredBody =
      'انتهت مدة هذه الجلسة التجريبية ولم يعد بالإمكان متابعة استخدامها.';

  static const contactSupport = 'تواصل مع الدعم';

  // ---------- Development state inspector (debug builds only) ----------
  static const devStatesTitle = 'حالات الجلسة (تطوير)';
  static const devStatesBody =
      'أداة تطوير فقط. تفرض حالة جلسة على مُصنِّف بدء التشغيل لمعاينة الشاشة '
      'المقابلة لها. لا تصل هذه الأداة إلى نسخة الإصدار.';
  static const devStatesNormal = 'طبيعي (بدون فرض)';
  static const devStatesAccountSuspended = 'حساب موقوف';
  static const devStatesAccountRevoked = 'حساب مسحوب الوصول';
  static const devStatesPendingSetup = 'إعداد غير مكتمل';
  static const devStatesTenantSuspended = 'فريق موقوف';
  static const devStatesTenantDeleted = 'فريق محذوف';
  static const devStatesDemoActive = 'تجربة نشطة';
  static const devStatesDemoExpired = 'تجربة منتهية';
  static const devStatesOpen = 'معاينة حالات الجلسة';

  // ---------- Organization + Plan (Point 15) ----------
  // Read-only tenant screens. Plan names, statuses and limit keys are closed
  // typed values; every one has its own string here and no wire value is
  // ever rendered.
  static const settingsPlan = 'الخطة والاشتراك';

  static const orgAccessActive = 'وصول المؤسسة نشط';
  static const orgAccessSuspended = 'وصول المؤسسة موقوف';
  static const orgAccessDeletionPending = 'المؤسسة بانتظار الحذف';
  static const orgAccessDeleted = 'المؤسسة محذوفة';
  static const orgAccessUnknown = 'حالة الوصول غير معروفة';

  static const orgSubscriptionTrial = 'فترة تجريبية';
  static const orgSubscriptionActive = 'اشتراك فعّال';
  static const orgSubscriptionGrace = 'فترة سماح';
  static const orgSubscriptionInactive = 'اشتراك غير فعّال';
  static const orgSubscriptionUnknown = 'حالة اشتراك غير معروفة';

  static const orgSectionDetails = 'بيانات المؤسسة';
  static const orgSectionPlan = 'الخطة';
  static const orgRegisteredLabel = 'تاريخ التسجيل';
  static const orgMainAdminLabel = 'المدير الرئيسي';
  static const orgIdLabel = 'الرقم المرجعي للدعم';
  static const orgIdHelp = 'اذكر هذا الرقم عند التواصل مع الدعم.';
  static const orgIdCopy = 'نسخ الرقم المرجعي';
  static const orgIdCopied = 'تم نسخ الرقم المرجعي';
  static const orgPlanRowSubtitle = 'الحدود والاستخدام والوحدات المتاحة';
  static const orgManagedNote =
      'تُدار بيانات المؤسسة وخطتها من منصة $productNameAr، ولا تُعدَّل من هذا التطبيق. '
      'للاستفسار عن أي تغيير تواصل مع الدعم.';
  static const orgAccessAnnouncement = 'حالة وصول المؤسسة: %s';
  static const orgSubscriptionAnnouncement = 'حالة الاشتراك: %s';

  static const orgOfflineNotice = 'لا يوجد اتصال. تعرض الصفحة آخر نسخة محفوظة.';
  static const orgStaleNotice =
      'تعذّر تحديث البيانات. تعرض الصفحة آخر نسخة محفوظة.';
  static const orgLastRead = 'آخر تحديث';
  static const orgRefresh = 'تحديث';
  static const orgOfflineNoCache =
      'لا توجد نسخة محفوظة من بيانات المؤسسة بعد. اتصل بالإنترنت ثم أعد '
      'المحاولة.';
  static const orgUnavailableTitle = 'لا توجد مؤسسة مرتبطة بهذه الجلسة';
  static const orgUnavailableBody =
      'تظهر هذه الصفحة عند تسجيل الدخول بحساب مرتبط بمؤسسة.';

  static const planTitleBasic = 'الخطة الأساسية';
  static const planTitleStandard = 'الخطة القياسية';
  static const planTitleAdvanced = 'الخطة المتقدمة';
  static const planTitleNone = 'لا توجد خطة معيّنة';
  static const planTitleUnknown = 'خطة غير معروفة';
  static const planDescBasic = 'للفرق الصغيرة ذات التشغيل المحدود.';
  static const planDescStandard = 'للفرق النشطة متعددة المفارز.';
  static const planDescAdvanced = 'للجهات الكبيرة ذات النطاق التشغيلي الواسع.';
  static const planDescNone = 'لم تُعيَّن خطة لمؤسستك بعد.';
  static const planDescUnknown =
      'لا يتعرّف هذا الإصدار من التطبيق على خطة مؤسستك. حدّث التطبيق أو '
      'تواصل مع الدعم.';
  static const planCurrentAnnouncement = 'الخطة الحالية: %s';

  static const planSubscriptionLabel = 'حالة الاشتراك';
  static const planTrialEnds = 'تنتهي الفترة التجريبية';
  static const planRenews = 'التجديد الإداري القادم';
  static const planGraceEnds = 'تنتهي فترة السماح';
  static const planGraceNote =
      'فترة السماح مهلة مؤقتة في الاشتراك، ولا تعني حذف البيانات أو إيقاف '
      'المؤسسة تلقائيًا.';
  static const planInactiveNote =
      'الاشتراك غير فعّال حاليًا، وهذا منفصل عن وصول المؤسسة. للاستفسار '
      'تواصل مع الدعم.';
  static const planStatusUnknownNote =
      'لا يتعرّف هذا الإصدار على حالة الاشتراك الحالية. حدّث التطبيق أو '
      'تواصل مع الدعم.';

  static const planLimitsSection = 'الحدود والاستخدام';
  static const planUsageHiddenNote =
      'أرقام الاستخدام على مستوى المؤسسة تظهر لمن يملك صلاحية إدارة بيانات '
      'المؤسسة. تعرض الصفحة لك الحد الأقصى لكل عنصر.';
  static const planNoPlanLimits =
      'لا تُعرض حدود لأن المؤسسة بلا خطة معيّنة حاليًا.';
  static const planLimitsUnsupported =
      'بعض الحدود لا يعرضها هذا الإصدار من التطبيق.';
  static const limitDetachmentGroups = 'مجموعات المفارز';
  static const limitDetachments = 'المفارز';
  static const limitAdmins = 'المشرفون';
  static const limitMembers = 'الأعضاء';
  static const limitWorkshops = 'الورش';
  static const limitStorage = 'مساحة التخزين';
  static const limitWithin = 'ضمن الحد';
  static const limitAt = 'بلغ الحد';
  static const limitOver = 'تجاوز الحد';
  static const limitUnavailable = 'الحد غير متاح';
  static const limitMax = 'الحد الأقصى';
  static const limitAtNote = 'لا يمكن إضافة المزيد ضمن هذا الحد.';
  static const limitOverNote =
      'الاستخدام أعلى من الحد الحالي ولم تُحذف أي بيانات. تتوقف الإضافة حتى '
      'ينخفض الاستخدام عن الحد.';
  static const limitPlanDefault = 'حسب الخطة';
  static const limitCustom = 'حد مخصّص لمؤسستك · حد الخطة %s';
  static const limitUsageSemantics = '%label%، الاستخدام %used% من %limit%';
  static const limitMaxSemantics = '%label%، الحد الأقصى %limit%';

  static const planFeaturesSection = 'الوحدات المتاحة';
  static const featureEnabled = 'مفعّلة';
  static const featureDisabled = 'غير مفعّلة';
  static const featureStateAnnouncement = '%feature%: %state%';
  static const planFeaturesUnavailable =
      'تعذّر تحديد الوحدات المتاحة لهذه الجلسة.';

  static const planExplainSection = 'عن الإتاحة';
  static const planExplainBody =
      'تحدد منصة $productNameAr خطة مؤسستك وحدودها والوحدات المتاحة لها. إتاحة وحدة '
      'للمؤسسة لا تعني أن حسابك يملك صلاحية استخدامها، وإذا لم تجد أداة في '
      'حسابك فقد يعود ذلك إلى صلاحياتك لا إلى الخطة.';

  // ---------- Phase 3A — attention, today, and readable statistics ----------

  /// How consequential a raised condition is, **in a word**.
  ///
  /// A tint and a glyph are the only severity carriers the dashboard had, and
  /// colour is not a carrier: it is invisible to a colour-blind reader, it is
  /// gone in a screenshot printed in grey, and it is never announced. These
  /// three words are the carrier; the colour agrees with them.
  static const severityUrgent = 'عاجل';
  static const severityImportant = 'مهم';
  static const severityInfo = 'للعلم';

  /// The heading over a list that is information rather than a decision —
  /// queued work that will go on its own. «يحتاج قرارك» would be a small lie
  /// told about it.
  static const dashboardForInfo = 'للعلم';

  static const dashboardTodaySection = 'اليوم';
  static const dashboardGlanceSection = 'لمحة عن المفرزة';
  static const dashboardShortcutsSection = 'اختصارات المفرزة';

  /// The calm state. One sentence, in the card that reports the day — not a
  /// second card that says the same absence a different way.
  static const dashboardQuietTitle = 'لا شيء يحتاج قرارك الآن';
  static const dashboardQuietBody =
      'راجعنا الشفتات والمخزن والمزامنة. سنعرض هنا أي أمر يستجدّ.';

  /// The switcher, as a control rather than a pair of chevrons.
  static const dashboardSwitchAction = 'تبديل';
  static const dashboardOneDetachment = 'مفرزة واحدة';
  static const dashboardAmongDetachments = 'من %d مفرزات';

  /// One sentence for one absence. The old screen drew two cards —
  /// «لا شفتات اليوم في هذه المفرزة» and «لا شفت قادم مجدول» — which on a
  /// quiet day is the same fact told twice in two boxes.
  static const dashboardNoShiftsAtAll = 'لا شفتات اليوم، ولا شفت قادم مجدول.';

  static const dashboardRosterNone = 'لا أعضاء';
  static const dashboardRosterOne = 'عضو واحد';
  static const dashboardRosterMany = '%d أعضاء';
  static const dashboardShiftsTodayNone = 'لا شفتات اليوم';
  static const dashboardShiftsTodayOne = 'شفت واحد اليوم';
  static const dashboardShiftsTodayMany = '%d شفتات اليوم';

  /// Spoken for the whole attention row: the severity first, because that is
  /// what decides whether the rest is read now.
  static const dashboardAlertSemantics = '%severity%: %title%. %body%';

  // ---- Statistics: scale, period and the text a chart cannot carry ----

  /// «المقياس ٠–١٠٠» — printed under every series, because a bar whose height
  /// is a fraction of an unstated maximum says nothing. Before this, a
  /// coverage series of ٤٠/٤٢/٤١٪ drew identically to ٩٠/٩٥/٩٢٪.
  /// What a metric tile announces while its provider is still resolving.
  static const statsLoadingValue = 'جارٍ التحميل';

  static const statsScale = 'المقياس';
  static const statsLatest = 'الأحدث';
  static const statsUnit = 'وحدة';

  /// Change against the day before, in words. Never an arrow alone, and never
  /// a colour alone.
  static const statsChangeUp = 'ارتفاع %s عن اليوم السابق';
  static const statsChangeDown = 'انخفاض %s عن اليوم السابق';
  static const statsChangeNone = 'بلا تغيير عن اليوم السابق';
  static const statsChangeUnknown = 'لا مقارنة متاحة';

  /// The whole series as one sentence, for a reader who gets no chart at all.
  static const statsSeriesSemantics =
      '%title%، %period%. %latest%. الأعلى %high%، المتوسط %avg%. %scale%.';

  /// A series that cannot be drawn honestly — one point, or none.
  static const statsSeriesTooShort = 'لا تكفي البيانات لرسم هذه الفترة.';

  /// A series that is genuinely all zeros. Drawing seven bars at 2 % of the
  /// height to say "nothing happened" is a chart pretending to be data.
  static const statsSeriesAllZero = 'لا نشاط مسجّل في هذه الفترة.';

  static const statsCoverageHint = 'تغطية الشفتات المجدولة في كل يوم';
  static const statsStockHint = 'الوحدات المصروفة من المخزن في كل يوم';

  // ---------- Beginner guidance ----------
  static const stepOne = 'الخطوة ١';
  static const stepTwo = 'الخطوة ٢';
  static const stepThree = 'الخطوة ٣';
  static const gotIt = 'فهمت';
}
