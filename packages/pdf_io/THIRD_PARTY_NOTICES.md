# Third-party notices — pdf_io

What `pdf_io` ships or uses from other people, under which license, and what each
license asks of the app. Plan: [06-pdf 6.16, 7, 7.1](../../docs/plans/06-pdf.md)
(PDF-S7).

## 1. Dart and Flutter packages

Flutter adds the `LICENSE` file of every pub package the app depends on to the app's
license list (`NOTICES`) by itself. Nothing to do here beyond keeping the versions
pinned (contract 7.5).

| Package | Version | License | Use |
|---|---|---|---|
| pdfrx | 2.11.0 | MIT | rendering, text, passwords, save without security; its web worker runs `pdfium.wasm` |
| pdfrx_engine | 0.9.0 (indirect) | MIT | re-exported by pdfrx |
| pdfium_dart | 0.4.1 | MIT | FFI bindings of the native compose backend; its build hook downloads PDFium chromium/8125 (VM tests) |
| pdfium_flutter | 0.4.1 (indirect) | MIT | iOS / macOS PDFium XCFramework (native platforms, later) |
| file_picker | 13.3.2 | MIT | picking the PDF file |
| flutter_riverpod | 3.4.3 | MIT | state |
| material_ui | 1.10.0 | BSD-3-Clause | widgets |
| web | 1.1.2 | BSD-3-Clause | download, Web Share, Worker (`*_browser.dart` only) |
| ffi | 2.2.0 | BSD-3-Clause | native compose backend only |
| crypto | 3.0.8 | BSD-3-Clause | fixture encryption (MD5), sha256 check of the web test preparation |
| collection | 1.19.1 | BSD-3-Clause | |
| meta | 1.19.0 | BSD-3-Clause | |
| fake_async (dev) | 1.3.3 | Apache-2.0 | tests only — not shipped |

The `LICENSE` files of pdfrx and pdfium_dart are their own 11-line MIT texts: they do
**not** contain PDFium's notices. Those are section 2.

## 2. PDFium and its third-party components

