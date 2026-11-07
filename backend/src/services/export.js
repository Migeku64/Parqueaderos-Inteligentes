// Exportación de reportes a PDF y Excel (.xlsx) sin dependencias externas (RF19).
//  - PDF: documento tabular en hoja carta horizontal, con encabezado, filtros y paginación.
//  - XLSX: libro de Excel (Office Open XML) con encabezado en negrilla, filtros y panel fijo.
import zlib from 'node:zlib';

const ORG = 'Sistema de Gestión de Parqueaderos Comunitarios – Conjunto Residencial Nueva Castilla Etapa 3';
const TZ = 'America/Bogota';

// ---------------------------------------------------------------------------
// Formato de valores (igual para PDF y Excel)
// ---------------------------------------------------------------------------
const two = (n) => String(n).padStart(2, '0');

function fmtDateTime(d) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat('es-CO', {
      timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false,
    }).formatToParts(d).map((p) => [p.type, p.value]),
  );
  return `${parts.day}/${parts.month}/${parts.year} ${parts.hour === '24' ? '00' : parts.hour}:${parts.minute}`;
}

export function formatValue(v) {
  if (v === null || v === undefined || v === '') return '';
  if (v instanceof Date) return Number.isNaN(v.getTime()) ? '' : fmtDateTime(v);
  if (typeof v === 'boolean') return v ? 'Sí' : 'No';
  if (typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v)) {
    const [y, m, d] = v.split('-');
    return `${d}/${m}/${y}`;
  }
  if (typeof v === 'number') return Number.isInteger(v) ? String(v) : v.toFixed(2);
  if (typeof v === 'string' && /^-?\d+\.\d+$/.test(v)) return Number(v).toFixed(2);
  return String(v);
}

export function describeFilters(f = {}) {
  const out = [];
  if (f.from) out.push(`Desde ${formatValue(f.from)}`);
  if (f.to) out.push(`Hasta ${formatValue(f.to)}`);
  if (f.spot) out.push(`Celda ${String(f.spot).toUpperCase()}`);
  if (f.resident_id) out.push(`Residente #${f.resident_id}`);
  return out.length ? out.join(' · ') : 'Sin filtros';
}

// ---------------------------------------------------------------------------
// PDF
// ---------------------------------------------------------------------------
// Anchos de Helvetica (unidades de 1/1000 em) para los caracteres 32..126.
const HELV = [
  278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278, 556, 556, 556, 556, 556, 556, 556,
  556, 556, 556, 278, 278, 584, 584, 584, 556, 1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833,
  722, 778, 667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556, 333, 556, 556, 500, 556,
  556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556, 556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334,
  260, 334, 584,
];
const BASE = { á: 'a', é: 'e', í: 'i', ó: 'o', ú: 'u', Á: 'A', É: 'E', Í: 'I', Ó: 'O', Ú: 'U', ñ: 'n', Ñ: 'N', ü: 'u', Ü: 'U' };

function charWidth(ch, bold) {
  const b = BASE[ch] || ch;
  const c = b.charCodeAt(0);
  const w = c >= 32 && c <= 126 ? HELV[c - 32] : 556;
  return bold ? w * 1.06 : w;
}
function textWidth(s, size, bold = false) {
  let w = 0;
  for (const ch of s) w += charWidth(ch, bold);
  return (w * size) / 1000;
}
function fit(s, maxW, size, bold = false) {
  if (textWidth(s, size, bold) <= maxW) return s;
  let out = s;
  while (out.length > 1 && textWidth(out + '...', size, bold) > maxW) out = out.slice(0, -1);
  return out.trimEnd() + '...';
}

// Codifica a WinAnsi (cp1252) y escapa para cadenas literales de PDF.
const CP1252 = { '–': 0x96, '—': 0x97, '‘': 0x91, '’': 0x92, '“': 0x93, '”': 0x94, '•': 0x95, '€': 0x80, '…': 0x85 };
function pdfStr(s) {
  let out = '';
  for (const ch of s) {
    let code = CP1252[ch] ?? ch.charCodeAt(0);
    if (code > 255) code = 0x3f; // '?'
    const c = String.fromCharCode(code);
    out += c === '(' || c === ')' || c === '\\' ? '\\' + c : c;
  }
  return `(${out})`;
}

