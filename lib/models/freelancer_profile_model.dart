class FreelancerProfileModel {
  final String uid;
  final String nationalId;
  final double rating;

  final String firstName;
  final String lastName;

  String get fullName {
    // نكبّر أول حرف من كل كلمة عند العرض (حتى لو محفوظ بقاعدة
    // البيانات بأحرف صغيرة من تسجيلات قديمة)، عشان يبين متناسق بكل
    // مكان يظهر فيه الاسم بالتطبيق.
    String cap(String s) => s.isEmpty
        ? s
        : s
              .split(' ')
              .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
              .join(' ');
    final both = ('${cap(firstName)} ${cap(lastName)}').trim();
    return both.isEmpty ? "Freelancer" : both;
  }

  final String email;
  final String bio;
  final String? photoUrl;
  final bool isBlocked;
  final String? serviceField;
  final String? serviceType;
  final String? workingMode;

  final String? iban;

  final List<ExperienceModel> experiences;
  final List<String> portfolioUrls;

  const FreelancerProfileModel({
    required this.uid,
    required this.nationalId,
    required this.rating,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.bio,
    required this.photoUrl,
    required this.isBlocked,
    required this.serviceField,
    required this.serviceType,
    required this.workingMode,
    required this.iban,
    required this.experiences,
    required this.portfolioUrls,
  });

  FreelancerProfileModel copyWith({
    String? firstName,
    String? lastName,
    String? email,
    String? bio,
    String? photoUrl,
    bool clearPhotoUrl = false,
    bool? isBlocked,
    String? serviceField,
    String? serviceType,
    bool clearServiceType = false,
    String? workingMode,
    bool clearWorkingMode = false,
    String? iban,
    List<ExperienceModel>? experiences,
    List<String>? portfolioUrls,
  }) {
    return FreelancerProfileModel(
      uid: uid,
      nationalId: nationalId,
      rating: rating,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      bio: bio ?? this.bio,
      photoUrl: clearPhotoUrl ? null : (photoUrl ?? this.photoUrl),
      isBlocked: isBlocked ?? this.isBlocked,
      serviceField: serviceField ?? this.serviceField,
      serviceType: clearServiceType ? null : (serviceType ?? this.serviceType),
      workingMode: clearWorkingMode ? null : (workingMode ?? this.workingMode),
      iban: iban ?? this.iban,
      experiences: experiences ?? this.experiences,
      portfolioUrls: portfolioUrls ?? this.portfolioUrls,
    );
  }

  factory FreelancerProfileModel.fromFirestore({
    required String uid,
    required Map<String, dynamic>? data,
    required double rating,
  }) {
    data ??= {};

    final first = (data['firstName'] ?? '').toString().trim();
    final last = (data['lastName'] ?? '').toString().trim();

    final portRaw = data['portfolioUrls'];
    final ports = (portRaw is List)
        ? portRaw.map((e) => e.toString()).toList()
        : <String>[];

    return FreelancerProfileModel(
      uid: uid,
      nationalId: (data['nationalId'] ?? '').toString(),
      rating: rating,
      firstName: first.isEmpty ? "Freelancer" : first,
      lastName: last,
      email: (data['email'] ?? '').toString(),
      bio: (data['bio'] ?? '').toString(),
      photoUrl: data['profile']?.toString(),
      isBlocked: data['isBlocked'] == true,
      serviceField: data['serviceField']?.toString(),
      serviceType: data['serviceType']?.toString(),
      workingMode: data['workingMode']?.toString(),
      iban: data['iban']?.toString(),
      experiences: (data['experiences'] is List)
    ? (data['experiences'] as List)
        .map((e) => ExperienceModel.fromMap(Map<String, dynamic>.from(e)))
        .toList()
    : <ExperienceModel>[],
      portfolioUrls: ports,
    );
  }
}

class ExperienceModel {
  final String field;
  final String org;
  final String period;

  const ExperienceModel({
    required this.field,
    required this.org,
    required this.period,
  });

  Map<String, dynamic> toMap() {
    return {'field': field, 'org': org, 'period': period};
  }

  factory ExperienceModel.fromMap(Map<String, dynamic> map) {
  return ExperienceModel(
    field: (map['field'] ?? '').toString(),
    org: (map['org'] ?? '').toString(),
    period: (map['period'] ?? '').toString(),
  );
}
}


class FreelancerReviewModel {
  final String reviewerName;
  final String reviewerProfileUrl;
  final int rating;
  final String text;

  const FreelancerReviewModel({
    required this.reviewerName,
    required this.reviewerProfileUrl,
    required this.rating,
    required this.text,
  });

  static FreelancerReviewModel fromFirestore(Map<String, dynamic> data) {
    final r = data['rating'];
    final ratingInt = (r is int) ? r : (r is num ? r.toInt() : 0);

    return FreelancerReviewModel(
      reviewerName: (data['reviewerName'] ?? 'User').toString(),
      reviewerProfileUrl: ((data['reviewerProfileUrl'] ??
                  data['senderProfileUrl'] ??
                  data['senderProfileImage']) ??
              '')
          .toString(),
      rating: ratingInt.clamp(0, 5),
      text: (data['text'] ?? '').toString(),
    );
  }
}
