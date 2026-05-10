class User {
  final String id;
  final String email;
  final String role;
  final bool isLocked;

  User({
    required this.id,
    required this.email,
    required this.role,
    this.isLocked = false,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? 'user',
      isLocked: json['isLocked'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'role': role,
      'isLocked': isLocked,
    };
  }
}
