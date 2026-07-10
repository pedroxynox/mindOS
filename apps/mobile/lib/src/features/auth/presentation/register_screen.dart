import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth_providers.dart';
import 'auth_form_scaffold.dart';

/// Account creation screen. On success the router redirects to home.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
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
        .register(_email.text, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);

    return AuthFormScaffold(
      title: 'Crea tu cuenta',
      subtitle: 'Empieza a capturar y organizar tu mente con mindOS',
      formKey: _formKey,
      emailController: _email,
      passwordController: _password,
      errorMessage: state.errorMessage,
      isSubmitting: state.isSubmitting,
      submitLabel: 'Crear cuenta',
      onSubmit: _submit,
      onFieldChanged: () => ref.read(authControllerProvider.notifier).clearError(),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('¿Ya tienes cuenta?'),
          TextButton(
            onPressed: state.isSubmitting ? null : () => context.go('/login'),
            child: const Text('Iniciar sesión'),
          ),
        ],
      ),
    );
  }
}
