// Calculate the dimensions of the screen in logical pixels.

import 'package:flutter/widgets.dart';

/// Logical screen size for the current widget tree.
///
/// Prefer this over `dart:ui window.physicalSize` since Flutter apps can be
/// embedded, resized (web/desktop), and have view-dependent metrics.
Size screenSize(BuildContext context) => MediaQuery.sizeOf(context);