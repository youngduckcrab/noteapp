// pdf_io compose worker extension (06-pdf 6.11.4–6.11.6). Loaded by the dedicated compose
// Worker right after pdfrx 2.11.0's pdfium_worker.js:
//
//   const pdfiumWasmUrl="<modules>/pdfium.wasm";importScripts("<modules>/pdfium_worker.js");
//   importScripts("<this file>");
//
// Both are classic scripts in one worker global scope, so the worker's top-level `functions`
// table, `encodePdf`, `Pdfium` and `StringUtils` are visible here (V9). The commands use the
// worker's request protocol ({id, command, parameters} → {id, status, result | error}):
//
//   pdfioComposeBegin    {jobId, sources: [ArrayBuffer], pages: ArrayBuffer (Float64 plan)}
//                        → {pageCount}
//   pdfioComposeAddPages {jobId, pages: [{outputIndex, verbs, coords, paints, images, texts,
//                        fonts}]} → {done}
//                        (2차) images: [{jpeg, width, height, hasAlpha, data: ArrayBuffer}],
//                        texts: [string], fonts: [[fontId, ArrayBuffer]] (m5-7/06-pdf 6.2.6)
//   pdfioComposeFinish   {jobId} → {data: ArrayBuffer} (transferred; pdfrx encodePdf)
//   pdfioComposeAbort    {jobId} → {}
//   pdfioComposeJobCount {} → {count}   (test hook: open jobs in this worker)
//
// The steps mirror lib/src/compose/compose_layout.dart (visible box, D, M = D ∘ F, plan
// rows, import / move / blank steps) and the native interpreter in
// compose_backend_native.dart; test/unit/compose_layout_test.dart holds the reference
// values and test/web/compose_browser_test.dart runs the shared compose probes.
//
// If the pdfrx worker internals are not what this file expects, every compose command
// fails with 'pdfio-incompatible-pdfrx' (Dart: engineUnavailable). pdfrx is pinned exactly.
//
// (2차, m5-7/06-pdf T23 — 6.2.5–6.2.7) image and text ops, the same steps as the native
// interpreter: a part's fonts first (FPDFText_LoadFont, closed with FPDFFont_Close before the
// document), JPEG bytes as they are (FPDFImageObj_LoadJpegFileInline through an
// FPDF_FILEACCESS whose m_GetBlock is a Pdfium.addFunction callback — pdfrx's own
// createDocumentFromJpegData does the same, E6), RGBA as a BGRA bitmap (BGRx without alpha:
// no SMask), text as UTF-16 in wasm memory. The compatibility check also needs
// Pdfium.addFunction / removeFunction.
'use strict';

