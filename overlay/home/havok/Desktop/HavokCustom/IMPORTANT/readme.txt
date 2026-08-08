===============================================================================
                           !!! IMPORTANT WARNING !!!
===============================================================================

DO NOT modify, rename, or delete any files in this folder unless you
absolutely know what you are doing.

This folder contains all the .hsl (Havok Scripting Library) files that
make up the entire HavokOS desktop environment and all the built-in
applications you see.

Every window, panel, menu, button, and interface element is defined by
these HSL files. If you break them, your desktop may not load correctly
or at all.

===============================================================================

WHAT ARE THESE FILES?

Each .hsl file defines a part of the HavokOS desktop:

  desktop.hsl      - The main desktop surface, wallpaper, and icons
  panel.hsl        - The top panel/bar with clock and app launcher
  app_browser.hsl  - The Havok Browser application
  app_files.hsl    - The Havok Files (file manager) application
  app_editor.hsl   - The Havok Editor (text editor) application
  app_settings.hsl - The Havok Settings application
  menu.hsl         - The right-click context menus
  theme.hsl        - Colors, fonts, and visual styling

===============================================================================

HOW CUSTOMIZATION WORKS

1. The files in THIS folder (IMPORTANT/) define the base system.
   They are loaded FIRST when HavokOS starts.

2. You can add your OWN .hsl files in the HavokCustom folder
   (the parent folder, NOT inside IMPORTANT/).

3. Your custom files are loaded AFTER the system files, so they
   can add new widgets, buttons, menus, and functionality without
   breaking the base system.

4. To reload your changes, click the Reload button (↻) in the top
   panel, or right-click the desktop and select "Reload HSL Extensions"
   or use the HSL Settings panel.

===============================================================================

IF YOU BREAK SOMETHING

If the desktop fails to load after modifying these files, you can:

  1. Open a terminal (Ctrl+Alt+T or via the panel menu)
  2. Restore the default files from /usr/share/havok/hsl/defaults/
  3. Or reinstall HavokOS

===============================================================================
