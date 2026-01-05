// lib/widgets/portal_opening_overlay.dart
import 'package:flutter/material.dart';

class PortalOpeningOverlay extends StatefulWidget {
  final VoidCallback onComplete;
  final Color portalColor;

  const PortalOpeningOverlay({super.key, required this.onComplete, required this.portalColor});

  @override
  State<PortalOpeningOverlay> createState() => _PortalOpeningOverlayState();
}

class _PortalOpeningOverlayState extends State<PortalOpeningOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    
    _scaleAnimation = Tween<double>(begin: 0.0, end: 20.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInExpo),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.5, curve: Curves.easeIn)),
    );

    _controller.forward().then((_) => widget.onComplete());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Opacity(
              opacity: _opacityAnimation.value,
              child: Container(
                width: 100 * _scaleAnimation.value,
                height: 100 * _scaleAnimation.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.portalColor,
                  boxShadow: [
                    BoxShadow(color: widget.portalColor.withOpacity(0.8), blurRadius: 100, spreadRadius: 50)
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}