# LeadingMangaZoom for KOReader

> Forked from [Maximum](https://github.com/Shac0x/maximum.koplugin) by [@Shac0x](https://github.com/Shac0x)

A KOReader plugin for reading manga and comics. Two-finger tap anywhere on the page to zoom into that quadrant. Tap once to zoom back out. Supports **CBZ**, **CBR**, and **PDF**.

---

## Screenshots

<img src="img/Img1.png" alt="Normal view" width="400">

*Normal page view*

<img src="img/Img2.png" alt="Zoomed view" width="400">

*Zoomed into a quadrant via two-finger tap*

<img src="img/Menu2.png" alt="Plugin settings" width="400">

*Plugin settings menu*

---

## How It Works

1. Open a CBZ, CBR, or PDF file in KOReader.
2. **Two-finger tap** on any area of the page to zoom into that quadrant.
3. **Tap** anywhere to zoom back out.
4. **Spread** (two fingers apart) to zoom into the page centered on your fingers.
5. **Pinch** (two fingers together) to zoom back out.

### Landscape Pages

The plugin handles landscape (double-wide) pages in two ways — pick one from the settings:

- **Auto-rotate**: Rotates landscape pages to fill the screen. Choose clockwise or counter-clockwise.
- **Page split**: Shows landscape pages as two halves — left side first, then right side when you turn the page.

These two are mutually exclusive; enabling one disables the other.

### RTL Mode

Enable **RTL mode** from the settings to switch reading direction to right-to-left when zoomed — standard for manga.

### Saving Defaults

**Hold** any toggle in the menu to save it as the default for future documents.

---

## Installation

1. Copy the `leadingmangazoom.koplugin` folder into KOReader's `plugins/` directory.
2. Restart KOReader.
3. Open a comic file — the plugin appears under **Leading Manga Zoom** in the main menu.

> **Note**: Make sure **Reflow** is disabled. Reflow re-renders pages as text, which breaks zoom functionality.

---

## Requirements

- KOReader with touch support
- CBZ, CBR, or PDF files

---

## Credits

- Original plugin by [@Shac0x](https://github.com/Shac0x) — [maximum.koplugin](https://github.com/Shac0x/maximum.koplugin)
- Auto-rotate based on [koreader-autorotate](https://github.com/Extraltodeus/koreader-autorotate) by [@Extraltodeus](https://github.com/Extraltodeus)

## License

GPL-3.0 — see [LICENSE](LICENSE).