(function () {
  const INCOMPATIBLE = 'pdfio-incompatible-pdfrx';
  if (typeof functions !== 'object' || functions === null) {
    // Nothing to register into: the requests fail as unknown commands (Dart: engineUnavailable).
    return;
  }
  const compatible =
    typeof encodePdf === 'function' &&
    typeof Pdfium === 'object' &&
    Pdfium !== null &&
    typeof Pdfium.addFunction === 'function' &&
    typeof Pdfium.removeFunction === 'function' &&
    typeof StringUtils === 'function';
  if (!compatible) {
    const incompatible = function () {
      throw new Error(INCOMPATIBLE);
    };
    functions.pdfioComposeBegin = incompatible;
    functions.pdfioComposeAddPages = incompatible;
    functions.pdfioComposeFinish = incompatible;
    functions.pdfioComposeAbort = function () {
      return {};
    };
    functions.pdfioComposeJobCount = function () {
      return { count: 0 };
    };
    return;
  }

  // 6.11.5 opcodes and paint layout (PdfComposeOpcodes).
  const MOVE_TO = 0;
  const LINE_TO = 1;
  const CUBIC_TO = 2;
  const CLOSE = 3;
  const END_OBJECT = 7;
  const IMAGE = 8;
  const TEXT = 9;
  const IMAGE_ARGS = 7;
  const TEXT_ARGS = 13;
  const PAINT_STRIDE = 10;
  const PLAN_STRIDE = 6;
  const FONT_TRUETYPE = 2; // FPDF_FONT_TRUETYPE
  const BITMAP_BGRX = 3; // FPDFBitmap_BGRx
  const BITMAP_BGRA = 4; // FPDFBitmap_BGRA

  /** jobId → {dst, sources: [docHandle], buffers: [ptr], rows, fonts: Map<fontId, FPDF_FONT>} */
  const jobs = new Map();

  function wasm() {
    return Pdfium.wasmExports;
  }

  function fail(message) {
    throw new Error('pdfio-compose: ' + message);
  }

  // ---- 6.11.3 coordinates (= PdfComposePageBox) -------------------------------------

  function normalized(box) {
    if (!box || box.length !== 4 || !box.every(Number.isFinite)) return null;
    return {
      l: Math.min(box[0], box[2]),
      b: Math.min(box[1], box[3]),
      r: Math.max(box[0], box[2]),
      t: Math.max(box[1], box[3]),
    };
  }

  function isEmpty(box) {
    return !(box.r > box.l && box.t > box.b);
  }

  /** CropBox ∩ MediaBox, else MediaBox, else [0 0 612 792] (PDFium CPDF_Page). */
  function visibleBox(mediaBox, cropBox, rotation) {
    let media = normalized(mediaBox);
    if (media === null || isEmpty(media)) media = { l: 0, b: 0, r: 612, t: 792 };
    let box = media;
    const crop = normalized(cropBox);
    if (crop !== null && !isEmpty(crop)) {
      const l = Math.max(crop.l, media.l);
      const b = Math.max(crop.b, media.b);
      const r = Math.min(crop.r, media.r);
      const t = Math.min(crop.t, media.t);
      if (l < r && b < t) box = { l: l, b: b, r: r, t: t };
    }
    return { l: box.l, b: box.b, r: box.r, t: box.t, rot: ((rotation % 4) + 4) % 4 };
  }

  function displaySize(box) {
    return box.rot % 2 === 1 ? [box.t - box.b, box.r - box.l] : [box.r - box.l, box.t - box.b];
  }

  /** D: displayed pt (y down) → PDF user space. */
  function displayToUser(box) {
    switch (box.rot) {
      case 0:
        return [1, 0, 0, -1, box.l, box.t];
      case 1:
        return [0, 1, 1, 0, box.l, box.b];
      case 2:
        return [-1, 0, 0, 1, box.r, box.b];
      default:
        return [0, -1, -1, 0, box.r, box.t];
    }
  }

  /** M = D ∘ F, F = PdfPageFit.noteToPdfMatrix() (identity when the fit is one). */
  function noteToUser(box, noteWidth, noteHeight) {
    const d = displayToUser(box);
    const size = displaySize(box);
    const dw = size[0];
    const dh = size[1];
    const k = Math.min(noteWidth / dw, noteHeight / dh);
    const ox = (noteWidth - dw * k) / 2;
    const oy = (noteHeight - dh * k) / 2;
    if (Math.abs(k - 1) < 1e-4 && Math.abs(ox) < 1e-3 && Math.abs(oy) < 1e-3) return d;
    const s = 1 / k;
    const tx = -ox / k;
    const ty = -oy / k;
    return [d[0] * s, d[1] * s, d[2] * s, d[3] * s, d[0] * tx + d[2] * ty + d[4], d[1] * tx + d[3] * ty + d[5]];
  }

  // ---- 6.11.4 plan and page assembly (= decodeComposePlan, PdfComposeLayout) ---------

  function decodePlan(pages, sourceCount) {
    if (pages.length % PLAN_STRIDE !== 0) fail('plan length ' + pages.length);
    const rows = [];
    for (let o = 0; o < pages.length; o += PLAN_STRIDE) {
      const kind = pages[o];
      const w = pages[o + 3];
      const h = pages[o + 4];
      if (!(Number.isFinite(w) && Number.isFinite(h) && w > 0 && h > 0)) {
        fail('page ' + o / PLAN_STRIDE + ': note size ' + w + ' x ' + h);
      }
      if (kind === 1) {
        rows.push({ blank: true, source: -1, index: -1, w: w, h: h });
        continue;
      }
      const source = pages[o + 1];
      const index = pages[o + 2];
      const ok =
        kind === 0 &&
        Number.isInteger(source) &&
        Number.isInteger(index) &&
        source >= 0 &&
        source < sourceCount &&
        index >= 0;
      if (!ok) fail('page ' + o / PLAN_STRIDE + ': kind ' + kind + ', source ' + source + ', pdf page ' + index);
      rows.push({ blank: false, source: source, index: index, w: w, h: h });
    }
    return rows;
  }

  function layoutOf(rows, sourceCount) {
    const imports = [];
    const importedOutputs = [];
    for (let s = 0; s < sourceCount; s++) {
      imports.push([]);
      importedOutputs.push([]);
    }
    const sourceOrder = [];
    const blanks = [];
    rows.forEach(function (row, i) {
      if (row.blank) {
        blanks.push(i);
        return;
      }
      imports[row.source].push(row.index);
      importedOutputs[row.source].push(i);
      sourceOrder.push(i);
    });
    const current = [].concat.apply([], importedOutputs);
    const moves = [];
    const usedSources = imports.filter(function (list) {
      return list.length > 0;
    }).length;
    if (usedSources > 1) {
      for (let t = 0; t < sourceOrder.length; t++) {
        const p = current.indexOf(sourceOrder[t], t);
        if (p === t) continue;
        moves.push([p, t]);
        current.splice(t, 0, current.splice(p, 1)[0]);
      }
    }
    return { imports: imports, moves: moves, blanks: blanks };
  }

  function release(job) {
    const w = wasm();
    // Fonts first: a font points at its document.
    job.fonts.forEach(function (font) {
      w.FPDFFont_Close(font);
    });
    job.fonts.clear();
    if (job.dst) w.FPDF_CloseDocument(job.dst);
    job.dst = 0;
    job.sources.forEach(function (doc) {
      w.FPDF_CloseDocument(doc);
    });
    job.sources = [];
    job.buffers.forEach(function (ptr) {
      w.free(ptr);
    });
    job.buffers = [];
  }

  function withInts(values, action) {
    const w = wasm();
    const ptr = w.malloc(4 * Math.max(values.length, 1));
    try {
      new Int32Array(Pdfium.memory.buffer, ptr, values.length).set(values);
      return action(ptr);
    } finally {
      w.free(ptr);
    }
  }

  function begin(params) {
    const jobId = params.jobId;
    if (jobs.has(jobId)) fail('job ' + jobId + ' exists');
    const sources = params.sources || [];
    const rows = decodePlan(new Float64Array(params.pages), sources.length);
    const w = wasm();
    const job = { dst: 0, sources: [], buffers: [], rows: rows, fonts: new Map() };
    try {
      job.dst = w.FPDF_CreateNewDocument();
      if (!job.dst) fail('FPDF_CreateNewDocument failed');
      // Step 1: each source into wasm memory (PDFium keeps reading it until it is closed).
      sources.forEach(function (source, s) {
        const bytes = new Uint8Array(source);
        const ptr = w.malloc(Math.max(bytes.length, 1));
        if (!ptr) fail('source ' + s + ': out of memory');
        job.buffers.push(ptr);
        new Uint8Array(Pdfium.memory.buffer, ptr, bytes.length).set(bytes);
        const doc = w.FPDF_LoadMemDocument(ptr, bytes.length, 0);
        if (!doc) fail('source ' + s + ': FPDF_LoadMemDocument error ' + w.FPDF_GetLastError());
        job.sources.push(doc);
      });
      const layout = layoutOf(rows, sources.length);
      // Step 3: one import call per source (shared resources copied once, V7).
      layout.imports.forEach(function (indexes, s) {
        if (indexes.length === 0) return;
        const count = w.FPDF_GetPageCount(job.sources[s]);
        indexes.forEach(function (index) {
          if (index >= count) fail('source ' + s + ': pdf page ' + index + ' not in 0..' + (count - 1));
        });
        const ok = withInts(indexes, function (ptr) {
          return w.FPDF_ImportPagesByIndex(job.dst, job.sources[s], ptr, indexes.length, w.FPDF_GetPageCount(job.dst));
        });
        if (!ok) fail('source ' + s + ': import failed');
      });
      // Step 4: source pages into output order (several sources only).
      layout.moves.forEach(function (move) {
        const ok = withInts([move[0]], function (ptr) {
          return w.FPDF_MovePages(job.dst, ptr, 1, move[1]);
        });
        if (!ok) fail('move ' + move[0] + ' -> ' + move[1] + ' failed');
      });
      // Step 5: blank pages at their final indexes, ascending.
      layout.blanks.forEach(function (index) {
        const page = w.FPDFPage_New(job.dst, index, rows[index].w, rows[index].h);
        if (!page) fail('blank page ' + index);
        w.FPDF_ClosePage(page);
      });
      // Step 6.
      const pageCount = w.FPDF_GetPageCount(job.dst);
      if (pageCount !== rows.length) fail(pageCount + ' pages, plan has ' + rows.length);
      jobs.set(jobId, job);
      return { pageCount: pageCount };
    } catch (e) {
      release(job);
      throw e;
    }
  }

  // ---- 6.11.5 interpreter -----------------------------------------------------------

  function pageBox(page) {
    const w = wasm();
    const ptr = w.malloc(16);
    try {
      const read = function (getter) {
        if (!getter(page, ptr, ptr + 4, ptr + 8, ptr + 12)) return null;
        return Array.from(new Float32Array(Pdfium.memory.buffer, ptr, 4));
      };
      const media = read(w.FPDFPage_GetMediaBox);
      const crop = read(w.FPDFPage_GetCropBox);
      return visibleBox(media, crop, w.FPDFPage_GetRotation(page));
    } finally {
      w.free(ptr);
    }
  }

  function interpretPage(job, ops, multiply) {
    const w = wasm();
    const outputIndex = ops.outputIndex;
    if (!(Number.isInteger(outputIndex) && outputIndex >= 0 && outputIndex < job.rows.length)) {
      fail('outputIndex ' + outputIndex);
    }
    const row = job.rows[outputIndex];
    const verbs = new Uint8Array(ops.verbs);
    const coords = new Float32Array(ops.coords);
    const paints = new Float32Array(ops.paints);
    const images = ops.images || [];
    const texts = ops.texts || [];
    // 6.2.6: the part's fonts go into the document before its ops run.
    (ops.fonts || []).forEach(function (entry) {
      loadFont(job, entry[0], entry[1]);
    });
    if (verbs.length === 0) return;
    const page = w.FPDF_LoadPage(job.dst, outputIndex);
    if (!page) fail('FPDF_LoadPage ' + outputIndex + ' failed');
    let object = 0;
    try {
      const m = noteToUser(pageBox(page), row.w, row.h);
      let c = 0;
      const open = function (v) {
        if (!object) fail('verb ' + v + ': no moveTo before it');
        return object;
      };
      for (let v = 0; v < verbs.length; v++) {
        switch (verbs[v]) {
          case MOVE_TO:
            if (object) {
              w.FPDFPath_MoveTo(object, coords[c], coords[c + 1]);
            } else {
              object = w.FPDFPageObj_CreateNewPath(coords[c], coords[c + 1]);
              if (!object) fail('FPDFPageObj_CreateNewPath failed');
            }
            c += 2;
            break;
          case LINE_TO:
            w.FPDFPath_LineTo(open(v), coords[c], coords[c + 1]);
            c += 2;
            break;
          case CUBIC_TO:
            w.FPDFPath_BezierTo(open(v), coords[c], coords[c + 1], coords[c + 2], coords[c + 3], coords[c + 4], coords[c + 5]);
            c += 6;
            break;
          case CLOSE:
            w.FPDFPath_Close(open(v));
            break;
          case END_OBJECT: {
            const path = open(v);
            if (c >= coords.length) fail('verb ' + v + ': no paint index');
            const paint = Math.round(coords[c]);
            c += 1;
            const p = paint * PAINT_STRIDE;
            if (paint < 0 || p + PAINT_STRIDE > paints.length) fail('verb ' + v + ': paint ' + paint + ' missing');
            const r = Math.round(paints[p + 1]);
            const g = Math.round(paints[p + 2]);
            const b = Math.round(paints[p + 3]);
            const a = Math.round(paints[p + 4]);
            if (paints[p] === 1) {
              w.FPDFPageObj_SetStrokeColor(path, r, g, b, a);
              w.FPDFPageObj_SetStrokeWidth(path, paints[p + 5]);
              w.FPDFPageObj_SetLineCap(path, Math.round(paints[p + 6]));
              w.FPDFPageObj_SetLineJoin(path, Math.round(paints[p + 7]));
              w.FPDFPath_SetDrawMode(path, 0, 1);
            } else {
              w.FPDFPageObj_SetFillColor(path, r, g, b, a);
              w.FPDFPath_SetDrawMode(path, Math.round(paints[p + 9]), 0);
            }
            if (paints[p + 8] === 1) w.FPDFPageObj_SetBlendMode(path, multiply);
            w.FPDFPageObj_Transform(path, m[0], m[1], m[2], m[3], m[4], m[5]);
            object = 0;
            if (!w.FPDFPage_InsertObject(page, path)) {
              w.FPDFPageObj_Destroy(path);
              fail('FPDFPage_InsertObject failed');
            }
            break;
          }
          case IMAGE: {
            if (object) fail('verb ' + v + ': image inside an open path object');
            if (c + IMAGE_ARGS > coords.length) fail('verb ' + v + ': coords end early');
            const image = images[coords[c]];
            if (!image) fail('verb ' + v + ': image ' + coords[c] + ' missing');
            place(page, imageObject(job, page, image, v), coords, c + 1, m);
            c += IMAGE_ARGS;
            break;
          }
          case TEXT: {
            if (object) fail('verb ' + v + ': text inside an open path object');
            if (c + TEXT_ARGS > coords.length) fail('verb ' + v + ': coords end early');
            const text = texts[coords[c]];
            if (typeof text !== 'string') fail('verb ' + v + ': text ' + coords[c] + ' missing');
            const font = job.fonts.get(coords[c + 1]);
            if (!font) fail('verb ' + v + ': font ' + coords[c + 1] + ' not loaded');
            const textObject = textObjectOf(job, font, coords[c + 2], text, v);
            w.FPDFPageObj_SetFillColor(
              textObject,
              Math.round(coords[c + 3]),
              Math.round(coords[c + 4]),
              Math.round(coords[c + 5]),
              Math.round(coords[c + 6])
            );
            place(page, textObject, coords, c + 7, m);
            c += TEXT_ARGS;
            break;
          }
          default:
            fail('verb ' + v + ': unknown opcode ' + verbs[v]);
        }
        if (c > coords.length) fail('verb ' + v + ': coords end early');
      }
      if (object) fail('ops end inside an object');
      if (!w.FPDFPage_GenerateContent(page)) fail('FPDFPage_GenerateContent ' + outputIndex);
    } finally {
      if (object) w.FPDFPageObj_Destroy(object);
      w.FPDF_ClosePage(page);
    }
  }

  // ---- (2차) 6.2.5–6.2.7 fonts, image and text objects --------------------------------

  /** FPDFText_LoadFont(TrueType, cid) — PDFium copies the data; the wasm buffer is freed here. */
  function loadFont(job, fontId, buffer) {
    if (job.fonts.has(fontId)) fail('font ' + fontId + ' already loaded in this job');
    const w = wasm();
    const bytes = new Uint8Array(buffer);
    const ptr = w.malloc(Math.max(bytes.length, 1));
    if (!ptr) fail('font ' + fontId + ': out of memory');
    try {
      new Uint8Array(Pdfium.memory.buffer, ptr, bytes.length).set(bytes);
      const font = w.FPDFText_LoadFont(job.dst, ptr, bytes.length, FONT_TRUETYPE, 1);
      if (!font) fail('font ' + fontId + ': FPDFText_LoadFont failed');
      job.fonts.set(fontId, font);
    } finally {
      w.free(ptr);
    }
  }

  /** A new image object holding [image] (not inserted yet — the caller owns it). */
  function imageObject(job, page, image, v) {
    const w = wasm();
    const object = w.FPDFPageObj_NewImageObj(job.dst);
    if (!object) fail('verb ' + v + ': FPDFPageObj_NewImageObj failed');
    try {
      const pages = w.malloc(4);
      if (!pages) fail('out of memory');
      let ok = 0;
      try {
        new Int32Array(Pdfium.memory.buffer, pages, 1)[0] = page;
        ok = image.jpeg ? loadJpeg(pages, object, image) : setBitmap(pages, object, image);
      } finally {
        w.free(pages);
      }
      if (!ok) {
        fail('verb ' + v + ': loading a ' + (image.jpeg ? 'JPEG' : 'bitmap') + ' ' + image.width + 'x' + image.height + ' failed');
      }
      return object;
    } catch (e) {
      w.FPDFPageObj_Destroy(object);
      throw e;
    }
  }

  /** FPDF_FILEACCESS {m_FileLen, m_GetBlock, m_Param} (12 bytes in wasm32) over the JPEG bytes. */
  function loadJpeg(pages, object, image) {
    const w = wasm();
    const data = new Uint8Array(image.data);
    const access = w.malloc(12);
    if (!access) fail('out of memory');
    const getBlock = function (param, position, pBuf, size) {
      if (position + size > data.length) return 0;
      new Uint8Array(Pdfium.memory.buffer, pBuf, size).set(data.subarray(position, position + size));
      return 1;
    };
    const callback = Pdfium.addFunction(getBlock, 'iiiii');
    try {
      const fields = new Uint32Array(Pdfium.memory.buffer, access, 3);
      fields[0] = data.length;
      fields[1] = callback;
      fields[2] = 0;
      return w.FPDFImageObj_LoadJpegFileInline(pages, 1, object, access);
    } finally {
      Pdfium.removeFunction(callback);
      w.free(access);
    }
  }

  /** Straight RGBA → BGRA (BGRx without alpha) in wasm memory → FPDFImageObj_SetBitmap (copies). */
  function setBitmap(pages, object, image) {
    const w = wasm();
    const width = image.width;
    const height = image.height;
    const src = new Uint8Array(image.data);
    const length = width * height * 4;
    if (!(width > 0 && height > 0) || src.length !== length) {
      fail('bitmap: ' + src.length + ' B for ' + width + 'x' + height);
    }
    const ptr = w.malloc(length);
    if (!ptr) fail('bitmap ' + width + 'x' + height + ': out of memory');
    try {
      const dst = new Uint8Array(Pdfium.memory.buffer, ptr, length);
      for (let i = 0; i < length; i += 4) {
        dst[i] = src[i + 2];
        dst[i + 1] = src[i + 1];
        dst[i + 2] = src[i];
        dst[i + 3] = src[i + 3];
      }
      const bitmap = w.FPDFBitmap_CreateEx(width, height, image.hasAlpha ? BITMAP_BGRA : BITMAP_BGRX, ptr, width * 4);
      if (!bitmap) fail('FPDFBitmap_CreateEx ' + width + 'x' + height + ' failed');
      try {
        return w.FPDFImageObj_SetBitmap(pages, 1, object, bitmap);
      } finally {
        w.FPDFBitmap_Destroy(bitmap);
      }
    } finally {
      w.free(ptr);
    }
  }

  /** A new text object (not inserted yet): UTF-16 + NUL in wasm memory → FPDFText_SetText. */
  function textObjectOf(job, font, fontSize, text, v) {
    const w = wasm();
    const object = w.FPDFPageObj_CreateTextObj(job.dst, font, fontSize);
    if (!object) fail('verb ' + v + ': FPDFPageObj_CreateTextObj failed');
    try {
      const ptr = w.malloc((text.length + 1) * 2);
      if (!ptr) fail('out of memory');
      try {
        const units = new Uint16Array(Pdfium.memory.buffer, ptr, text.length + 1);
        for (let i = 0; i < text.length; i++) units[i] = text.charCodeAt(i);
        units[text.length] = 0;
        if (!w.FPDFText_SetText(object, ptr)) fail('verb ' + v + ': FPDFText_SetText failed');
      } finally {
        w.free(ptr);
      }
      return object;
    } catch (e) {
      w.FPDFPageObj_Destroy(object);
      throw e;
    }
  }

  /** The object's own matrix (coords[c..c+5]), then note → user [m], then onto the page. */
  function place(page, object, coords, c, m) {
    const w = wasm();
    try {
      w.FPDFPageObj_Transform(object, coords[c], coords[c + 1], coords[c + 2], coords[c + 3], coords[c + 4], coords[c + 5]);
      w.FPDFPageObj_Transform(object, m[0], m[1], m[2], m[3], m[4], m[5]);
      if (!w.FPDFPage_InsertObject(page, object)) fail('FPDFPage_InsertObject failed');
    } catch (e) {
      w.FPDFPageObj_Destroy(object);
      throw e;
    }
  }

  function jobOf(params) {
    const job = jobs.get(params.jobId);
    if (!job) fail('job ' + params.jobId + ' is not open');
    return job;
  }

  function addPages(params) {
    const job = jobOf(params);
    const multiply = StringUtils.allocateUTF8('Multiply');
    try {
      (params.pages || []).forEach(function (ops) {
        interpretPage(job, ops, multiply);
      });
    } finally {
      StringUtils.freeUTF8(multiply);
    }
    return { done: true };
  }

  function finish(params) {
    const job = jobOf(params);
    jobs.delete(params.jobId);
    try {
      // {result: {data}, transfer: [data]}: the worker posts the bytes without a copy.
      return encodePdf({ docHandle: job.dst, incremental: false, removeSecurity: false });
    } finally {
      release(job);
    }
  }

  function abort(params) {
    const job = jobs.get(params.jobId);
    if (job) {
      jobs.delete(params.jobId);
      release(job);
    }
    return {};
  }

  functions.pdfioComposeBegin = begin;
  functions.pdfioComposeAddPages = addPages;
  functions.pdfioComposeFinish = finish;
  functions.pdfioComposeAbort = abort;
  functions.pdfioComposeJobCount = function () {
    return { count: jobs.size };
  };
})();
