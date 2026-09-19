class Topic {
  const Topic({required this.id, required this.name, this.parentId});

  final int id;
  final String name;
  final int? parentId;
}
