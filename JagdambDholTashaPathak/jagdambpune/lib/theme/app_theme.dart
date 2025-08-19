// import 'package:flutter/material.dart';
// import 'app_colors.dart';

// class AppTheme {
//   static ThemeData lightTheme = ThemeData(
//     scaffoldBackgroundColor: AppColors.primaryMaroon,
    
//     // ✅ AppBar with yellow icons (back button & actions)
//     appBarTheme: const AppBarTheme(
//       backgroundColor: AppColors.primaryMaroon,
//       elevation: 0,
//       iconTheme: IconThemeData(color: AppColors.accentYellow), // Back button yellow
//       titleTextStyle: TextStyle(color: AppColors.white, fontSize: 20),
//     ),

//     // ✅ All icons default to yellow (including dropdowns)
//     iconTheme: const IconThemeData(color: AppColors.accentYellow),

//     textTheme: const TextTheme(
//       bodyMedium: TextStyle(color: AppColors.white),
//     ),

//     // ✅ Dropdown menu style with maroon background & white text
//     dropdownMenuTheme: const DropdownMenuThemeData(
//       menuStyle: MenuStyle(
//         backgroundColor: WidgetStatePropertyAll(AppColors.primaryMaroon),
//       ),
//       textStyle: TextStyle(color: AppColors.white),
//     ),
//   );
// }

import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData lightTheme = ThemeData(
    scaffoldBackgroundColor: AppColors.primaryMaroon,

    // ✅ AppBar with yellow icons & white title
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primaryMaroon,
      elevation: 0,
      iconTheme: IconThemeData(color: AppColors.accentYellow), // Back button yellow
      titleTextStyle: TextStyle(color: AppColors.textLight, fontSize: 20),
    ),

    // ✅ All icons (including dropdowns) are yellow by default
    iconTheme: const IconThemeData(color: AppColors.accentYellow),

    // ✅ Global text theme
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: AppColors.textLight),
    ),

    // ✅ Dropdown Menu Style
    dropdownMenuTheme: const DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(AppColors.primaryMaroon),
      ),
      textStyle: TextStyle(color: AppColors.textLight),
    ),
  );
}
