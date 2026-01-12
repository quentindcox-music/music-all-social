import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ReviewEditorPage extends StatefulWidget {
  const ReviewEditorPage({
    super.key,
    required this.albumId,
    this.existingRating,
    this.existingText,
  });

  final String albumId;
  final double? existingRating; // 0–10
  final String? existingText;

  @override
  State<ReviewEditorPage> createState() => _ReviewEditorPageState();
}

class _ReviewEditorPageState extends State<ReviewEditorPage> {
  late final TextEditingController _textController;
  late double _rating; // 0–10 in 0.5 steps

  bool _saving = false;

  double _snapToHalf(double value) {
    // e.g. 7.36 -> 7.5, 7.24 -> 7.0
    return (value * 2).round() / 2.0;
  }

  @override
  void initState() {
    super.initState();
    _rating = _snapToHalf((widget.existingRating ?? 0.0).clamp(0.0, 10.0));
    _textController = TextEditingController(text: widget.existingText ?? '');
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _saving = true;
    });

    final reviewsRef = FirebaseFirestore.instance
        .collection('albums')
        .doc(widget.albumId)
        .collection('reviews')
        .doc(user.uid);

    final text = _textController.text.trim();

    await reviewsRef.set(
      {
        'rating': _rating, // 0–10 (0.5 steps)
        'text': text,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    if (!mounted) return;
    setState(() {
      _saving = false;
    });
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rate This Album'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),

              // ------- RATING NUMBER (CENTERED) -------
              Center(
                child: Column(
                  children: [
                    Text(
                      _rating.toStringAsFixed(1),
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '/10',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ------- INTERACTIVE 10-STAR BAR (CENTERED) -------
              Center(
                child: _InteractiveTenStarBar(
                  rating: _rating,
                  onChanged: (value) {
                    setState(() {
                      _rating = _snapToHalf(value).clamp(0.0, 10.0);
                    });
                  },
                ),
              ),

              const SizedBox(height: 24),

              Text(
                'Your Thoughts (Optional)',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),

              TextField(
                controller: _textController,
                maxLines: 6,
                minLines: 3,
                decoration: const InputDecoration(
                  hintText: 'What did you like or dislike about this album?',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(_saving ? 'Saving…' : 'Save Rating'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 0–10 interactive star bar:
/// - 10 stars, centered
/// - tap OR drag horizontally to change rating
/// - supports half stars (0.5 increments)
class _InteractiveTenStarBar extends StatelessWidget {
  const _InteractiveTenStarBar({
    required this.rating,
    required this.onChanged,
  });

  final double rating; // 0–10
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const starCount = 10;
    const starSize = 34.0;
    const spacing = 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final desiredWidth =
            starCount * starSize + (starCount - 1) * spacing;
        // Make sure we never exceed the available width (prevents overflow).
        final rowWidth = math.min(desiredWidth, constraints.maxWidth);

        void handleLocalPosition(Offset localPosition) {
          final dx = localPosition.dx.clamp(0.0, rowWidth);
          final ratio = rowWidth == 0 ? 0.0 : dx / rowWidth; // 0.0–1.0

          // Map to 0–10 in half steps (0.5).
          // 10 stars * 2 half-steps each = 20 possible steps.
          final halfSteps = (ratio * starCount * 2).round();
          final newRating =
              (halfSteps / 2.0).clamp(0.0, starCount.toDouble());

          onChanged(newRating);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (details) => handleLocalPosition(details.localPosition),
          onPanUpdate: (details) =>
              handleLocalPosition(details.localPosition),
          onTapUp: (details) => handleLocalPosition(details.localPosition),
          child: SizedBox(
            width: rowWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(starCount, (index) {
                final starIndex = index + 1; // 1–10
                IconData icon;
                if (rating >= starIndex) {
                  icon = Icons.star; // full
                } else if (rating >= starIndex - 0.5) {
                  icon = Icons.star_half; // half
                } else {
                  icon = Icons.star_border; // empty
                }

                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: spacing / 2),
                  child: Icon(
                    icon,
                    size: starSize,
                    color: icon == Icons.star_border
                        ? theme.colorScheme.outline
                        : theme.colorScheme.primary,
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }
}
