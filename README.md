# LeadingMangaZoom for KOReader

> Forked from [Maximum](https://github.com/Shac0x/maximum.koplugin) by [@Shac0x](https://github.com/Shac0x)

A powerful KOReader plugin designed for reading manga and comics. It features a smart quadrant-based zoom system, allowing you to navigate dense manga pages with ease.

---

## 🚀 Features

- **Quadrant Zoom**: Two-finger tap anywhere to instantly zoom into that quadrant.
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
3. **Single Tap**: Tap anywhere while zoomed in to return to the full-page view.
4. **Pinch & Spread**: Use standard multi-touch gestures for free zooming.
5. **Manage Settings**: Access the **Leading Manga Zoom** menu from the main KOReader menu.
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

### v1.1.0 (2026-07-16)
- **Added CZB Support**: Added `.czb` to the supported fixed-layout comic formats list.
- **Fixed Zoom Coordinate Offsets**: Zooming now accurately aligns to touch centers even when the page is panned.
- **Enhanced Page Split Navigation**: Page split now tracks page numbers to properly reset the half-page panning view when moving to new landscape pages.
- **Added RTL Page Splitting**: Landscape pages in Right-to-Left orientation (e.g. Japanese manga) now split from Right-to-Left.
- **Improved Pinch Gestures**: Enabled pinch-to-zoom-out gesture to collapse both page-zoom and quadrant-zoom views.

---

## ⚖️ License

GPL-3.0 — see [LICENSE](LICENSE).