PDFium is compiled into the binaries of
[pdfium-binaries](https://github.com/bblanchon/pdfium-binaries) (Benoit Blanchon), and
its notices exist only inside those release archives, so Flutter's `NOTICES` does not
have them. `pdf_io` keeps **verbatim copies** (byte for byte, no header added) in
[`licenses/`](licenses/), declares the folder as a Flutter asset (`pubspec.yaml`), and
`initializePdfIo` registers them once with `LicenseRegistry.addLicense`
(`lib/src/licenses.dart`). The texts are read only when the app opens its license
list (INFRA I9 '오픈소스 라이선스'), never at start-up, and are not compiled into
`main.dart.js`.

Archives the files come from:

| Archive | Release | Where it goes |
|---|---|---|
| `pdfium-wasm.tgz` | [chromium/7811](https://github.com/bblanchon/pdfium-binaries/releases/tag/chromium%2F7811) (PDFium 149.0.7811.0) | **Shipped** in the web app: pdfrx 2.11.0 `assets/pdfium.wasm` is byte-identical to its `lib/pdfium.wasm` (5,231,809 B, sha256 `5b2cbb18…a549df`, V17), for both the viewer worker and the compose worker |
| `pdfium-linux-x64.tgz` | [chromium/8125](https://github.com/bblanchon/pdfium-binaries/releases/tag/chromium%2F8125) (PDFium 158.0.8125.0) | VM tests only (pdfium_dart build hook) — not shipped |

Files (the union of both archives' `licenses/` folders, 19 files, plus the archives'
own `LICENSE`, identical in both). A file present in both archives is copied from
chromium/7811, the one that ships; the two copies are identical except `lcms.txt`
(7811: Little CMS 2.15 header, 8125: 2.19).

| File | Component | License | Web 7811 | VM 8125 | Copied from |
|---|---|---|---|---|---|
| `LICENSE` | pdfium-binaries packaging scripts | MIT ("This package also includes third-party software. See the licenses/ directory") | ● | ● | 7811 |
| `pdfium.txt` | PDFium | BSD-3-Clause + Apache-2.0 full text | ● | ● | 7811 |
| `abseil.txt` | Abseil | Apache-2.0 | ● | ● | 7811 |
| `agg23.txt` | Anti-Grain Geometry 2.3 | AGG permissive license (keep the notice) | ● | ● | 7811 |
| `fast_float.txt` | fast_float | MIT | ● | ● | 7811 |
| `freetype.txt` | FreeType | FreeType Project License (FTL) | ● | ● | 7811 |
| `icu.txt` | ICU | Unicode License V3 | ● | ● | 7811 |
| `lcms.txt` | Little CMS | MIT | ● | ● | 7811 |
| `libjpeg_turbo.ijg` | libjpeg-turbo (IJG part) | IJG License | ● | ● | 7811 |
| `libjpeg_turbo.md` | libjpeg-turbo | BSD-3-Clause (+ zlib) | ● | ● | 7811 |
| `libopenjpeg.txt` | OpenJPEG | BSD-2-Clause | ● | ● | 7811 |
| `libpng.txt` | libpng | PNG Reference Library License v2 | ● | ● | 7811 |
| `simdutf.txt` | simdutf | MIT (or Apache-2.0) | ● | ● | 7811 |
| `zlib.txt` | zlib | zlib License | ● | ● | 7811 |
| `libtiff.txt` | LibTIFF | libtiff permissive license | ● | — | 7811 |
| `dragonbox-Apache2-LLVM.txt` | Dragonbox | Apache-2.0 with LLVM Exception | — | ● | 8125 |
| `dragonbox-Boost.txt` | Dragonbox | Boost Software License 1.0 | — | ● | 8125 |
| `harfbuzz.txt` | HarfBuzz | Old MIT | — | ● | 8125 |
| `highway.txt` | Highway | Apache-2.0 | — | ● | 8125 |
| `llvm-libc.txt` | LLVM libc | Apache-2.0 with LLVM Exception | — | ● | 8125 |

`test/unit/licenses_test.dart` checks that `licenses/` holds exactly these 20 files,
that each one is byte-identical to the archive copy (sha256), that `pubspec.yaml`
declares the folder, and that the registry table in `lib/src/licenses.dart` lists the
same files and reads all of them.

Encoding: `freetype.txt` is ISO-8859-1 (its `©` is the byte `0xA9`); the others are
ASCII or UTF-8. The file is kept as is and `lib/src/licenses.dart` decodes it as
Latin-1 when it is not valid UTF-8.

## 3. Obligations

| Who | What the license asks | How the app meets it |
|---|---|---|
| All of section 2 (BSD, MIT, Apache-2.0, Unicode, zlib, libpng, AGG, Boost, libtiff) | Keep the copyright notices and license texts with binary distributions | The full texts in the app's license list (LicenseRegistry, above). No `NOTICE` files come with the archives, so Apache-2.0 asks for nothing more. Nothing is modified, so the zlib / libpng "altered versions" clauses do not apply |
| **FreeType** (FTL, "2. Redistribution", binary form) | A disclaimer in the distribution **documentation** that the software is based in part on the work of the FreeType Team. The license's preferred text: "Portions of this software are copyright © \<year\> The FreeType Project (www.freetype.org). All rights reserved." — `<year>` = the year of the FreeType version inside PDFium chromium/7811 | **Open (before the stage-2 release):** put the sentence in the app information and the store description. The FreeType version (hence the year) is not in the archive; read it from PDFium's `third_party/freetype` at chromium/7811 when the text is written |
| **libjpeg-turbo / IJG** (`libjpeg_turbo.ijg`, condition (2): only executable code distributed) | State in the **documentation**: "this software is based in part on the work of the Independent JPEG Group" | **Open (before the stage-2 release):** same place as the FreeType credit |
| pdfium-binaries (`LICENSE`, MIT) | Keep the notice | License list |

The two documentation credits are not shown by the license list alone; the app shell
owns the screen (INFRA 01-infra I9) and the store text.

## 4. Later

- Native platforms (iOS `pdfium_flutter` XCFramework, Android pdfrx native binaries)
  ship other PDFium builds whose `licenses/` lists must be checked again at the native
  transition; the union in `licenses/` and in `lib/src/licenses.dart` grows with them.
- A pdfrx upgrade changes `pdfium.wasm` (the web test preparation fails on a different
  sha256): re-check the archive it comes from and update this file and `licenses/`.
