# Leading Manga Zoom for KOReader

A manga and comic reading plugin maintained by [Auri3l](https://github.com/Auri3l), forked from [Maximum](https://github.com/Shac0x/maximum.koplugin) by Shac0x.

## Features

- Two-finger tap on a quadrant to zoom into it; single tap to return.
- Spread to zoom around the gesture position; pinch to collapse the zoom.
- Right-to-left reading support.
- Automatic rotation of landscape pages, or splitting a spread into two views with forward and backward navigation using touch gestures and physical page-turn buttons.
- Hold a menu option to save it as the default for future books.

## Installation

This `koreader-contrib` branch contains the installable plugin at the repository root. Its Lua files are identical to upstream release **v1.1.2**.

1. Copy this directory as `leadingmangazoom.koplugin` into KOReader's `plugins/` directory.
2. Restart KOReader and open a supported document with Reflow disabled.
3. Open **Leading Manga Zoom** in the reader menu to configure the plugin.

Alternatively, download `leadingmangazoom.koplugin.zip` from the [latest release](https://github.com/Auri3l/leadingmangazoom.koplugin/releases/latest) and extract it into `plugins/`.

## Compatibility

- Fixed-layout CBZ, CBR, CBT, CB7, CZB and PDF documents supported by the installed KOReader build. EPUB/MOBI and documents with Reflow enabled are excluded.
- Grid and spread/pinch zoom require a touchscreen with multi-touch support. Physical page-turn buttons are supported for split navigation.
- Automated regression tests pass on Lua 5.1 and LuaJIT 2.1. Touch-dispatch integration checks pass against KOReader **2026.03** and **2026.07**.
- These checks use KOReader doubles and real touch-dispatch modules; they are not a full renderer or physical-device test. Release v1.1.2 has not been physically validated by the maintainer on every supported device.
- Auto-rotate and page splitting are mutually exclusive. Split and temporary zoom views switch out of continuous view and restore the prior setting when disabled or collapsed.
- Maximum can remain installed. Enable only one plugin's overlapping gesture features at a time if both handle the same gesture.

## Development and support

The [master branch](https://github.com/Auri3l/leadingmangazoom.koplugin/tree/master) contains the development layout, regression tests, CI, screenshots and changelog. This branch provides a flat plugin layout for [KOReader contrib](https://github.com/koreader/contrib).

Report problems in the [upstream issue tracker](https://github.com/Auri3l/leadingmangazoom.koplugin/issues), including the device, KOReader version, plugin version and steps to reproduce.

## Credits and license

Forked from Maximum by Shac0x; auto-rotate logic was inspired by [koreader-autorotate](https://github.com/Extraltodeus/koreader-autorotate). Licensed under GPL-3.0; see [LICENSE](LICENSE).
