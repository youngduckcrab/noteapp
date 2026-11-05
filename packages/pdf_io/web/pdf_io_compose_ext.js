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
//   pdfioComposeAddPages {jobId, pages: [{outputIndex, verbs, coords, paints}]} → {done}
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
  const PAINT_STRIDE = 10;
  const PLAN_STRIDE = 6;

  /** jobId → {dst, sources: [docHandle], buffers: [ptr], rows} */
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
    const job = { dst: 0, sources: [], buffers: [], rows: rows };
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
