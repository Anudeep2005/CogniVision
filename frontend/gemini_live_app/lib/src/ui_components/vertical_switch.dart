import 'dart:developer';
import 'package:flutter/material.dart';

class VerticalSwitch extends StatefulWidget {
  const VerticalSwitch({this.onChanged, this.initialValue = false, super.key});
  final ValueChanged<bool>? onChanged;
  final bool initialValue;

  @override
  State<VerticalSwitch> createState() => _VerticalSwitchState();
}

class _VerticalSwitchState extends State<VerticalSwitch> {
  late bool _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RotatedBox(
          quarterTurns: 3, // Vertical orientation
          child: Switch(
            value: _value,
            activeThumbColor: colorScheme.primary,
            activeTrackColor: colorScheme.primary.withValues(alpha: 0.2),
            inactiveThumbColor: colorScheme.secondary.withValues(alpha: 0.8),
            inactiveTrackColor: colorScheme.surfaceContainer.withValues(alpha: 0.5),
            trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
            onChanged: (val) {
              setState(() {
                _value = val;
              });
              if (widget.onChanged != null) {
                widget.onChanged!(val);
              }
              log('Vertical Switch Value: $val');
            },
          ),
        ),
      ],
    );
  }
}
