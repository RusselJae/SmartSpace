class ProfileExtras {
  const ProfileExtras({
    required this.username,
    required this.gender,
    this.dateOfBirth,
    this.avatarPath,
  });

  final String username;
  final Gender gender;
  final DateTime? dateOfBirth;
  final String? avatarPath;

  ProfileExtras copyWith({
    String? username,
    Gender? gender,
    DateTime? dateOfBirth,
    String? avatarPath,
  }) {
    return ProfileExtras(
      username: username ?? this.username,
      gender: gender ?? this.gender,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      avatarPath: avatarPath ?? this.avatarPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'gender': gender.name,
      'dateOfBirth': dateOfBirth?.toIso8601String(),
      'avatarPath': avatarPath,
    };
  }

  factory ProfileExtras.fromJson(Map<String, dynamic> json) {
    return ProfileExtras(
      username: json['username'] as String? ?? '',
      gender: Gender.values.firstWhere(
        (g) => g.name == json['gender'],
        orElse: () => Gender.other,
      ),
      dateOfBirth:
          json['dateOfBirth'] != null ? DateTime.tryParse(json['dateOfBirth'] as String) : null,
      avatarPath: json['avatarPath'] as String?,
    );
  }
}

enum Gender { male, female, other }

