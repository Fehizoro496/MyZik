import 'package:flutter/cupertino.dart';

/// Icon set for the music player UI, mapping the design's glyphs onto
/// [CupertinoIcons].
///
/// Screens reference these intent-based names rather than the package's
/// identifiers. Keeping the indirection here means swapping icon packs only
/// touches this file.
class AppIcons {
  const AppIcons._();

  /// Back chevron in screen headers.
  static const IconData back = CupertinoIcons.chevron_back;

  /// Trailing disclosure chevron on tappable list rows.
  static const IconData chevronRight = CupertinoIcons.chevron_forward;

  static const IconData search = CupertinoIcons.search;
  static const IconData close = CupertinoIcons.xmark;

  static const IconData heart = CupertinoIcons.heart;
  static const IconData heartFilled = CupertinoIcons.heart_fill;

  static const IconData download = CupertinoIcons.arrow_down_circle;
  static const IconData downloadFilled = CupertinoIcons.arrow_down_circle_fill;
  static const IconData downloaded = CupertinoIcons.checkmark_alt_circle_fill;
  static const IconData retry = CupertinoIcons.arrow_clockwise;

  /// Overflow menu affordance: three dots inside a circle.
  static const IconData more = CupertinoIcons.ellipsis_circle;
  static const IconData moreVert = CupertinoIcons.ellipsis_vertical;
  static const IconData moreHoriz = CupertinoIcons.ellipsis;

  static const IconData home = CupertinoIcons.house;
  static const IconData homeFilled = CupertinoIcons.house_fill;

  static const IconData category = CupertinoIcons.square_grid_2x2;
  static const IconData categoryFilled = CupertinoIcons.square_grid_2x2_fill;

  static const IconData folder = CupertinoIcons.folder;

  /// Referenced by the currently disabled "jump to now playing" nav action.
  static const IconData swap = CupertinoIcons.arrow_right_arrow_left;

  // Transport controls.
  static const IconData playFilled = CupertinoIcons.play_fill;
  static const IconData pause = CupertinoIcons.pause_fill;
  static const IconData skipPrevious = CupertinoIcons.backward_end_fill;
  static const IconData skipNext = CupertinoIcons.forward_end_fill;
  static const IconData shuffle = CupertinoIcons.shuffle;
  static const IconData repeat = CupertinoIcons.repeat;
  static const IconData repeatOne = CupertinoIcons.repeat_1;

  static const IconData musicNote = CupertinoIcons.music_note;
  static const IconData queue = CupertinoIcons.music_note_list;

  /// Lyrics panel empty state.
  static const IconData lyrics = CupertinoIcons.quote_bubble;

  static const IconData dragHandle = CupertinoIcons.line_horizontal_3;

  static const IconData add = CupertinoIcons.add;
  static const IconData addCircle = CupertinoIcons.add_circled;
  static const IconData checkCircle = CupertinoIcons.checkmark_circle_fill;
  static const IconData playlistAdd = CupertinoIcons.text_badge_plus;
  static const IconData playlistRemove = CupertinoIcons.text_badge_minus;
  static const IconData info = CupertinoIcons.info_circle;
  static const IconData edit = CupertinoIcons.pencil;
  static const IconData delete = CupertinoIcons.trash;
  static const IconData deleteFilled = CupertinoIcons.trash_fill;

  static const IconData video = CupertinoIcons.play_rectangle;
  static const IconData offline = CupertinoIcons.wifi_slash;
}
