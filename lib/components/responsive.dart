import 'package:flutter/material.dart';

class Responsive extends StatelessWidget {
  final Widget child;

  const Responsive({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    final bool isDesktop = width >= 1024;
    final bool isTablet = width >= 768 && width < 1024;

    final double maxWidth = isDesktop
        ? 520
        : isTablet
            ? 450
            : double.infinity;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 28 : 0,
            vertical: isDesktop ? 24 : 0,
          ),
          decoration: isDesktop
              ? BoxDecoration(
                  color: Colors.white.withOpacity(0.90),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    )
                  ],
              )
              : null,
          child: child,
        ),
      ),
    );
  }
}