class SearchHistory {
  const SearchHistory({
    this.items = const <String>[],
    this.ready = false,
    this.readFailed = false,
  });

  final List<String> items;
  final bool ready;
  final bool readFailed;
}
