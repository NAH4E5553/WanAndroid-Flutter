import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repository/contract/album_repository.dart';
import '../../../model/album_models.dart';

final class AlbumUiState {
  AlbumUiState({
    this.permission = AlbumPermission.unknown,
    this.loading = true,
    this.expanded = false,
    this.busy = false,
    this.cloudConfirmation = false,
    this.message,
    this.selectedId = 'all',
    this.snapshot,
    this.limit = 80,
    this.generation = 0,
    this.result,
  });
  final AlbumPermission permission;
  final bool loading, expanded, busy, cloudConfirmation;
  final String? message;
  final String selectedId;
  final AlbumSnapshot? snapshot;
  final int limit, generation;
  final AlbumResult? result;
  bool get canBrowse =>
      permission == AlbumPermission.full ||
      permission == AlbumPermission.limited;
  List<AlbumGroup> get groups => snapshot?.groups ?? const [AlbumGroup.all];
  AlbumGroup get group => groups.firstWhere(
    (a) => a.id == selectedId,
    orElse: () => AlbumGroup.all,
  );
  List<AlbumAsset> get assets => snapshot?.inGroup(selectedId) ?? const [];
}

final class AlbumPickerViewModel extends ChangeNotifier {
  AlbumPickerViewModel(
    this._repository, {
    this.budget = const AlbumBudget(),
    this.options = const AlbumPickerOptions(),
    this.cameraEnabled = true,
    this.systemPickerEnabled = true,
    AlbumCancellation? cancellation,
  }) {
    _limit = options.pageSize;
    _subscription = _repository.changes.listen(
      (_) => unawaited(refresh()),
      onError: (Object _) {
        if (_alive) {
          _message = '暂时无法监听照片变化，请刷新';
          _emit();
        }
      },
    );
    if (cancellation != null) {
      unawaited(
        cancellation.whenCancelled.then(
          (_) => finish(AlbumResultKind.cancelled),
        ),
      );
    }
    unawaited(refresh());
  }
  final AlbumRepository _repository;
  final AlbumBudget budget;
  final AlbumPickerOptions options;
  String text(String value) => options.text(value);
  final bool cameraEnabled, systemPickerEnabled;
  late final StreamSubscription<void> _subscription;
  bool _alive = true, _loading = true, _expanded = false, _busy = false;
  bool _requesting = false, _cloud = false, _foreground = true;
  int _generation = 0, _selection = 0, _limit = 80;
  String _selected = 'all';
  String? _message;
  AlbumPermission _permission = AlbumPermission.unknown;
  AlbumSnapshot? _snapshot;
  AlbumAsset? _pending;
  AlbumCancellation? _operation;
  AlbumResult? _result;
  bool _taken = false;
  final Map<String, (double, String?, double)> _positions = {};
  void rememberPosition(double offset, String? anchor, double withinRow) {
    _positions[_selected] = (offset, anchor, withinRow);
  }

  double restoreOffset(double rowExtent) {
    final position = _positions[_selected];
    if (position == null) return 0;
    final index = state.assets.indexWhere((a) => a.id == position.$2);
    if (index < 0) return position.$1;
    final camera = cameraEnabled && _selected == 'all' ? 1 : 0;
    return ((index + camera) ~/ 4) * rowExtent + position.$3;
  }

  void _restoreLimit() {
    final position = _positions[_selected];
    final index = state.assets.indexWhere((a) => a.id == position?.$2);
    if (index >= _limit) {
      _limit = ((index ~/ options.pageSize) + 1) * options.pageSize;
    }
  }

  AlbumUiState get state => AlbumUiState(
    permission: _permission,
    loading: _loading,
    expanded: _expanded,
    busy: _busy || _cloud,
    cloudConfirmation: _cloud,
    message: _message,
    selectedId: _selected,
    snapshot: _snapshot,
    limit: _limit,
    generation: _generation,
    result: _result,
  );
  void _emit() {
    if (_alive) notifyListeners();
  }

  Future<void> refresh() async {
    if (!_alive || _result != null) return;
    cancelPreparation(notify: false);
    final generation = ++_generation;
    _repository.clearImages();
    _snapshot = null;
    _loading = true;
    _expanded = false;
    _emit();
    try {
      final permission = await _repository.permission();
      if (!_valid(generation)) return;
      _permission = permission;
      if (permission == AlbumPermission.full ||
          permission == AlbumPermission.limited) {
        final snapshot = await _repository.snapshot();
        if (!_valid(generation)) return;
        _snapshot = snapshot;
        if (!snapshot.groups.any((g) => g.id == _selected)) {
          _selected = 'all';
          _message = '相册已变化，已显示所有图片';
        }
      }
    } catch (_) {
      if (_valid(generation)) _message = '暂时无法读取照片，请重试';
    }
    if (_valid(generation)) {
      _restoreLimit();
      _loading = false;
      _emit();
    }
  }

