import 'package:flutter/material.dart';

class BottomBar extends StatelessWidget {
  const BottomBar({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.surfaceContainer,
            ),
          ),
        ),
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }
}

class ChatButton extends StatelessWidget {
  const ChatButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: IconButton.filledTonal(
        onPressed: () {},
        icon: const Padding(
          padding: EdgeInsets.all(4),
          child: Icon(Icons.chat_bubble_outline),
        ),
      ),
    );
  }
}

class VideoButton extends StatelessWidget {
  const VideoButton({required this.isActive, this.onPressed, super.key});
  final bool isActive;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: IconButton.filledTonal(
        style: isActive
            ? ButtonStyle(
                backgroundColor: WidgetStateProperty.all(
                  const Color.fromARGB(240, 238, 255, 244),
                ),
                iconColor: WidgetStateProperty.all(Colors.black87),
              )
            : const ButtonStyle(),
        onPressed: onPressed,
        icon: const Padding(
          padding: EdgeInsets.all(4),
          child: Icon(Icons.video_call_rounded),
        ),
      ),
    );
  }
}

class MuteButton extends StatelessWidget {
  const MuteButton({required this.isMuted, this.onPressed, super.key});
  final bool isMuted;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: IconButton.filledTonal(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(
            isMuted ? null : const Color.fromARGB(240, 238, 255, 244),
          ),
        ),
        onPressed: onPressed,
        icon: Padding(
          padding: const EdgeInsets.all(4),
          child: isMuted
              ? const Icon(Icons.mic_off)
              : const Icon(color: Colors.black87, Icons.mic_none),
        ),
      ),
    );
  }
}

class CallButton extends StatelessWidget {
  const CallButton({required this.isActive, this.onPressed, super.key});
  final bool isActive;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: IconButton.filledTonal(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(
            isActive ? const Color.fromARGB(255, 199, 39, 27) : Colors.green[500],
          ),
        ),
        onPressed: onPressed,
        icon: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(isActive ? Icons.phone_disabled_outlined : Icons.phone),
        ),
      ),
    );
  }
}