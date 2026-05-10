import 'dart:ui';
import 'package:flutter/material.dart';

class BottomBar extends StatelessWidget {
  const BottomBar({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(40),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class GlassButton extends StatelessWidget {
  const GlassButton({
    required this.icon,
    this.onPressed,
    this.isActive = false,
    this.activeColor,
    this.iconColor,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final bool isActive;
  final Color? activeColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveActiveColor = activeColor ?? colorScheme.primary;
    final effectiveIconColor = iconColor ?? (isActive ? Colors.white : colorScheme.primary);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isActive ? effectiveActiveColor : Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: isActive ? effectiveActiveColor : Colors.white.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(
          icon,
          color: effectiveIconColor,
          size: 24,
        ),
      ),
    );
  }
}

class ChatButton extends StatelessWidget {
  const ChatButton({super.key});

  @override
  Widget build(BuildContext context) {
    return const GlassButton(
      icon: Icons.chat_bubble_outline_rounded,
    );
  }
}

class VideoButton extends StatelessWidget {
  const VideoButton({required this.isActive, this.onPressed, super.key});
  final bool isActive;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GlassButton(
      icon: isActive ? Icons.videocam_rounded : Icons.videocam_outlined,
      isActive: isActive,
      onPressed: onPressed,
    );
  }
}

class MuteButton extends StatelessWidget {
  const MuteButton({required this.isMuted, this.onPressed, super.key});
  final bool isMuted;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GlassButton(
      icon: isMuted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
      isActive: !isMuted,
      onPressed: onPressed,
    );
  }
}

class CallButton extends StatelessWidget {
  const CallButton({required this.isActive, this.onPressed, super.key});
  final bool isActive;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GlassButton(
      icon: isActive ? Icons.call_end_rounded : Icons.call_rounded,
      isActive: isActive,
      activeColor: Colors.redAccent.withValues(alpha: 0.8),
      onPressed: onPressed,
    );
  }
}