  bool _valid(int generation) =>
      _alive && _result == null && generation == _generation;
  Future<void> authorize() async {
    if (_requesting || _busy || _result != null) return;
    _requesting = true;
    _loading = true;
    _emit();
    try {
      await _repository.permission(request: true);
    } catch (_) {
      _message = '无法申请照片访问，请使用系统相册选择';
    } finally {
      _requesting = false;
      await refresh();
    }
  }

  Future<void> manage() async {
    if (_busy || _requesting) return;
    _requesting = true;
    try {
      await _repository.manageAccess();
    } catch (_) {
      _message = '无法管理照片访问，可前往系统设置调整';
    } finally {
      _requesting = false;
      await refresh();
    }
  }

  Future<void> settings() async {
    try {
      await _repository.openSettings();
    } catch (_) {
      _message = '请在系统设置的本应用权限中调整照片访问';
      _emit();
    }
  }

  void toggleAlbums() {
    if (_busy || _cloud || _loading || !state.canBrowse) return;
    _expanded = !_expanded;
    _emit();
  }

  void chooseGroup(String id) {
    if (_busy || _cloud) return;
    if (id != _selected) {
      _selected = id;
      _limit = options.pageSize;
      _restoreLimit();
    }
    _expanded = false;
    _emit();
  }

  void more() {
    if (!_busy && !_loading) {
      _limit += options.pageSize;
      _emit();
    }
  }

  Future<Uint8List?> thumbnail(AlbumAsset asset, int size) =>
      _repository.thumbnail(asset, size);
  Future<void> select(AlbumAsset asset, {bool network = false}) async {
    if (_busy || _result != null || !_foreground || !_alive) return;
    final token = ++_selection;
    final generation = _generation;
    _busy = true;
    _expanded = false;
    _cloud = false;
    _message = null;
    _pending = asset;
    final cancellation = AlbumCancellation();
    _operation = cancellation;
    _emit();
    try {
      final lease = await _repository.prepare(
        asset,
        budget,
        cancellation,
        allowNetwork: network,
      );
      if (!_valid(generation) ||
          token != _selection ||
          !_foreground ||
          cancellation.cancelled) {
        await lease.release();
        return;
      }
      _result = AlbumResult(AlbumResultKind.selected, lease: lease);
    } on AlbumFailure catch (e) {
      if (!_valid(generation) || token != _selection) return;
      if (e.code == 'networkRequired') {
        _cloud = true;
      } else {
        _message = _errorMessage(e.code);
      }
    } catch (_) {
      if (_valid(generation) && token == _selection) _message = '无法准备照片，请重新选择';
    } finally {
      if (_alive && token == _selection) {
        _busy = false;
        _emit();
      }
    }
  }

  void download() {
    final asset = _pending;
    if (_cloud && asset != null) {
      _cloud = false;
      unawaited(select(asset, network: true));
    }
  }

  void cancelPreparation({bool notify = true}) {
    _selection++;
    _operation?.cancel();
    _operation = null;
    _busy = false;
    _cloud = false;
    _pending = null;
    if (notify) _emit();
  }

  void back() {
    if (_expanded) {
      _expanded = false;
      _emit();
    } else if (_busy || _cloud) {
      cancelPreparation();
    } else {
      finish(AlbumResultKind.cancelled);
    }
  }

  void finish(AlbumResultKind kind) {
    if (!_alive || _result != null) return;
    if (kind == AlbumResultKind.cameraRequested && (!cameraEnabled || _busy)) {
      return;
    }
    if (kind == AlbumResultKind.systemPickerRequested &&
        (!systemPickerEnabled || _busy)) {
      return;
    }
    cancelPreparation(notify: false);
    _result = AlbumResult(kind);
    _emit();
  }

  AlbumResult? takeResult() {
    _taken = true;
    return _result;
  }

  void inactive() {
    _expanded = false;
    _emit();
  }

  void background() {
    _foreground = false;
    _expanded = false;
    if (_busy || _cloud) {
      cancelPreparation(notify: false);
      _message = '准备已取消，请重新选择';
    }
    _emit();
  }

  void resumed() {
    _foreground = true;
    if (!_requesting) unawaited(refresh());
  }

  @override
  void dispose() {
    _alive = false;
    cancelPreparation(notify: false);
    if (!_taken && _result?.lease != null) {
      unawaited(_result!.lease!.release().catchError((Object _) {}));
    }
    unawaited(_subscription.cancel());
    unawaited(_repository.close());
    super.dispose();
  }
}

String _errorMessage(String code) => switch (code) {
  'cancelled' => '准备已取消，请重新选择',
  'timeout' => '准备图片超时，请重试',
  'exportUnavailable' => '图片处理暂不可用，请使用系统相册选择或稍后重试',
  'budgetExceeded' => '照片过大，请选择较小的图片',
  'insufficientSpace' => '可用空间不足，请清理空间后重试',
  'resourceChanged' => '照片已变化，请重新选择',
  'permissionDenied' => '照片访问权限已变化，请刷新',
  'unsupportedFormat' => '暂不支持此图片格式，请选择其他照片',
  'networkFailed' => '照片尚未下载，连接网络后可重试',
  _ => '无法准备照片，请重新选择',
};
