// lib/utils/error_handler.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

class ErrorHandler {
  /// Shows a user-friendly error message based on the error type
  static void handle(BuildContext context, dynamic error, {String? customMessage}) {
    String message = customMessage ?? _getErrorMessage(error);
    
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  static String _getErrorMessage(dynamic error) {
    if (error is FirebaseException) {
      return _handleFirebaseError(error);
    }
    
    final errorString = error.toString().toLowerCase();
    
    if (errorString.contains('handshakeexception') || 
        errorString.contains('socketexception')) {
      return 'Check your internet connection and try again';
    }
    
    if (errorString.contains('timeout')) {
      return 'Request timed out. Please try again';
    }
    
    if (errorString.contains('format')) {
      return 'Invalid data format received';
    }
    
    return 'Something went wrong. Please try again';
  }

  static String _handleFirebaseError(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
        return 'You don\'t have permission to perform this action';
      case 'not-found':
        return 'The requested data was not found';
      case 'already-exists':
        return 'This item already exists';
      case 'unauthenticated':
        return 'Please sign in to continue';
      case 'unavailable':
        return 'Service temporarily unavailable. Please try again';
      default:
        return 'An error occurred: ${error.message ?? error.code}';
    }
  }

  /// Shows a loading dialog
  static void showLoading(BuildContext context, {String? message}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  if (message != null) ...[
                    const SizedBox(height: 16),
                    Text(message),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Hides the loading dialog
  static void hideLoading(BuildContext context) {
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }
}