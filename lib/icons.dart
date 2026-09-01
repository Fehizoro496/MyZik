import 'package:flutter/widgets.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// Icon set for the music player UI, mapping the design's glyphs onto Iconsax.
///
/// Screens reference these intent-based names rather than the package's
/// generated identifiers, whose `_copy` suffix is how the generator spells the
/// Bold style. Keeping the indirection here means swapping icon packs — as was
/// needed when flutter_iconly stopped compiling — only touches this file.
class AppIcons {
  const AppIcons._();

  /// Back chevron in screen headers.
  static const IconData back = Iconsax.arrow_left_2;

  /// Trailing disclosure chevron on tappable list rows.
  static const IconData chevronRight = Iconsax.arrow_right_2;

  static const IconData search = Iconsax.search_normal;

  static const IconData heart = Iconsax.heart;
  static const IconData heartFilled = Iconsax.heart_copy;

  /// Iconsax spells the download tray "import" (and upload "export").
  static const IconData download = Iconsax.import;
  static const IconData downloadFilled = Iconsax.import_copy;

  static const IconData playFilled = Iconsax.play_copy;

  /// Overflow menu affordance: three dots inside a circle.
  static const IconData more = Iconsax.more_circle;

  static const IconData home = Iconsax.home_2;
  static const IconData homeFilled = Iconsax.home_2_copy;

  static const IconData category = Iconsax.category;
  static const IconData categoryFilled = Iconsax.category_copy;

  static const IconData folder = Iconsax.folder;

  /// Referenced by the currently disabled "jump to now playing" nav action.
  static const IconData swap = Iconsax.arrow_swap_horizontal;
}
