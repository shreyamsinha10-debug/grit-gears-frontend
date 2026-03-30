// ---------------------------------------------------------------------------
// GymProfile, GymBatch, GymPlan – strongly-typed models for /gym/profile API.
// ---------------------------------------------------------------------------

/// Single batch (Morning, Evening, etc.) from gym profile.
class GymBatch {
  final String? id;
  final String name;
  final String? description;
  final String? startTime;
  final String? endTime;

  const GymBatch({
    this.id,
    required this.name,
    this.description,
    this.startTime,
    this.endTime,
  });

  factory GymBatch.fromJson(Map<String, dynamic> json) {
    return GymBatch(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      startTime: json['start_time'] as String?,
      endTime: json['end_time'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'name': name};
    if (id != null) m['id'] = id;
    if (description != null && description!.isNotEmpty) m['description'] = description;
    if (startTime != null && startTime!.isNotEmpty) m['start_time'] = startTime;
    if (endTime != null && endTime!.isNotEmpty) m['end_time'] = endTime;
    return m;
  }
}

/// Membership plan from gym profile.
class GymPlan {
  final String? id;
  final String name;
  final String? description;
  final int price;
  final String durationType;
  final bool isActive;
  final int? registrationFee;
  final bool waiveRegistrationFee;

  const GymPlan({
    this.id,
    required this.name,
    this.description,
    required this.price,
    required this.durationType,
    this.isActive = true,
    this.registrationFee,
    this.waiveRegistrationFee = false,
  });

  factory GymPlan.fromJson(Map<String, dynamic> json) {
    return GymPlan(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      price: (json['price'] as num?)?.toInt() ?? 0,
      durationType: json['duration_type'] as String? ?? '1m',
      isActive: json['is_active'] != false,
      registrationFee: (json['registration_fee'] as num?)?.toInt(),
      waiveRegistrationFee: json['waive_registration_fee'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'description': description ?? '',
      'price': price,
      'duration_type': durationType,
      'is_active': isActive,
      'registration_fee': registrationFee,
      'waive_registration_fee': waiveRegistrationFee,
    };
  }
}

/// Gym profile from GET /gym/profile.
class GymProfile {
  final String? id;
  final String name;
  final String? logoBase64;
  final String? invoiceName;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? state;
  final String? pinCode;
  final String? phone;
  final String? termsAndConditions;
  final List<GymBatch> batches;
  final List<GymPlan> plans;

  const GymProfile({
    this.id,
    required this.name,
    this.logoBase64,
    this.invoiceName,
    this.addressLine1,
    this.addressLine2,
    this.city,
    this.state,
    this.pinCode,
    this.phone,
    this.termsAndConditions,
    this.batches = const [],
    this.plans = const [],
  });

  factory GymProfile.fromJson(Map<String, dynamic> json) {
    final batchesList = json['batches'] as List<dynamic>? ?? [];
    final plansList = json['plans'] as List<dynamic>? ?? [];
    return GymProfile(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      logoBase64: json['logo_base64'] as String?,
      invoiceName: json['invoice_name'] as String?,
      addressLine1: json['address_line1'] as String?,
      addressLine2: json['address_line2'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      pinCode: json['pin_code'] as String?,
      phone: json['phone'] as String?,
      termsAndConditions: json['terms_and_conditions'] as String?,
      batches: batchesList.map((e) => GymBatch.fromJson(e as Map<String, dynamic>)).toList(),
      plans: plansList.map((e) => GymPlan.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'invoice_name': invoiceName,
      'city': city,
      'state': state,
      'pin_code': pinCode,
      'phone': phone,
      'terms_and_conditions': termsAndConditions,
      'batches': batches.map((e) => e.toJson()).toList(),
      'plans': plans.map((e) => e.toJson()).toList(),
    };
  }
}
