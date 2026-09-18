class WanPageDto<T> {
  const WanPageDto({
    required this.datas,
    required this.curPage,
    required this.over,
    required this.total,
  });

  factory WanPageDto.fromJson(
    Object? value,
    T Function(Map<String, dynamic> json) decodeItem,
  ) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Page data must be an object.');
    }
    final Object? datas = value['datas'];
    final Object? curPage = value['curPage'];
    final Object? over = value['over'];
    final Object? total = value['total'];
    if (datas is! List || curPage is! int || over is! bool || total is! int) {
      throw const FormatException('Invalid page fields.');
    }
    return WanPageDto<T>(
      datas: datas
          .map<T>((Object? item) {
            if (item is! Map<String, dynamic>) {
              throw const FormatException('Page item must be an object.');
            }
            return decodeItem(item);
          })
          .toList(growable: false),
      curPage: curPage,
      over: over,
      total: total,
    );
  }

  final List<T> datas;
  final int curPage;
  final bool over;
  final int total;
}
