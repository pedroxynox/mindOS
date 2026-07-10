import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth_providers.dart';
import 'auth_form_scaffold.dart';

/// Sign-in screen. On success the router redirects to home automatically.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await ref
        .read(authControllerProvider.notifier)
        .login(_email.text, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);

    return AuthFormScaffold(
      title: 'Bienvenido de vuelta',
      subtitle: 'Inicia sesión para continuar con mindOS',
      formKey: _formKey,
      emailController: _email,
      passwordController: _password,
      errorMessage: state.errorMessage,
      isSubmitting: state.isSubmitting,
      submitLabel: 'Iniciar sesión',
      onSubmit: _submit,
      onFieldChanged: () => ref.read(authControllerProvider.notifier).clearError(),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('¿No tienes cuenta?'),
          TextButton(
            onPressed: state.isSubmitting ? null : () => context.go('/register'),
            child: const Text('Crear cuenta'),
          ),
        ],
      ),
    );
  }
}