export function toPdf({ title, columns, rows, filters }) {
  const W = 792, H = 612, M = 36; // carta horizontal, márgenes de 0,5"
  const size = 8, rowH = 14, headH = 18;
  const usable = W - 2 * M;
  const cells = rows.map((r) => columns.map((c) => formatValue(r[c.key])));

  // Anchos de columna proporcionales al contenido
  const natural = columns.map((c, i) => {
    let w = textWidth(c.label, size, true);
    for (let k = 0; k < Math.min(cells.length, 400); k++) w = Math.max(w, textWidth(cells[k][i], size));
    return Math.min(w + 10, 260);
  });
  const total = natural.reduce((a, b) => a + b, 0);
  const widths = natural.map((w) => (w / total) * usable);

  const top = H - M;
  const firstY = top - 58; // espacio para título y datos del reporte
  const rowsFirst = Math.floor((firstY - headH - M - 20) / rowH);
  const rowsNext = Math.floor((top - headH - M - 20) / rowH);
  const pages = [];
  let idx = 0;
  do {
    const n = pages.length === 0 ? rowsFirst : rowsNext;
    pages.push(cells.slice(idx, idx + n));
    idx += n;
  } while (idx < cells.length);

  const generated = fmtDateTime(new Date());
  const streams = pages.map((pageRows, p) => {
    const ops = [];
    const text = (x, y, s, sz, bold = false, gray = 0) =>
      ops.push(`BT /${bold ? 'F2' : 'F1'} ${sz} Tf ${gray} g ${x.toFixed(2)} ${y.toFixed(2)} Td ${pdfStr(s)} Tj ET`);
    let y = top;
    if (p === 0) {
      text(M, y - 14, title, 15, true);
      text(M, y - 30, ORG, 8.5, false, 0.35);
      text(M, y - 43, `Generado: ${generated}   ·   Filtros: ${describeFilters(filters)}   ·   Registros: ${rows.length}`, 8.5, false, 0.35);
      y = firstY;
    } else {
      text(M, y - 10, `${title} (continuación)`, 10, true);
      y = top - 20;
    }
    // Encabezado de la tabla
    ops.push(`0.184 0.333 0.592 rg ${M} ${(y - headH).toFixed(2)} ${usable} ${headH} re f`);
    let x = M;
    columns.forEach((c, i) => {
      text(x + 4, y - headH + 6, fit(c.label, widths[i] - 8, size, true), size, true, 1);
      x += widths[i];
    });
    y -= headH;
    // Filas
    pageRows.forEach((r, k) => {
      if (k % 2 === 1) ops.push(`0.945 0.957 0.976 rg ${M} ${(y - rowH).toFixed(2)} ${usable} ${rowH} re f`);
      x = M;
      r.forEach((v, i) => {
        text(x + 4, y - rowH + 4.5, fit(v, widths[i] - 8, size), size);
        x += widths[i];
      });
      y -= rowH;
    });
    if (!rows.length) text(M + 4, y - 14, 'El reporte no tiene datos con los filtros seleccionados.', 9, false, 0.35);
    ops.push(`0.75 G 0.5 w ${M} ${(y).toFixed(2)} m ${W - M} ${(y).toFixed(2)} l S`);
    // Pie de página
    text(M, M - 14, ORG, 7, false, 0.45);
    const pg = `Página ${p + 1} de ${pages.length}`;
    text(W - M - textWidth(pg, 7), M - 14, pg, 7, false, 0.45);
    return ops.join('\n');
  });

  // Ensamblado de objetos PDF
  const objs = [];
  const add = (s) => objs.push(s) && objs.length;
  const catalog = add(null);
  const pagesId = add(null);
  const f1 = add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
  const f2 = add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>');
  const kids = [];
  for (const s of streams) {
    const data = zlib.deflateSync(Buffer.from(s, 'latin1'));
    const content = add({ dict: `<< /Length ${data.length} /Filter /FlateDecode >>`, data });
    kids.push(
      add(`<< /Type /Page /Parent ${pagesId} 0 R /MediaBox [0 0 ${W} ${H}] /Resources << /Font << /F1 ${f1} 0 R /F2 ${f2} 0 R >> >> /Contents ${content} 0 R >>`),
    );
  }
  objs[catalog - 1] = `<< /Type /Catalog /Pages ${pagesId} 0 R >>`;
  objs[pagesId - 1] = `<< /Type /Pages /Kids [${kids.map((k) => `${k} 0 R`).join(' ')}] /Count ${kids.length} >>`;
  const info = add(`<< /Title ${pdfStr(title)} /Producer ${pdfStr('Parqueadero Comunitario')} /CreationDate (D:${new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14)}Z) >>`);

  const chunks = [Buffer.from('%PDF-1.4\n%\xe2\xe3\xcf\xd3\n', 'latin1')];
  let offset = chunks[0].length;
  const xref = [];
  objs.forEach((o, i) => {
    xref.push(offset);
    const parts = typeof o === 'string'
      ? [Buffer.from(`${i + 1} 0 obj\n${o}\nendobj\n`, 'latin1')]
      : [Buffer.from(`${i + 1} 0 obj\n${o.dict}\nstream\n`, 'latin1'), o.data, Buffer.from('\nendstream\nendobj\n', 'latin1')];
    for (const b of parts) { chunks.push(b); offset += b.length; }
  });
  const xrefStr = `xref\n0 ${objs.length + 1}\n0000000000 65535 f \n${xref.map((o) => `${String(o).padStart(10, '0')} 00000 n \n`).join('')}`
    + `trailer\n<< /Size ${objs.length + 1} /Root ${catalog} 0 R /Info ${info} 0 R >>\nstartxref\n${offset}\n%%EOF\n`;
  chunks.push(Buffer.from(xrefStr, 'latin1'));
  return Buffer.concat(chunks);
}

