# LeadingMangaZoom for KOReader

> Forked from [Maximum](https://github.com/Shac0x/maximum.koplugin) by [@Shac0x](https://github.com/Shac0x)

A powerful KOReader plugin designed for reading manga and comics. It features a smart quadrant-based zoom system, allowing you to navigate dense manga pages with ease.

---

## 🚀 Features

- **Quadrant Zoom**: Two-finger tap anywhere to instantly zoom into that quadrant.
- **Quadrant Navigation**: While zoomed, swipe, tap the left/right side of the screen or press the page buttons to move to the next quadrant, continuing onto the next page.
- **Gesture Scaling**: Spread to zoom into a custom area, or pinch to zoom back out.
- **RTL Support**: Toggle Right-to-Left reading direction for authentic manga navigation.
- **Landscape Handling**: 
    - **Auto-rotate**: Automatically rotates double-wide pages to fill your screen.
    - **Page Split**: Splits landscape pages into two logical pages (Left then Right, or vice versa).
- **Format Support**: Extensive support for all common comic book and manga archives.

---

## 📱 Screenshots

<div align="center">
  <img src="img/Img1.png" alt="Normal view" width="350">
  <img src="img/Img2.png" alt="Zoomed view" width="350">
</div>

<p align="center">
  <i>Normal page view (Left) vs. Quadrant-zoomed view (Right)</i>
</p>

---

## 📖 How to Use

1. **Open a Supported Document**: Open any compatible comic archive or PDF.
2. **Two-Finger Tap**: Tap on any of the 4 quadrants of the screen to zoom in.
3. **Move Between Quadrants**: While zoomed in:
    - **Swipe** left/right to go to the next/previous quadrant in reading order, or up/down to go to the quadrant below/above.
    - **Tap** the left or right third of the screen to go back or forward (mirrored in RTL mode).
    - **Page buttons** step through quadrants too. Going past the last quadrant turns the page and zooms into the first quadrant of the next page.
    - Turn this off with **Swipe/tap to move between quadrants** in the menu.
4. **Single Tap**: Tap the middle of the screen while zoomed in to return to the full-page view (anywhere, if quadrant navigation is off).
5. **Pinch & Spread**: Use standard multi-touch gestures for free zooming.
6. **Manage Settings**: Access the **Leading Manga Zoom** menu from the main KOReader menu.
    - *Tip: Hold any menu option to set it as the default for all future books.*

---

## 🛠 Supported Formats

LeadingMangaZoom is optimized for **fixed-layout** documents. It supports:
- **CBZ** (.zip)
- **CBR** (.rar)
- **CBT** (.tar)
- **CB7** (.7z)
- **CZB** (.czb)
- **PDF** (.pdf)

> [!NOTE]
> **Why no EPUB/MOBI?** These are "reflowable" formats. Because the content isn't fixed in place, quadrant-based zooming isn't possible. For the best experience, use [Kindle Comic Converter](https://kcc.do/) to convert your manga to **CBZ** or **PDF**.

---

## 📥 Installation

1. Download the latest release or clone this repo.
2. Copy the `leadingmangazoom.koplugin` folder into your KOReader's `plugins/` directory.
3. Restart KOReader.
4. Ensure **Reflow** is disabled for the document (as it converts images to reflowable blocks).

---

## 🤝 Credits

- Based on [maximum.koplugin](https://github.com/Shac0x/maximum.koplugin) by [@Shac0x](https://github.com/Shac0x)
- Auto-rotate logic inspired by [koreader-autorotate](https://github.com/Extraltodeus/koreader-autorotate) by [@Extraltodeus](https://github.com/Extraltodeus)

## 📅 Changelog

### v1.2.0 (2026-10-10)
- **Quadrant navigation** ([#7](https://github.com/Auri3l/leadingmangazoom.koplugin/issues/7)): swipe, tap the screen sides or use page buttons to move between zoomed quadrants without zooming out. Reading order follows RTL mode, the document's writing direction and KOReader's inverse reading order. Past the last quadrant, the page turns and the first quadrant of the next page is zoomed (not on split spreads). Can be turned off from the menu.
- Page changes made while zoomed (go to page, TOC, links, page buttons with navigation off) now release the zoom, instead of carrying one page's zoom over to the next and restoring a stale pan position later.
- Zoom levels now account for a visible status bar, like KOReader's own zoom modes, so quadrants are no longer cropped at the bottom.
- Tested against KOReader v2026.03 and v2026.07.1.

### v1.1.2 (2026-09-06)
- Load plugin modules by their own paths to avoid crashes and duplicate menus when Maximum or another plugin uses the same module names.
- Give grid, spread, pinch and zoom-collapse taps priority over KOReader's built-in gestures. Disabled features let the original gestures run.
- Handle split-page navigation through KOReader's paging controller for taps, swipes and physical buttons, including backward navigation into the last half of a spread.
- Apply landscape settings to the opening page and immediately after toggling modes. Keep auto-rotate and split defaults mutually exclusive.
- Cancel stale split-page pans on navigation, disabling or closing; preserve the selected half on redraw.
- Restore previous zoom, pan, reading direction and continuous-view state after temporary zooming, and account for screen margins in spread coordinates.
- Preserve the v1.1.1 physical-button fix and let KOReader update its layout when restoring portrait orientation.

### Developer checks

From the repository root, run `luajit tests/run.lua` or `lua5.1 tests/run.lua`.
The tests use small KOReader doubles; they do not replace validation on an e-reader.
To also exercise KOReader's real touch-zone ordering and gesture dispatch, run
`KOREADER_SOURCE=/path/to/koreader luajit tests/run.lua`.

Device checks before release: with Reflow disabled, try two-finger tap, spread,
pinch and tap-to-collapse; enable splitting on an already-open landscape page;
navigate both ways through consecutive spreads in LTR and RTL, using touch and
physical buttons; disable splitting and check that the previous view returns.
Maximum can remain installed, but enable only one plugin's overlapping gesture
features at a time if both are configured to handle the same gesture.

### v1.1.1 (2026-07-25)
- **Fixed Physical Button Remapping Issue**: Resolved a bug on devices with physical page-turn buttons (e.g. Kobo Sage, Kobo Libra 2, Kobo Forma, PocketBook, Kindle Oasis) where auto-rotating landscape pages caused physical buttons to invert and kick the user back to the previous page.

### v1.1.0 (2026-07-16)
- **Added CZB Support**: Added `.czb` to the supported fixed-layout comic formats list.
- **Fixed Zoom Coordinate Offsets**: Zooming now accurately aligns to touch centers even when the page is panned.
- **Enhanced Page Split Navigation**: Page split now tracks page numbers to properly reset the half-page panning view when moving to new landscape pages.
- **Added RTL Page Splitting**: Landscape pages in Right-to-Left orientation (e.g. Japanese manga) now split from Right-to-Left.
- **Improved Pinch Gestures**: Enabled pinch-to-zoom-out gesture to collapse both page-zoom and quadrant-zoom views.

---

## ⚖️ License

GPL-3.0 — see [LICENSE](LICENSE).
