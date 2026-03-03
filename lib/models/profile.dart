class Profile {
  final String id;
  final String? fullName;
  final String? firstName;
  final String? lastName;
  final String? middleName;
  final DateTime? birthDate;
  final String? nickname;
  final int? age;
  final String? gender;
  final double? weight;
  final String? goal;
  final String? level;
  final String? avatarUrl;
  final String? city;
  final String? phone;
  final String? email;
  final DateTime createdAt;
  final DateTime updatedAt;

  Profile({
    required this.id,
    this.fullName,
    this.firstName,
    this.lastName,
    this.middleName,
    this.birthDate,
    this.nickname,
    this.age,
    this.gender,
    this.weight,
    this.goal,
    this.level,
    this.avatarUrl,
    this.city,
    this.phone,
    this.email,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      fullName: json['full_name'] as String?,
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      middleName: json['middle_name'] as String?,
      birthDate: json['birth_date'] != null
          ? DateTime.tryParse(json['birth_date'] as String)
          : null,
      nickname: json['nickname'] as String?,
      age: json['age'] as int?,
      gender: json['gender'] as String?,
      weight: (json['weight'] as num?)?.toDouble(),
      goal: json['goal'] as String?,
      level: json['level'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      city: json['city'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'full_name': fullName,
        'first_name': firstName,
        'last_name': lastName,
        'middle_name': middleName,
        'birth_date': birthDate?.toIso8601String().split('T')[0],
        'nickname': nickname,
        'age': age,
        'gender': gender,
        'weight': weight,
        'goal': goal,
        'level': level,
        'avatar_url': avatarUrl,
        'city': city,
        'phone': phone,
        'email': email,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  Profile copyWith({
    String? fullName,
    String? firstName,
    String? lastName,
    String? middleName,
    DateTime? birthDate,
    String? nickname,
    int? age,
    String? gender,
    double? weight,
    String? goal,
    String? level,
    String? avatarUrl,
    String? city,
    String? phone,
    String? email,
  }) {
    return Profile(
      id: id,
      fullName: fullName ?? this.fullName,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      middleName: middleName ?? this.middleName,
      birthDate: birthDate ?? this.birthDate,
      nickname: nickname ?? this.nickname,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      weight: weight ?? this.weight,
      goal: goal ?? this.goal,
      level: level ?? this.level,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      city: city ?? this.city,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
