import 'package:flutter/material.dart';

class InteractiveRetroButton extends StatefulWidget {
  final Color color;
  final Color borderColor;
  final double width;
  final double height;
  final bool isCircle;
  final double borderRadius;
  final VoidCallback onTap;
  final Widget? child;

  const InteractiveRetroButton({
    super.key,
    required this.color,
    required this.borderColor,
    required this.width,
    required this.height,
    this.isCircle = false,
    this.borderRadius = 0,
    required this.onTap,
    this.child,
  });

  @override
  State<InteractiveRetroButton> createState() => _InteractiveRetroButtonState();
}

class _InteractiveRetroButtonState extends State<InteractiveRetroButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: _isPressed
              ? Color.lerp(widget.color, Colors.white, 0.35)!
              : widget.color,
          shape: widget.isCircle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: widget.isCircle
              ? null
              : BorderRadius.circular(widget.borderRadius),
          border: Border.all(color: widget.borderColor, width: 3.0),
          boxShadow: _isPressed
              ? [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.9),
                    blurRadius: 14,
                    spreadRadius: 3,
                  ),
                  const BoxShadow(
                    color: Colors.white,
                    blurRadius: 5,
                    spreadRadius: 1,
                  ),
                ]
              : [
                  const BoxShadow(
                    color: Colors.black45,
                    blurRadius: 4,
                    offset: Offset(0, 3),
                  ),
                ],
        ),
        child: Center(child: widget.child),
      ),
    );
  }
}

class InteractiveDPad extends StatefulWidget {
  final Color color;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onLeft;
  final VoidCallback onRight;

  const InteractiveDPad({
    super.key,
    required this.color,
    required this.onUp,
    required this.onDown,
    required this.onLeft,
    required this.onRight,
  });

  @override
  State<InteractiveDPad> createState() => _InteractiveDPadState();
}

class _InteractiveDPadState extends State<InteractiveDPad> {
  String? _pressedDir;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            width: 110,
            height: 40,
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.black, width: 3.0),
              boxShadow: _pressedDir != null
                  ? [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.7),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ]
                  : [
                      const BoxShadow(
                        color: Colors.black45,
                        blurRadius: 4,
                        offset: Offset(0, 3),
                      ),
                    ],
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            width: 40,
            height: 110,
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.black, width: 3.0),
              boxShadow: _pressedDir != null
                  ? [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.7),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ]
                  : [
                      const BoxShadow(
                        color: Colors.black45,
                        blurRadius: 4,
                        offset: Offset(0, 3),
                      ),
                    ],
            ),
          ),
          if (_pressedDir == 'up')
            Positioned(
              top: 5,
              child: Container(
                width: 36,
                height: 35,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.6),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(2),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.white,
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          if (_pressedDir == 'down')
            Positioned(
              bottom: 5,
              child: Container(
                width: 36,
                height: 35,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.6),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(2),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.white,
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          if (_pressedDir == 'left')
            Positioned(
              left: 5,
              child: Container(
                width: 35,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.6),
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(2),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.white,
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          if (_pressedDir == 'right')
            Positioned(
              right: 5,
              child: Container(
                width: 35,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.6),
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(2),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.white,
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            top: 0,
            left: 40,
            width: 40,
            height: 40,
            child: GestureDetector(
              onTapDown: (_) {
                setState(() => _pressedDir = 'up');
                widget.onUp();
              },
              onTapUp: (_) => setState(() => _pressedDir = null),
              onTapCancel: () => setState(() => _pressedDir = null),
              child: Container(
                color: Colors.transparent,
                child: const Icon(Icons.arrow_drop_up, color: Colors.black),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 40,
            width: 40,
            height: 40,
            child: GestureDetector(
              onTapDown: (_) {
                setState(() => _pressedDir = 'down');
                widget.onDown();
              },
              onTapUp: (_) => setState(() => _pressedDir = null),
              onTapCancel: () => setState(() => _pressedDir = null),
              child: Container(
                color: Colors.transparent,
                child: const Icon(Icons.arrow_drop_down, color: Colors.black),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 40,
            width: 40,
            height: 40,
            child: GestureDetector(
              onTapDown: (_) {
                setState(() => _pressedDir = 'left');
                widget.onLeft();
              },
              onTapUp: (_) => setState(() => _pressedDir = null),
              onTapCancel: () => setState(() => _pressedDir = null),
              child: Container(
                color: Colors.transparent,
                child: const Icon(
                  Icons.skip_previous,
                  size: 20,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 40,
            width: 40,
            height: 40,
            child: GestureDetector(
              onTapDown: (_) {
                setState(() => _pressedDir = 'right');
                widget.onRight();
              },
              onTapUp: (_) => setState(() => _pressedDir = null),
              onTapCancel: () => setState(() => _pressedDir = null),
              child: Container(
                color: Colors.transparent,
                child: const Icon(
                  Icons.skip_next,
                  size: 20,
                  color: Colors.black,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
