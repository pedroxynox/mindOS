import 'package:flutter/material.dart';

/// Shared visual shell for the login and register screens: a centered, width-
/// constrained card (looks good on web/desktop) with a branded header, an
/// email + password form, an inline error banner and a primary action.
class AuthFormScaffold extends StatefulWidget {
  const AuthFormScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.submitLabel,
    required this.onSubmit,
    required this.isSubmitting,
    this.errorMessage,
    this.onFieldChanged,
    this.footer,
  });

  final String title;
  final String subtitle;
  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final String submitLabel;
  final Future<void> Function() onSubmit;
  final bool isSubmitting;
  final String? errorMessage;
  final VoidCallback? onFieldChanged;
  final Widget? footer;

  @override
  State<AuthFormScaffold> createState() => _AuthFormScaffoldState();
}

class _AuthFormScaffoldState extends State<AuthFormScaffold> {
  bool _obscure = true;

  String? _validateEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Escribe tu correo';
    if (!v.contains('@') || !v.contains('.')) return 'Correo no válido';
    return null;
  }

  String? _validatePassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Escribe tu contraseña';
    if (v.length < 8) return 'Mínimo 8 caracteres';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: widget.formKey,
                  onChanged: widget.onFieldChanged,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: theme.colorScheme.primary,
                        child: Icon(
                          Icons.psychology_alt,
                          color: theme.colorScheme.onPrimary,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.subtitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: widget.emailController,
                        enabled: !widget.isSubmitting,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Correo',
                          prefixIcon: Icon(Icons.mail_outline),
                          border: OutlineInputBorder(),
                        ),
                        validator: _validateEmail,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: widget.passwordController,
                        enabled: !widget.isSubmitting,
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) {
                          if (!widget.isSubmitting) widget.onSubmit();
                        },
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(_obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: _validatePassword,
                      ),
                      if (widget.errorMessage != null) ...[
                        const SizedBox(height: 16),
                        _ErrorBanner(message: widget.errorMessage!),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed:
                            widget.isSubmitting ? null : () => widget.onSubmit(),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: widget.isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(widget.submitLabel),
                      ),
                      if (widget.footer != null) ...[
                        const SizedBox(height: 8),
                        widget.footer!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline,
              size: 20, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
