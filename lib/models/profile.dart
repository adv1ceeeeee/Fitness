class Profile {
  final String id;
  final String? fullName;
  final int? age;
  final String? gender;
  final double? weight;
  final String? goal;
  final String? level;
  final String? avatarUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  Profile({
    required this.id,
    this.fullName,
    this.age,
    this.gender,
    this.weight,
    this.goal,
    this.level,
    this.avatarUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      fullName: json['full_name'] as String?,
      age: json['age'] as int?,
      gender: json['gender'] as String?,
      weight: (json['weight'] as num?)?.toDouble(),
      goal: json['goal'] as String?,
      level: json['level'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'full_name': fullName,
        'age': age,
        'gender': gender,
        'weight': weight,
        'goal': goal,
        'level': level,
        'avatar_url': avatarUrl,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  Profile copyWith({
    String? fullName,
    int? age,
    String? gender,
    double? weight,
    String? goal,
    String? level,
    String? avatarUrl,
  }) {
    return Profile(
      id: id,
      fullName: fullName ?? this.fullName,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      weight: weight ?? this.weight,
      goal: goal ?? this.goal,
      level: level ?? this.level,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
