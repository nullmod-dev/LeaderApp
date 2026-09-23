import 'package:flutter/foundation.dart';

import '../../../core/access/capability.dart';
import '../../tenant_feature/domain/tenant_feature_models.dart';

enum SimpleAdminAccountStatus { active, suspended }

enum SimpleAdminInvitationStatus { pending, cancelled, accepted, expired }

@immutable
class SimpleAdminAccount {
  const SimpleAdminAccount({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.email,
    required this.capabilities,
    required this.status,
    required this.revision,
  });

  final String id;
  final String tenantId;
  final String name;
  final String email;
  final Capabilities capabilities;
  final SimpleAdminAccountStatus status;
  final int revision;

  SimpleAdminAccount copyWith({Capabilities? capabilities, int? revision}) =>
      SimpleAdminAccount(
        id: id,
        tenantId: tenantId,
        name: name,
        email: email,
        capabilities: capabilities ?? this.capabilities,
        status: status,
        revision: revision ?? this.revision,
      );
}

@immutable
class SimpleAdminInvitation {
  const SimpleAdminInvitation({
    required this.id,
    required this.tenantId,
    required this.email,
    required this.suggestedName,
    required this.capabilities,
    required this.createdAt,
    required this.expiresAt,
    required this.status,
  });

  final String id;
  final String tenantId;
  final String email;
  final String suggestedName;
  final Capabilities capabilities;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final SimpleAdminInvitationStatus status;

  SimpleAdminInvitationStatus effectiveStatus(DateTime now) =>
      status == SimpleAdminInvitationStatus.pending &&
              expiresAt != null &&
              !now.toUtc().isBefore(expiresAt!.toUtc())
          ? SimpleAdminInvitationStatus.expired
          : status;

  SimpleAdminInvitation copyWith({SimpleAdminInvitationStatus? status}) =>
      SimpleAdminInvitation(
        id: id,
        tenantId: tenantId,
        email: email,
        suggestedName: suggestedName,
        capabilities: capabilities,
        createdAt: createdAt,
        expiresAt: expiresAt,
        status: status ?? this.status,
      );
}

@immutable
class SimpleAdminManagementSnapshot {
  const SimpleAdminManagementSnapshot({
    required this.tenantId,
    required this.accounts,
    required this.invitations,
    required this.revision,
    required this.readAt,
  });

  final String tenantId;
  final List<SimpleAdminAccount> accounts;
  final List<SimpleAdminInvitation> invitations;
  final int revision;
  final DateTime readAt;
}

@immutable
class InviteSimpleAdminCommand {
  const InviteSimpleAdminCommand({
    required this.email,
    required this.suggestedName,
    required this.capabilityKeys,
    required this.expectedRevision,
    required this.idempotencyKey,
  });

  final String email;
  final String suggestedName;
  final Set<String> capabilityKeys;
  final int expectedRevision;
  final String idempotencyKey;
}

@immutable
class CancelSimpleAdminInvitationCommand {
  const CancelSimpleAdminInvitationCommand({
    required this.invitationId,
    required this.expectedRevision,
  });

  final String invitationId;
  final int expectedRevision;
}

@immutable
class UpdateSimpleAdminCapabilitiesCommand {
  const UpdateSimpleAdminCapabilitiesCommand({
    required this.accountId,
    required this.capabilityKeys,
    required this.expectedRevision,
  });

  final String accountId;
  final Set<String> capabilityKeys;
  final int expectedRevision;
}

/// The safe subset offered by this UI. Every entry is an existing key; the
/// selector invents no permission and never offers tenant ownership,
/// lifecycle, organization editing or recursive admin-management authority.
const simpleAdminAssignableKeys = <String>{
  Cap.detachmentView,
  Cap.memberView,
  Cap.memberContactView,
  Cap.memberInvite,
  Cap.memberEdit,
  Cap.memberRoleAssign,
  Cap.shiftManage,
  Cap.shiftAssign,
  Cap.shiftPublish,
  Cap.shiftAttendanceRecord,
  Cap.shiftOccurrenceManage,
  Cap.inventoryAdjust,
  Cap.inventoryItemManage,
  Cap.workshopCreate,
  Cap.workshopEdit,
  Cap.workshopPeopleManage,
  Cap.workshopAttendanceRecord,
  Cap.workshopSectionManage,
  Cap.statsView,
  Cap.announcementPublish,
};

/// Point 18B — how the selector groups the catalogue, in display order. A
/// presentation grouping only: it grants nothing and is never sent.
enum SimpleAdminCapabilityGroup { team, shifts, inventory, workshops, insights }

@immutable
class SimpleAdminCapabilityDefinition {
  const SimpleAdminCapabilityDefinition({
    required this.key,
    required this.label,
    required this.description,
    required this.group,
    this.feature,
  });

  final String key;
  final String label;
  final String description;
  final SimpleAdminCapabilityGroup group;
  final TenantFeatureKey? feature;
}

