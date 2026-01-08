import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/user_service.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({
    super.key,
    required this.signedOutBuilder,
    required this.signedInBuilder,
  });

  final WidgetBuilder signedOutBuilder;
  final WidgetBuilder signedInBuilder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return signedOutBuilder(context);
        }

        return _PostSignIn(
          user: user,
          child: signedInBuilder(context),
        );
      },
    );
  }
}

class _PostSignIn extends StatefulWidget {
  const _PostSignIn({required this.user, required this.child});

  final User user;
  final Widget child;

  @override
  State<_PostSignIn> createState() => _PostSignInState();
}

class _PostSignInState extends State<_PostSignIn> {
  bool _didWrite = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didWrite) return;
    _didWrite = true;

    UserService.upsertUser(widget.user);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
