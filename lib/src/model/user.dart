class User {
  const User({required this.id, required this.username, this.nickname});

  final int id;
  final String username;
  final String? nickname;

  String get displayName =>
      (nickname != null && nickname!.isNotEmpty) ? nickname! : username;
}