const simpleAdminCapabilityCatalogue = <SimpleAdminCapabilityDefinition>[
  SimpleAdminCapabilityDefinition(
      key: Cap.detachmentView,
      group: SimpleAdminCapabilityGroup.team,
      label: 'عرض المفرزات',
      description: 'عرض المفرزات الداخلة في نطاق الحساب.'),
  SimpleAdminCapabilityDefinition(
      key: Cap.memberView,
      group: SimpleAdminCapabilityGroup.team,
      label: 'عرض الأعضاء',
      description: 'عرض قوائم الأعضاء داخل المفرزات.'),
  SimpleAdminCapabilityDefinition(
      key: Cap.memberContactView,
      group: SimpleAdminCapabilityGroup.team,
      label: 'عرض بيانات التواصل',
      description: 'عرض أرقام التواصل والبيانات الشخصية.'),
  SimpleAdminCapabilityDefinition(
      key: Cap.memberInvite,
      group: SimpleAdminCapabilityGroup.team,
      label: 'إضافة أعضاء',
      description: 'إضافة أعضاء جدد إلى قوائم الفريق.'),
  SimpleAdminCapabilityDefinition(
      key: Cap.memberEdit,
      group: SimpleAdminCapabilityGroup.team,
      label: 'تعديل الأعضاء',
      description: 'تحديث بيانات أعضاء الفريق.'),
  SimpleAdminCapabilityDefinition(
      key: Cap.memberRoleAssign,
      group: SimpleAdminCapabilityGroup.team,
      label: 'تعيين أدوار الفريق',
      description: 'تغيير الدور التشغيلي للعضو.'),
  SimpleAdminCapabilityDefinition(
      key: Cap.shiftManage,
      group: SimpleAdminCapabilityGroup.shifts,
      label: 'إدارة الشفتات',
      description: 'إنشاء الشفتات وتعديل جداولها.'),
  SimpleAdminCapabilityDefinition(
      key: Cap.shiftAssign,
      group: SimpleAdminCapabilityGroup.shifts,
      label: 'تعيين الشفتات',
      description: 'إسناد أعضاء الفريق إلى الشفتات.'),
  SimpleAdminCapabilityDefinition(
      key: Cap.shiftPublish,
      group: SimpleAdminCapabilityGroup.shifts,
      label: 'نشر الجداول',
      description: 'نشر جدول الشفتات عندما يدعم التدفق ذلك.'),
  SimpleAdminCapabilityDefinition(
      key: Cap.shiftAttendanceRecord,
      group: SimpleAdminCapabilityGroup.shifts,
      label: 'تسجيل الحضور',
      description: 'تسجيل الحضور ضمن نافذة الشفت.'),
  SimpleAdminCapabilityDefinition(
      key: Cap.shiftOccurrenceManage,
      group: SimpleAdminCapabilityGroup.shifts,
      label: 'إدارة تكرار الشفت',
      description: 'إدارة مرات الشفت وقوالبه.'),
  SimpleAdminCapabilityDefinition(
      key: Cap.inventoryAdjust,
      group: SimpleAdminCapabilityGroup.inventory,
      label: 'تعديل كميات المخزون',
      description: 'تسجيل الإدخال والإخراج اليومي.',
      feature: TenantFeatureKey.inventory),
  SimpleAdminCapabilityDefinition(
      key: Cap.inventoryItemManage,
      group: SimpleAdminCapabilityGroup.inventory,
      label: 'إدارة أصناف المخزون',
      description: 'إنشاء الأصناف وتعديل إعداداتها.',
      feature: TenantFeatureKey.inventory),
  SimpleAdminCapabilityDefinition(
      key: Cap.workshopCreate,
      group: SimpleAdminCapabilityGroup.workshops,
      label: 'إنشاء الورش',
      description: 'إنشاء ورشة جديدة.',
      feature: TenantFeatureKey.workshops),
  SimpleAdminCapabilityDefinition(
      key: Cap.workshopEdit,
      group: SimpleAdminCapabilityGroup.workshops,
      label: 'تعديل الورش',
      description: 'تحديث بيانات الورش.',
      feature: TenantFeatureKey.workshops),
  SimpleAdminCapabilityDefinition(
      key: Cap.workshopPeopleManage,
      group: SimpleAdminCapabilityGroup.workshops,
      label: 'إدارة المشاركين',
      description: 'إضافة المشاركين وفريق التنظيم.',
      feature: TenantFeatureKey.workshops),
  SimpleAdminCapabilityDefinition(
      key: Cap.workshopAttendanceRecord,
      group: SimpleAdminCapabilityGroup.workshops,
      label: 'حضور الورش',
      description: 'تسجيل حضور المشاركين في الورش.',
      feature: TenantFeatureKey.workshops),
  SimpleAdminCapabilityDefinition(
      key: Cap.workshopSectionManage,
      group: SimpleAdminCapabilityGroup.workshops,
      label: 'أقسام الورش',
      description: 'إدارة أقسام فريق الورشة.',
      feature: TenantFeatureKey.workshops),
  SimpleAdminCapabilityDefinition(
      key: Cap.statsView,
      group: SimpleAdminCapabilityGroup.insights,
      label: 'عرض الإحصاءات والتقارير',
      description: 'عرض الإحصاءات وإنشاء التقارير.',
      feature: TenantFeatureKey.statisticsReports),
  SimpleAdminCapabilityDefinition(
      key: Cap.announcementPublish,
      group: SimpleAdminCapabilityGroup.insights,
      label: 'نشر الإعلانات',
      description: 'إنشاء الإعلانات وسحبها.',
      feature: TenantFeatureKey.announcements),
];