// ---------------------------------------------------------------------------
// XLSX (Office Open XML) + ZIP mínimo
// ---------------------------------------------------------------------------
const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();
function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function zip(files) {
  const local = [];
  const central = [];
  let offset = 0;
  const now = new Date();
  const dosTime = (now.getHours() << 11) | (now.getMinutes() << 5) | (now.getSeconds() >> 1);
  const dosDate = ((now.getFullYear() - 1980) << 9) | ((now.getMonth() + 1) << 5) | now.getDate();
  for (const [name, content] of files) {
    const raw = Buffer.from(content, 'utf8');
    const data = zlib.deflateRawSync(raw);
    const nameBuf = Buffer.from(name, 'utf8');
    const crc = crc32(raw);
    const h = Buffer.alloc(30);
    h.writeUInt32LE(0x04034b50, 0); h.writeUInt16LE(20, 4); h.writeUInt16LE(0x0800, 6); h.writeUInt16LE(8, 8);
    h.writeUInt16LE(dosTime, 10); h.writeUInt16LE(dosDate, 12); h.writeUInt32LE(crc, 14);
    h.writeUInt32LE(data.length, 18); h.writeUInt32LE(raw.length, 22); h.writeUInt16LE(nameBuf.length, 26); h.writeUInt16LE(0, 28);
    local.push(h, nameBuf, data);
    const c = Buffer.alloc(46);
    c.writeUInt32LE(0x02014b50, 0); c.writeUInt16LE(20, 4); c.writeUInt16LE(20, 6); c.writeUInt16LE(0x0800, 8); c.writeUInt16LE(8, 10);
    c.writeUInt16LE(dosTime, 12); c.writeUInt16LE(dosDate, 14); c.writeUInt32LE(crc, 16); c.writeUInt32LE(data.length, 20);
    c.writeUInt32LE(raw.length, 24); c.writeUInt16LE(nameBuf.length, 28); c.writeUInt32LE(offset, 42);
    central.push(c, nameBuf);
    offset += h.length + nameBuf.length + data.length;
  }
  const centralBuf = Buffer.concat(central);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(files.length, 8); end.writeUInt16LE(files.length, 10);
  end.writeUInt32LE(centralBuf.length, 12); end.writeUInt32LE(offset, 16);
  return Buffer.concat([...local, centralBuf, end]);
}

