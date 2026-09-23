import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/features/auth/state/login_ui_state.dart';

/// Login view. Request ownership and navigation live in the route-scoped
/// view model so leaving this screen can cancel an in-flight login.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.state,
    required this.onUsernameChanged,
    required this.onPasswordChanged,
    required this.onPasswordFocused,
    required this.onSubmit,
    required this.onBack,
    super.key,
  });

  final LoginUiState state;
  final ValueChanged<String> onUsernameChanged;
  final ValueChanged<String> onPasswordChanged;
  final VoidCallback onPasswordFocused;
  final Future<void> Function() onSubmit;
  final VoidCallback onBack;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _username;
  late final TextEditingController _password;
  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _username = TextEditingController(text: widget.state.username);
    _password = TextEditingController(text: widget.state.password);
    _passwordFocus.addListener(_notifyPasswordFocus);
  }

  @override
  void didUpdateWidget(LoginScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _synchronize(_username, widget.state.username);
    _synchronize(_password, widget.state.password);
  }

  @override
  void dispose() {
    _passwordFocus.removeListener(_notifyPasswordFocus);
    _username.dispose();
    _password.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _synchronize(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _notifyPasswordFocus() {
    if (_passwordFocus.hasFocus) {
      widget.onPasswordFocused();
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    await widget.onSubmit();
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
    final LoginUiState state = widget.state;
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
                    focusNode: _usernameFocus,
                    semanticsLabel: '手机号',
                    placeholder: '请输入手机号',
                    enabled: !state.submitting,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    autofillHints: const <String>[AutofillHints.username],
                    errorText: state.phoneError ? '手机号输入有误，请重新输入' : null,
                    onChanged: widget.onUsernameChanged,
                    onSubmitted: (_) => _passwordFocus.requestFocus(),
                  ),
                  const SizedBox(height: 28),
                  _LoginInput(
                    controller: _password,
                    focusNode: _passwordFocus,
                    semanticsLabel: '密码',
                    placeholder: '请输入密码',
                    enabled: !state.submitting,
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: const <String>[AutofillHints.password],
                    obscureText: !_showPassword,
                    onChanged: widget.onPasswordChanged,
                    onSubmitted: (_) {
                      if (state.canSubmit) unawaited(_submit());
                    },
                    suffixIcon: IconButton(
                      tooltip: _showPassword ? '隐藏密码' : '显示密码',
                      onPressed: state.submitting
                          ? null
                          : () =>
                                setState(() => _showPassword = !_showPassword),
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        Text('登录即代表您已阅读并同意', style: theme.textTheme.bodySmall),
                        TextButton(
                          style: TextButton.styleFrom(
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => _showNotice('用户协议内容暂未提供。'),
                          child: const Text('《用户协议》'),
                        ),
                        Text('和', style: theme.textTheme.bodySmall),
                        TextButton(
                          style: TextButton.styleFrom(
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => _showNotice('隐私政策内容暂未提供。'),
                          child: const Text('《隐私政策》'),
                        ),
                      ],
                    ),
                  ),
                  if (state.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        state.error == DataError.service
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
                      onPressed: state.canSubmit ? _submit : null,
                      icon: state.submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                      label: Text(
                        state.submitting ? '正在登录…' : '登录',
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
                      const SizedBox(
                        height: 24,
                        child: VerticalDivider(width: 28, thickness: 1),
                      ),
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
    required this.focusNode,
    required this.semanticsLabel,
    required this.placeholder,
    required this.enabled,
    required this.keyboardType,
    required this.textInputAction,
    required this.autofillHints,
    required this.onChanged,
    required this.onSubmitted,
    this.obscureText = false,
    this.errorText,
    this.suffixIcon,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String semanticsLabel;
  final String placeholder;
  final bool enabled;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final Iterable<String> autofillHints;
  final bool obscureText;
  final String? errorText;
  final Widget? suffixIcon;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      textField: true,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        obscureText: obscureText,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        autofillHints: autofillHints,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          hintText: placeholder,
          errorText: errorText,
          suffixIcon: suffixIcon,
          border: const UnderlineInputBorder(),
        ),
      ),
    );
  }
}
