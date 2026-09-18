class PageResult<T> {
  const PageResult({required this.items, required this.nextPage});

  final List<T> items;
  final int? nextPage;
}