const xml = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
  // elimina caracteres de control no válidos en XML
  .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, '');
function colName(i) {
  let s = '';
  for (let n = i + 1; n > 0; n = Math.floor((n - 1) / 26)) s = String.fromCharCode(65 + ((n - 1) % 26)) + s;
  return s;
}

export function toXlsx({ title, columns, rows, filters }) {
  const sheetRows = [];
  const cell = (ref, v, style = 0) => {
    if (typeof v === 'number' && Number.isFinite(v)) return `<c r="${ref}" s="${style}"><v>${v}</v></c>`;
    return `<c r="${ref}" t="inlineStr" s="${style}"><is><t xml:space="preserve">${xml(v)}</t></is></c>`;
  };
  sheetRows.push(`<row r="1">${cell('A1', title, 3)}</row>`);
  sheetRows.push(`<row r="2">${cell('A2', `${ORG} · Generado: ${fmtDateTime(new Date())} · Filtros: ${describeFilters(filters)}`, 4)}</row>`);
  const hr = 4;
  sheetRows.push(`<row r="${hr}">${columns.map((c, i) => cell(`${colName(i)}${hr}`, c.label, 1)).join('')}</row>`);
  rows.forEach((r, k) => {
    const n = hr + 1 + k;
    sheetRows.push(`<row r="${n}">${columns.map((c, i) => {
      const v = r[c.key];
      const isNum = typeof v === 'number' || (typeof v === 'string' && /^-?\d+(\.\d+)?$/.test(v) && !/^0\d/.test(v));
      return cell(`${colName(i)}${n}`, isNum ? Number(v) : formatValue(v), 2);
    }).join('')}</row>`);
  });
  const widths = columns.map((c) => {
    let w = c.label.length;
    for (const r of rows.slice(0, 500)) w = Math.max(w, formatValue(r[c.key]).length);
    return Math.min(Math.max(w + 2, 8), 50);
  });
  const last = `${colName(columns.length - 1)}${hr + rows.length}`;
  const sheet = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheetViews><sheetView workbookViewId="0"><pane ySplit="${hr}" topLeftCell="A${hr + 1}" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
<cols>${widths.map((w, i) => `<col min="${i + 1}" max="${i + 1}" width="${w}" customWidth="1"/>`).join('')}</cols>
<sheetData>${sheetRows.join('')}</sheetData>
<autoFilter ref="A${hr}:${last}"/>
</worksheet>`;
  const styles = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="4"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font><font><b/><sz val="14"/><name val="Calibri"/></font><font><i/><sz val="9"/><color rgb="FF595959"/><name val="Calibri"/></font></fonts>
<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF2F5597"/><bgColor indexed="64"/></patternFill></fill></fills>
<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"><color rgb="FFD9D9D9"/></left><right style="thin"><color rgb="FFD9D9D9"/></right><top style="thin"><color rgb="FFD9D9D9"/></top><bottom style="thin"><color rgb="FFD9D9D9"/></bottom><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="5"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"/><xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>`;
  const sheetName = xml(title.slice(0, 31).replace(/[\\/?*[\]:]/g, ' '));
  return zip([
    ['[Content_Types].xml', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>`],
    ['_rels/.rels', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>`],
    ['xl/workbook.xml', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="${sheetName}" sheetId="1" r:id="rId1"/></sheets><definedNames><definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">'${sheetName.replace(/'/g, "''")}'!$A$${hr}:$${colName(columns.length - 1)}$${hr + rows.length}</definedName></definedNames></workbook>`],
    ['xl/_rels/workbook.xml.rels', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>`],
    ['xl/worksheets/sheet1.xml', sheet],
    ['xl/styles.xml', styles],
  ]);
}
