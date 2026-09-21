import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';

/// 登录页；视觉与交互按 Android 基线（UI-07）还原：
/// 欢迎标题、下划线输入框、密码显隐、圆形主按钮、协议与注册/忘记密码占位。
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({required this.onBack, super.key});

  final VoidCallback onBack;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();
  bool _showPassword = false;
  bool _submitting = false;
  bool _phoneError = false;
  DataError? _error;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _username.addListener(_onUsernameChanged);
    _password.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  // Editing clears the format error like the Android baseline; the password
  // focus or a submit triggers the actual validation.
  void _onUsernameChanged() {
    if (mounted) {
      setState(() {
        if (_phoneError) {
          _phoneError = false;
        }
      });
    }
  }

  bool _isValidPhone() {
    final String value = _username.text.trim();
    return RegExp(r'^1[3-9][0-9]{9}$').hasMatch(value);
  }

  bool get _canSubmit =>
      _isValidPhone() &&
      _password.text.isNotEmpty &&
      !_submitting &&
      !_completed;

  Future<void> _submit() async {
    if (!_isValidPhone()) {
      setState(() => _phoneError = true);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final DataResult<void> result = await ref
        .read(authRepositoryProvider)
        .login(_username.text.trim(), _password.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _submitting = false;
      if (result is DataSuccess<void>) {
        _completed = true;
      } else {
        _error = (result as DataFailure<void>).error;
      }
    });
    if (_completed && context.mounted) {
      unawaited(Navigator.of(context).maybePop());
    }
  }

  void _showNotice(String message) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('提示'),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: widget.onBack)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '你好，\n欢迎登录 WanAndroid',
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontSize: 28,
                      height: 39 / 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '使用已有的 WanAndroid 账号登录',
                    style: theme.textTheme.bodyMedium!.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 44),
                  _LoginInput(
                    controller: _username,
                    label: '手机号',
                    placeholder: '请输入手机号',
                    enabled: !_submitting,
                    keyboardType: TextInputType.phone,
                    errorText: _phoneError ? '手机号输入有误，请重新输入' : null,
                  ),
                  const SizedBox(height: 28),
                  _LoginInput(
                    controller: _password,
                    focusNode: _passwordFocus,
                    label: '密码',
                    placeholder: '请输入密码',
                    enabled: !_submitting,
                    keyboardType: TextInputType.visiblePassword,
                    obscureText: !_showPassword,
                    onFocusChanged: () {
                      // The baseline validates on password focus and on submit.
                      if (!_isValidPhone() && _username.text.isNotEmpty) {
                        setState(() => _phoneError = true);
                      }
                    },
                    trailing: IconButton(
                      tooltip: _showPassword ? '隐藏密码' : '显示密码',
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text('登录即代表您已阅读并同意', style: theme.textTheme.bodySmall),
                      GestureDetector(
                        onTap: () => _showNotice('用户协议内容暂未提供。'),
                        child: Text(
                          '《用户协议》',
                          style: theme.textTheme.bodySmall!.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      Text('和', style: theme.textTheme.bodySmall),
                      GestureDetector(
                        onTap: () => _showNotice('隐私政策内容暂未提供。'),
                        child: Text(
                          '《隐私政策》',
                          style: theme.textTheme.bodySmall!.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        _error == DataError.service
                            ? '登录未成功，请检查手机号和密码后重试'
                            : '登录未成功，请稍后重试',
                        style: theme.textTheme.bodySmall!.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        shape: const StadiumBorder(),
                        minimumSize: const Size.fromHeight(50),
                      ),
                      onPressed: _canSubmit ? _submit : null,
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                      label: Text(
                        _submitting ? '正在登录…' : '登录',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      TextButton(
                        onPressed: () =>
                            _showNotice('注册功能暂未开放，请使用已有的 WanAndroid 账号登录。'),
                        child: const Text('注册'),
                      ),
                      const VerticalDivider(width: 28, thickness: 1),
                      TextButton(
                        onPressed: () => _showNotice('找回密码功能暂未开放。'),
                        child: const Text('忘记密码'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginInput extends StatelessWidget {
  const _LoginInput({
    required this.controller,
    required this.label,
    required this.placeholder,
    required this.enabled,
    required this.keyboardType,
    this.focusNode,
    this.obscureText = false,
    this.errorText,
    this.trailing,
    this.onFocusChanged,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final String placeholder;
  final bool enabled;
  final TextInputType keyboardType;
  final bool obscureText;
  final String? errorText;
  final Widget? trailing;
  final VoidCallback? onFocusChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Focus(
          onFocusChange: (bool focused) {
            if (focused) {
              onFocusChanged?.call();
            }
          },
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            obscureText: obscureText,
            keyboardType: keyboardType,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: label,
              hintText: placeholder,
              errorText: errorText,
              border: const UnderlineInputBorder(),
            ),
          ),
        ),
        if (trailing != null)
          Align(alignment: Alignment.centerRight, child: trailing!),
      ],
    );
  }
}
