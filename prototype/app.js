const $ = selector => document.querySelector(selector);
const esc = text => text.replace(/[&<>"']/g, char => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
})[char]);
const paths = {
  up: 'M3 9l5-5 5 5',
  down: 'M3 6l5 5 5-5',
  back: 'M10 3L5 8l5 5',
  forward: 'M3 8h10 M9 4l4 4-4 4',
  expand: 'M3 6V3h3 M10 3h3v3 M13 10v3h-3 M6 13H3v-3',
  removed: 'M3 8h10'
};
const icon = name => `<svg viewBox="0 0 16 16" aria-hidden="true"><path d="${paths[name]}"/></svg>`;
const reader = $('#reader');
const scheme = matchMedia('(prefers-color-scheme: dark)');
let data;
let files;
let current = 0;
let mode = 'stream';
let flow = 'Unstaged';
let savedAnchor = null;
let navigationTarget = null;
let pendingStreamRows = [];
let clean = false;
let live = false;
let theme = 'system';
let windows = [];
let activeWindow;
let nextWindow = 1;
let composing = false;
let emptyFolderStyle = 'leaf';
let hiddenItemStyle = 'muted';
const linesOf = text => text.replace(/\n$/, '').split('\n');
const dirty = file => file.full !== file.disk;
const dirtyMark = file => dirty(file) ? '<span class="unsaved" aria-label="Unsaved changes">●</span>' : '';

function appearance() {
  document.documentElement.dataset.theme = theme === 'system'
    ? (scheme.matches ? 'dark' : 'light') : theme;
  $('#appearance').textContent = theme[0].toUpperCase() + theme.slice(1);
}

function syntax(text) {
  const pattern = /("(?:[^"\\]|\\.)*"|`[^`]*`|\/\/.*$|\b(?:func|var|type|struct|if|else|return|for|range|nil|true|false|int|bool|string|package|import|switch|case|break|continue)\b|\b\d+\b)/g;
  return text.split(pattern).map(token => {
    const kind = /^("|`)/.test(token) ? 'str'
      : token.startsWith('//') ? 'comment'
      : /^\d+$/.test(token) ? 'num'
      : /^(func|var|type|struct|if|else|return|for|range|nil|true|false|int|bool|string|package|import|switch|case|break|continue)$/.test(token) ? 'kw' : '';
    return kind ? `<span class="${kind}">${esc(token)}</span>` : esc(token);
  }).join('');
}

function tokens(text, markdown = false) {
  let strong = false;
  let code = false;
  return text.split(markdown ? /(\*\*|`)/g : /($^)/).flatMap(part => {
    if (markdown && part === '**') { strong = !strong; return []; }
    if (markdown && part === '`') { code = !code; return []; }
    return (part.match(/\s+|[\p{L}\p{N}_]+|[^\s\p{L}\p{N}_]/gu) || [])
      .map(text => ({ text, strong, code }));
  });
}

function compareTokens(before, after, markdown = false) {
  const a = tokens(before, markdown);
  const b = tokens(after, markdown);
  const grid = Array.from({ length: a.length + 1 }, () => new Uint16Array(b.length + 1));
  for (let i = a.length - 1; i >= 0; i--) {
    for (let j = b.length - 1; j >= 0; j--) {
      grid[i][j] = a[i].text === b[j].text
        ? grid[i + 1][j + 1] + 1 : Math.max(grid[i + 1][j], grid[i][j + 1]);
    }
  }
  const merged = [];
  let i = 0;
  let j = 0;
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && a[i].text === b[j].text) {
      merged.push({ ...b[j++], change: '' });
      i++;
    } else if (i < a.length && (j === b.length || grid[i + 1][j] >= grid[i][j + 1])) {
      merged.push({ ...a[i++], change: 'del' });
    } else {
      merged.push({ ...b[j++], change: 'ins' });
    }
  }
  if (!markdown) return merged;
  const runs = [];
  for (const token of merged) {
    const equal = !token.change;
    if (runs.at(-1)?.equal === equal) runs.at(-1).tokens.push(token);
    else runs.push({ equal, tokens: [token] });
  }
  for (let i = 1; i < runs.length - 1; i++) {
    if (runs[i].equal && runs[i].tokens.filter(token => /[\p{L}\p{N}_]/u.test(token.text)).length < 4) {
      runs[i].equal = false;
    }
  }
  const result = [];
  let changed = [];
  const flush = () => {
    const before = changed.filter(token => token.change !== 'ins');
    const after = changed.filter(token => token.change !== 'del');
    const shared = token => ({ ...token, change: '' });
    while (before.length && after.length && /^\s+$/.test(before[0].text) && before[0].text === after[0].text) {
      before.shift();
      result.push(shared(after.shift()));
    }
    const trailing = [];
    while (before.length && after.length && /^\s+$/.test(before.at(-1).text) && before.at(-1).text === after.at(-1).text) {
      before.pop();
      trailing.unshift(shared(after.pop()));
    }
    result.push(...before.map(token => ({ ...token, change: 'del' })),
      ...after.map(token => ({ ...token, change: 'ins' })), ...trailing);
    changed = [];
  };
  for (const run of runs) {
    if (run.equal) { flush(); result.push(...run.tokens); }
    else changed.push(...run.tokens);
  }
  flush();
  return result;
}

function typeset(parts) {
  const groups = [];
  for (const token of parts) {
    const key = `${token.change}:${token.strong}:${token.code}`;
    if (groups.at(-1)?.key === key) groups.at(-1).text += token.text;
    else groups.push({ ...token, key });
  }
  return groups.map(group => {
    const raw = group.text;
    const leading = raw.match(/^\s*/)[0];
    const trailing = raw.match(/\s*$/)[0];
    const core = raw.trim();
    if (!core) return esc(raw);
    let content = esc(core);
    if (group.code) content = `<code>${content}</code>`;
    if (group.strong) content = `<strong>${content}</strong>`;
    if (group.change) content = `<${group.change}>${content}</${group.change}>`;
    return esc(leading) + content + esc(trailing);
  }).join('');
}

function inline(text) {
  return typeset(tokens(text, true).map(token => ({ ...token, change: '' })));
}

function decoratedCode(parts, side) {
  return parts.filter(part => !part.change || part.change === side).map(part => {
    const text = syntax(part.text);
    return part.change && part.text.trim() ? `<span class="word">${text}</span>` : text;
  }).join('');
}

function indent(text) {
  return text.match(/^\s*/)[0].replace(/\t/g, '    ').length;
}

function row(line, html, full = false) {
  const changed = line.type !== ' ';
  const kind = line.type === '-' ? 'del' : line.type === '+' ? 'add' : '';
  const modification = line.kind === 'modified' ? ' modified' : '';
  return `<div ${kind === 'del' ? 'contenteditable="false"' : ''} class="line ${kind}${modification}" data-change="${changed}" data-line="${line.new ?? 'old-' + line.old}" style="--indent:${indent(line.text)}">
    <span contenteditable="false" class="gutter-mark"></span>
    ${full ? '' : `<span contenteditable="false" class="ln">${line.old ?? ''}</span>`}
    <span contenteditable="false" class="ln">${line.new ?? ''}</span>
    <span class="source">${html ?? syntax(line.text)}</span>
  </div>`;
}

function codeRows(rows) {
  const decoration = new Map();
  for (let i = 0; i < rows.length; i++) {
    if (rows[i].type !== '-') continue;
    let end = i;
    while (end < rows.length && rows[end].type === '-') end++;
    let plus = end;
    while (plus < rows.length && rows[plus].type === '+') plus++;
    for (let k = 0; k < Math.min(end - i, plus - end); k++) {
      const compared = compareTokens(rows[i + k].text, rows[end + k].text);
      decoration.set(i + k, decoratedCode(compared, 'del'));
      decoration.set(end + k, decoratedCode(compared, 'ins'));
    }
    i = plus - 1;
  }
  return rows.map((line, i) => row({ ...line, showStage: rows[i - 1]?.type !== line.type || rows[i - 1]?.stage !== line.stage }, decoration.get(i))).join('');
}

function markdownBlocks(rows) {
  const blocks = [];
  let block = [];
  let fence = null;
  const flush = () => {
    if (block.length) blocks.push(block);
    block = [];
  };
  for (const line of rows) {
    const marker = line.text.match(/^(`{3,}|~{3,})/);
    if (fence) {
      block.push(line);
      if (marker && marker[1][0] === fence[0] && marker[1].length >= fence.length) {
        fence = null;
        flush();
      }
      continue;
    }
    if (marker) {
      flush();
      fence = marker[1];
      block.push(line);
    } else if (!line.text.trim()) {
      flush();
    } else if (/^#{1,6}\s/.test(line.text)) {
      flush();
      blocks.push([line]);
    } else {
      const list = /^\s*([-+*]|\d+[.)])\s+/.test(line.text);
      const table = line.text.trim().startsWith('|');
      if (list || (block.length && table !== block[0].text.trim().startsWith('|'))) flush();
      block.push(line);
    }
  }
  flush();
  return blocks;
}

function markdownBlock(lines) {
  const changed = lines.filter(line => line.type !== ' ');
  const stages = new Set(changed.map(line => line.stage));
  const state = stages.size === 1 ? [...stages][0] : 'partial';
  const first = lines[0].text;
  const heading = first.match(/^(#{1,6})\s+/);
  const list = first.match(/^\s*([-+*]|\d+[.)])\s+/);
  const fence = first.match(/^(`{3,}|~{3,})/);
  const strip = text => text.replace(heading ? /^#{1,6}\s+/ : list ? /^\s*([-+*]|\d+[.)])\s+/ : /$^/, '');
  const before = lines.filter(line => line.type !== '+').map(line => strip(line.text)).join(' ');
  const after = lines.filter(line => line.type !== '-').map(line => strip(line.text)).join(' ');
  let content = !changed.length ? inline(after) : before && after
    ? typeset(compareTokens(before, after, true))
    : typeset(tokens(after || before, true).map(token => ({ ...token, change: after ? 'ins' : 'del' })));
  let tag = heading ? 'h' + Math.min(heading[0].trim().length + 1, 4) : 'p';
  if (list) {
    tag = /^\d/.test(list[1]) ? 'ol' : 'ul';
    content = `<li>${content}</li>`;
  } else if (first.trim().startsWith('|')) {
    tag = 'table';
    content = '<tbody>' + lines.filter(line => !/^\s*\|[\s:|-]+\|\s*$/.test(line.text)).map(line => {
      const change = line.type === '+' ? 'ins' : line.type === '-' ? 'del' : '';
      return '<tr>' + line.text.split('|').slice(1, -1).map(cell => `<td>${change ? `<${change}>` : ''}${inline(cell.trim())}${change ? `</${change}>` : ''}</td>`).join('') + '</tr>';
    }).join('') + '</tbody>';
  } else if (fence) {
    tag = 'pre';
    const body = lines.slice(1, lines.at(-1).text.startsWith(fence[1]) ? -1 : undefined);
    content = '<code>' + body.map(line => {
      const change = line.type === '+' ? 'ins' : line.type === '-' ? 'del' : '';
      return `${change ? `<${change}>` : ''}${esc(line.text)}${change ? `</${change}>` : ''}`;
    }).join('\n') + '</code>';
  }
  return { tag, content, state, changed: changed.length > 0 };
}

function contextProse(lines) {
  return markdownBlocks(lines.map(text => ({ text, type: ' ' }))).map(lines => {
    const block = markdownBlock(lines);
    return `<${block.tag} class="prose-block">${block.content}</${block.tag}>`;
  }).join('');
}

function prose(hunk, file) {
  const chunks = markdownBlocks(hunk.rows);
  for (let i = chunks.length - 1; i > 0; i--) {
    if (chunks[i].some(line => line.type !== ' ') || chunks[i - 1].some(line => line.type !== ' ')) continue;
    const start = hunk.rows.indexOf(chunks[i - 1][0]);
    const end = hunk.rows.indexOf(chunks[i].at(-1));
    chunks.splice(i - 1, 2, hunk.rows.slice(start, end + 1));
  }
  const content = chunks.map(lines => {
    const block = markdownBlock(lines);
    if (!block.changed) {
      if (lines.length < 4) return `<div data-line="${lines.find(line => line.new)?.new || 1}">${contextProse(lines.map(line => line.text))}</div>`;
      return `<div class="prose-context"><button class="fold" data-prose="${esc(file.path)}:${lines.find(line => line.new)?.new || 1}" title="Expand unchanged lines" aria-expanded="false">
        <span class="fold-gutter">${icon('down')}</span><span>${lines.length} unchanged lines</span></button>
        <div class="expanded prose" data-line="${lines.find(line => line.new)?.new || 1}" hidden>${contextProse(lines.map(line => line.text))}</div></div>`;
    }
    const anchorRows = hunk.anchorRows || hunk.rows;
    const position = anchorRows.indexOf(lines[0]);
    const number = lines.find(line => line.new != null)?.new
      ?? anchorRows.slice(position).find(line => line.new != null)?.new
      ?? anchorRows.slice(0, position).findLast(line => line.new != null)?.new
      ?? Math.min(lines[0].old || 1, file.full.trimEnd().split('\n').length);
    const kind = lines.some(line => line.type === '+') ? 'add' : 'del';
    return `<div class="prose-row ${kind}"><span class="gutter-mark"></span><${block.tag} class="prose-block" data-line="${number}">${block.content}</${block.tag}></div>`;
  }).join('');
  return `<div class="prose">${content}</div>`;
}

function flowState() {
  return activeWindow.flows[flow];
}

function groupStatus(file, group) {
  const staged = group === 'Staged';
  const before = staged ? file.head : file.index;
  const after = staged ? file.index : file.full;
  const existed = staged ? file.headExists : file.indexExists;
  const exists = staged ? file.indexExists : file.workExists || dirty(file);
  if (file.renameGroup === group) return 'R';
  if (!existed && exists) return staged ? 'A' : 'U';
  if (existed && !exists) return 'D';
  return before !== after ? 'M' : '';
}

function streamFile(file) {
  const view = { ...file, head: flow === 'Staged' ? file.head : file.index,
    full: flow === 'Staged' ? file.index : file.full, status: groupStatus(file, flow) };
  recompute(view);
  return view;
}

function editable() {
  return mode === 'full' || flow === 'Unstaged';
}

function sidebar() {
  const changed = new Set();
  $('#files').innerHTML = ['Staged', 'Unstaged'].map(group => {
    const included = files.map((file, index) => ({ file, index, status: groupStatus(file, group) })).filter(item => item.status);
    return `<button class="group-heading ${!activeWindow.treeSelected && mode === 'stream' && flow === group ? 'active' : ''}" data-group="${group}" aria-current="${!activeWindow.treeSelected && mode === 'stream' && flow === group}">${group}</button>` + included.map(({ file, index, status }) => {
      changed.add(index);
      const name = file.path.split('/').pop();
      const directory = file.path.slice(0, Math.max(0, file.path.lastIndexOf('/')));
      const label = status === 'R'
        ? `<span class="rename-name"><span>${esc(file.oldPath)}</span>${icon('forward')}<span>${esc(file.path)}</span>${dirtyMark(file)}</span>`
        : `<span class="file-name">${esc(name)}${dirtyMark(file)}</span><span class="file-directory">${esc(directory)}</span>`;
      const changes = diffRows(group === 'Staged' ? file.head : file.index, group === 'Staged' ? file.index : file.full);
      const plus = changes.filter(line => line.type === '+').length;
      const minus = changes.filter(line => line.type === '-').length;
      return `<button class="file-row ${!activeWindow.treeSelected && mode === 'full' && index === current && flow === group ? 'active' : ''}" data-file="${index}" data-group="${group}" data-status="${status}" title="${esc(file.path)}">
        <span class="file-status">${status}</span><span class="file-label">${label}</span>
        <span class="counts"><span class="plus">${plus ? '+' + plus : ''}</span><span class="minus">${minus ? '−' + minus : ''}</span></span></button>`;
    }).join('');
  }).join('');
  $('#file-count').textContent = clean ? '0' : changed.size;
  $('#files').hidden = clean;
  $('#files').querySelectorAll('button').forEach(button => button.onclick = () => switchFlow(button.dataset.group,
    button.dataset.file === undefined ? null : +button.dataset.file));
  renderTree();
}

function fileHeader(file) {
  return `<div contenteditable="false" class="file-head" data-key="head" data-line="head"><span class="path"><span class="directory">${esc(file.path.slice(0, file.path.lastIndexOf('/') + 1))}</span>${esc(file.path.split('/').pop())}${dirtyMark(files.find(item => item.path === file.path) || file)}</span>
    <span class="status">${{ M: 'Modified', A: 'Added', U: 'Untracked', R: 'Renamed', D: 'Deleted' }[file.status] || ''}</span>
    <span class="counts">${file.plus ? `<span class="plus">+${file.plus}</span>` : ''}${file.minus ? `<span class="minus">−${file.minus}</span>` : ''}</span></div>`;
}

function fold(file, from, to) {
  if (to < from) return '';
  if (to - from + 1 < 4) {
    const lines = file.full.split('\n').slice(from - 1, to);
    return file.path.endsWith('.md') && flow === 'Staged' ? `<div class="prose" data-line="${from}">${contextProse(lines)}</div>` : `<div class="code-block" contenteditable="true" spellcheck="false" autocapitalize="off" autocorrect="off">${lines.map((text, i) => row({ text, type: ' ', old: file.context[from + i], new: from + i })).join('')}</div>`;
  }
  const key = `${file.path}:${from}:${to}`;
  return `<button class="fold" data-key="fold-${key}" data-fold="${key}" data-path="${file.path}" data-from="${from}" data-to="${to}"
    title="Expand unchanged lines" aria-expanded="false"><span class="fold-gutter">${icon('down')}</span><span>${to - from + 1} unchanged lines</span></button>
    <div class="expanded" data-key="expanded-${key}" hidden></div>`;
}

function section(file, index) {
  let prior = 1;
  const digits = Math.max(2, String(Math.max(file.full.split('\n').length, file.head.split('\n').length)).length);
  const head = fileHeader(file);
  const contents = file.status === 'R' && !file.hunks.length
    ? `<div class="rename"><span>${esc(file.oldPath)}</span>${icon('forward')}<span>${esc(file.path)}</span></div>`
    : file.hunks.map(original => {
      const hunk = { ...original, rows: [...original.rows], anchorRows: original.rows };
      if (file.path.endsWith('.md') && flow === 'Staged') {
        const blocks = markdownBlocks(hunk.rows);
        const first = blocks.findIndex(lines => lines.some(line => line.type !== ' '));
        const last = blocks.findLastIndex(lines => lines.some(line => line.type !== ' '));
        if (first >= 0) {
          const start = hunk.rows.indexOf(blocks[first][0]);
          const end = hunk.rows.indexOf(blocks[last].at(-1));
          hunk.rows = hunk.rows.slice(start, end + 1);
        }
      }
      const numbered = hunk.rows.filter(line => line.new != null);
      const deletion = original.rows.indexOf(hunk.rows[0]);
      const start = numbered[0]?.new
        ?? original.rows.slice(deletion).find(line => line.new != null)?.new
        ?? original.rows.slice(0, deletion).findLast(line => line.new != null)?.new
        ?? prior;
      const gap = fold(file, prior, start - 1);
      prior = numbered.length ? Math.max(...numbered.map(line => line.new)) + 1 : start;
      return `${gap}<div class="hunk" id="${hunk.id}" data-key="${hunk.id}" data-stage="${hunk.stage}">
        ${file.path.endsWith('.md') && flow === 'Staged' ? prose(hunk, file) : `<div class="code-block" contenteditable="true" spellcheck="false" autocapitalize="off" autocorrect="off">${codeRows(hunk.rows)}</div>`}</div>`;
    }).join('') + (file.full === '' ? `<div class="code-block" contenteditable="true" spellcheck="false">${row({ text: '', type: ' ', new: 1 })}</div>` : fold(file, prior, linesOf(file.full).length));
  return `<section class="file-section" id="file-${index}" data-index="${index}" style="--digits:${digits}">${head}<div class="file-body" ${flowState().collapsedFiles.has(file.path) ? 'hidden' : ''}>${flow === 'Unstaged' ? conflict(files[index]) : ''}${contents}</div></section>`;
}

function bind() {
  $('#stream').querySelectorAll('[data-fold], [data-prose]').forEach(button => {
    const key = button.dataset.fold || button.dataset.prose;
    button.onclick = () => {
      const area = button.nextElementSibling;
      const open = area.hidden;
      if (open && button.dataset.fold) {
        const file = streamFile(files.find(file => file.path === button.dataset.path));
        const lines = file.full.split('\n').slice(+button.dataset.from - 1, +button.dataset.to);
        area.innerHTML = file.path.endsWith('.md') && flow === 'Staged' ? `<div class="prose" data-line="${button.dataset.from}">${contextProse(lines)}</div>` : `<div class="code-block" contenteditable="true" spellcheck="false" autocapitalize="off" autocorrect="off">${lines.map((text, i) => {
            const number = +button.dataset.from + i;
            return row({ text, type: ' ', old: file.context[number], new: number });
          }).join('')}</div>`;
      }
      if (flow === 'Staged') area.querySelectorAll('[contenteditable]').forEach(element => element.contentEditable = 'false');
      area.hidden = !open;
      button.title = `${open ? 'Collapse' : 'Expand'} unchanged lines`;
      button.setAttribute('aria-expanded', String(open));
      if (open) flowState().expanded.add(key);
      else flowState().expanded.delete(key);
    };
    if (flowState().expanded.has(key) && button.nextElementSibling.hidden) button.onclick();
  });
}

function render() {
  $('#stream').innerHTML = files.map((file, index) => groupStatus(file, flow) ? section(streamFile(file), index) : '').join('');
  bind();
  $('#stream').querySelectorAll('.file-head').forEach(head => head.onclick = () => {
    const section = head.closest('section');
    const file = files[+section.dataset.index];
    const body = $('#file-' + files.indexOf(file)).querySelector('.file-body');
    body.hidden = !body.hidden;
    if (body.hidden && body.contains(getSelection().anchorNode)) clearSelection();
    if (body.hidden) flowState().collapsedFiles.add(file.path);
    else flowState().collapsedFiles.delete(file.path);
  });
  if (flow === 'Staged') $('#stream').querySelectorAll('[contenteditable]').forEach(element => element.contentEditable = 'false');
  sidebar();
  const empty = !$('#stream').children.length;
  $('#empty').textContent = clean ? 'No changes. A little room to think.' : `No ${flow.toLowerCase()} changes.`;
  $('#empty').hidden = mode !== 'stream' || (!empty && !clean);
  $('#stream').hidden = mode !== 'stream' || clean;
}

let scrollFrame = 0;
let viewFade = null;

function stopScroll() {
  cancelAnimationFrame(scrollFrame);
  scrollFrame = 0;
  navigationTarget = null;
}

function scrollToPosition(top) {
  cancelAnimationFrame(scrollFrame);
  const start = reader.scrollTop;
  const target = Math.max(0, Math.min(reader.scrollHeight - reader.clientHeight, top));
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) {
    reader.scrollTo({ top: target, behavior: 'instant' });
    scrollFrame = 0;
    return;
  }
  const began = performance.now();
  const bezier = (t, a, b) => 3 * (1 - t) ** 2 * t * a + 3 * (1 - t) * t ** 2 * b + t ** 3;
  const tick = now => {
    const progress = Math.min(1, (now - began) / 380);
    let low = 0;
    let high = 1;
    for (let i = 0; i < 16; i++) {
      const mid = (low + high) / 2;
      if (bezier(mid, .22, .2) < progress) low = mid;
      else high = mid;
    }
    const eased = progress === 1 ? 1 : bezier((low + high) / 2, .8, 1);
    reader.scrollTo({ top: start + (target - start) * eased, behavior: 'instant' });
    scrollFrame = progress < 1 ? requestAnimationFrame(tick) : 0;
  };
  scrollFrame = requestAnimationFrame(tick);
}

function scrollToEl(element) {
  if (!element) return;
  navigationTarget = element;
  scrollToPosition(element.getBoundingClientRect().top - reader.getBoundingClientRect().top + reader.scrollTop);
}

function beginViewFade() {
  viewFade?.remove();
  reader.getAnimations().forEach(animation => animation.cancel());
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) return null;
  const rect = reader.getBoundingClientRect();
  const snapshot = reader.cloneNode(false);
  snapshot.append((mode === 'full' ? $('#fullfile') : $('#stream')).cloneNode(true));
  snapshot.removeAttribute('id');
  snapshot.querySelectorAll('[id]').forEach(element => {
    if (element.id === 'fullfile') element.classList.add('snapshot-full');
    element.removeAttribute('id');
  });
  snapshot.className = 'view-fade';
  snapshot.inert = true;
  snapshot.setAttribute('aria-hidden', 'true');
  Object.assign(snapshot.style, { left: rect.left + 'px', top: rect.top + 'px', width: rect.width + 'px', height: rect.height + 'px' });
  document.body.append(snapshot);
  snapshot.scrollTop = reader.scrollTop;
  viewFade = snapshot;
  return snapshot;
}

function finishViewFade(snapshot) {
  if (!snapshot) return;
  const options = { duration: 180, easing: 'linear' };
  reader.animate([{ opacity: 0 }, { opacity: 1 }], options);
  snapshot.animate([{ opacity: 1 }, { opacity: 0 }], options).finished.then(() => {
    snapshot.remove();
    if (viewFade === snapshot) viewFade = null;
  });
}

function deletionMarker(number) {
  return `<div class="deletion-boundary" data-change-block data-boundary="${number}"><span class="deletion-marker" role="img" aria-label="Deleted lines">${icon('removed')}</span></div>`;
}

function captureAnchor(scope, mapDeletion = false) {
  const viewport = reader.getBoundingClientRect();
  const rows = [...(scope?.querySelectorAll('.file-head, .line, .prose-block[data-line]') || [])].filter(row => row.getClientRects().length);
  let anchor = rows.find(row => row.getBoundingClientRect().bottom > viewport.top);
  if (!anchor) return null;
  if (mapDeletion && anchor.dataset.line.startsWith('old-')) {
    const position = rows.indexOf(anchor);
    anchor = rows.slice(position + 1).find(row => !row.dataset.line.startsWith('old-'))
      || rows.slice(0, position).findLast(row => !row.dataset.line.startsWith('old-'));
  }
  return anchor ? { element: anchor, file: anchor.closest('.file-section')?.dataset.index,
    line: anchor.dataset.line, top: anchor.getBoundingClientRect().top } : null;
}

function readingAnchor(index) {
  return captureAnchor(mode === 'full' ? $('#fullfile') : $('#file-' + index), true);
}

function openFile(index = current) {
  if (clean && !activeWindow.treeSelected) return;
  clearSelection();
  const fading = mode === 'stream' ? beginViewFade() : null;
  const anchor = readingAnchor(index);
  if (mode === 'stream') savedAnchor = captureAnchor($('#stream'));
  stopScroll();
  current = index;
  mode = 'full';
  const file = files[index];
  const additions = new Map();
  const deletions = new Set();
  for (const hunk of file.hunks) {
    for (let i = 0; i < hunk.rows.length; i++) {
      const line = hunk.rows[i];
      if (line.type === '+') additions.set(line.new, line);
      if (line.type !== '-') continue;
      while (i < hunk.rows.length && hunk.rows[i].type === '-') i++;
      const boundary = hunk.rows.slice(i).find(line => line.new !== null)?.new ?? file.full.split('\n').length;
      deletions.add(boundary);
      i--;
    }
  }
  const contents = file.full.split('\n').map((text, i) => {
    const number = i + 1;
    const line = !clean && !activeWindow.single && !activeWindow.folder && additions.get(number) || { text, type: ' ', new: number };
    const start = line.type === '+' && !additions.has(number - 1) && !deletions.has(number);
    const rendered = row(line, undefined, true).replace('<div ', `<div ${start ? 'data-change-block ' : ''}`);
    return (!clean && !activeWindow.single && !activeWindow.folder && deletions.has(number) ? deletionMarker(number) : '') + rendered;
  }).join('');
  $('#fullfile').style.setProperty('--digits', String(file.full.split('\n').length).length);
  $('#fullfile').innerHTML = `${activeWindow.single ? '' : fileHeader(activeWindow.folder || clean ? { ...file, status: '', plus: 0, minus: 0 } : streamFile(file))}
    ${conflict(file)}<div class="code-block" contenteditable="true" spellcheck="false" autocapitalize="off" autocorrect="off">${contents}</div>`;
  $('#stream').hidden = true;
  $('#empty').hidden = true;
  $('#fullfile').hidden = false;
  $('#back').hidden = false;
  $('#full').hidden = true;

  titleBar();
  const target = anchor && $('#fullfile').querySelector(`[data-line="${anchor.line}"]`);
  reader.scrollTo({ top: target ? reader.scrollTop + target.getBoundingClientRect().top - anchor.top : 0, behavior: 'instant' });
  window.lastOpenProof = { line: anchor?.line, before: anchor?.top, after: target?.getBoundingClientRect().top };
  sidebar();
  finishViewFade(fading);
}

function back() {
  if (mode !== 'full' || activeWindow.folder) return;
  activeWindow.treeSelected = false;
  clearSelection();
  const fading = beginViewFade();
  stopScroll();
  mode = 'stream';
  render();
  $('#stream').hidden = clean;
  $('#fullfile').hidden = true;
  $('#back').hidden = true;
  $('#full').hidden = clean;

  titleBar();
  navigationTarget = null;
  const anchor = savedAnchor?.element.isConnected ? savedAnchor.element
    : savedAnchor && $(`#file-${savedAnchor.file} [data-line="${savedAnchor.line}"]`);
  if (anchor) reader.scrollTo({ top: reader.scrollTop + anchor.getBoundingClientRect().top - savedAnchor.top, behavior: 'instant' });
  window.lastBackProof = { line: savedAnchor?.line, before: savedAnchor?.top, after: anchor?.getBoundingClientRect().top };
  cueRows($('#file-0'), pendingStreamRows);
  pendingStreamRows = [];
  finishViewFade(fading);
}

function change(direction) {
  if (clean) return;
  const all = [...document.querySelectorAll(mode === 'full' ? '#fullfile [data-change-block]' : '#stream .hunk')].filter(element => element.getClientRects().length);
  const top = reader.getBoundingClientRect().top;
  const prior = all.indexOf(navigationTarget);
  const element = prior >= 0 ? all[prior + direction] : direction > 0 ? all.find(element => element.getBoundingClientRect().top > top + 8)
    : all.filter(element => element.getBoundingClientRect().top < top - 8).pop();
  if (!element) return;
  if (mode === 'stream') {
    current = +element.closest('section').dataset.index;
    sidebar();
  }
  scrollToEl(element);
}

function reconcile(original, replacement) {
  const previous = new Map([...original.children].map(element => [element.dataset.key, element]));
  const retained = [];
  for (const incoming of [...replacement.children]) {
    const old = previous.get(incoming.dataset.key);
    const expanded = old?.classList.contains('expanded');
    const foldState = old?.hasAttribute('data-fold');
    const same = old && (old.outerHTML === incoming.outerHTML || expanded || foldState);
    retained.push(same ? old : incoming);
  }
  original.replaceChildren(...retained);
}

function cueRows(scope, rows) {
  rows.forEach(line => {
    const element = scope.querySelector(`[data-line="${line.new ?? 'old-' + line.old}"][data-change="true"]`);
    if (!element) return;
    element.classList.remove('updated');
    void element.offsetWidth;
    element.classList.add('updated');
  });
}

function update() {
  if (activeWindow.single || activeWindow.folder) return;
  stopScroll();
  const file = files.find(file => file.path === activeWindow.agentData?.updated.path) || files[0];
  activeWindow.updates = (activeWindow.updates || 0) + 1;
  const incoming = activeWindow.agentData
    ? (activeWindow.updates % 2 ? activeWindow.agentData.updated.full : activeWindow.agentData.initial)
    : file.disk + '\n';
  const unsaved = dirty(file);
  file.disk = incoming;
  if (unsaved) file.conflict = file.full !== incoming;
  else { file.full = incoming; file.conflict = false; recompute(file); }
  if (!unsaved) activeWindow.flows.Unstaged.collapsedFiles.delete(file.path);
  if (activeWindow.agentData && !live) { files.push(initialize(structuredClone(activeWindow.agentData.live))); live = true; }
  refresh();
}

function toggleClean() {
  stopScroll();
  if (mode === 'full') back();
  clean = !clean;
  $('#stream').hidden = clean;
  $('#empty').hidden = !clean;
  reader.classList.toggle('clean', clean);
  $('#full').hidden = clean;
  $('#prev').disabled = clean;
  $('#next').disabled = clean;
  $('#clean').textContent = clean ? 'Restore changes' : 'Clean state';
  sidebar();
}

$('#prev').innerHTML = icon('up');
$('#next').innerHTML = icon('down');
$('#full').innerHTML = icon('expand');
$('#back').innerHTML = icon('back');
$('#prev').onclick = () => change(-1);
$('#next').onclick = () => change(1);
$('#full').onclick = () => openFile();
$('#back').onclick = back;
$('#simulate').onclick = update;
$('#clean').onclick = toggleClean;
$('#appearance').onclick = () => {
  theme = theme === 'system' ? 'light' : theme === 'light' ? 'dark' : 'system';
  appearance();
};
scheme.addEventListener('change', appearance);
appearance();


let frame = false;
['wheel', 'pointerdown', 'touchstart'].forEach(type => reader.addEventListener(type, stopScroll, { passive: true }));
reader.addEventListener('scroll', () => {
  if (frame || mode !== 'stream' || clean) return;
  frame = true;
  requestAnimationFrame(() => {
    const top = reader.getBoundingClientRect().top + 64;
    const active = navigationTarget?.closest('.file-section') || [...$('#stream').querySelectorAll('section')]
      .filter(section => section.getBoundingClientRect().top <= top).pop();
    if (active && current !== +active.dataset.index) {
      current = +active.dataset.index;
      sidebar();
    }
    frame = false;
  });
});

fetch('data.json').then(response => {
  if (!response.ok) throw Error('Data unavailable');
  return response.json();
}).then(result => {
  data = result;
  windows = [makeDemoWindow(), makeFolderWindow(), makeWindow('combe', 'combe', 'main', [sample('src/main.rs', 'fn main() {\n    println!("combe");\n}\n', 'fn main() {\n    println!("hello");\n}\n')]), makeWindow('spale', 'prototype-editing', 'feat/prototype-editing', [sample('prototype.txt', 'spale\nRead and edit working changes.\n', 'spale\nRead working changes.\n')]), makeWindow('notes.txt', '', '', [sample('notes.txt', 'A small place to write.\n')], true)];
  activateWindow(windows[0].id);
  document.documentElement.dataset.ready = 'true';
}).catch(error => {
  $('#empty').hidden = false;
  $('#empty').textContent = 'Changes could not be loaded.';
  console.error(error);
});

function diffRows(before, after) {
  const a = before.match(/[^\n]*\n|[^\n]+$/g) || [];
  const b = after.match(/[^\n]*\n|[^\n]+$/g) || [];
  let prefix = 0;
  while (prefix < a.length && prefix < b.length && a[prefix] === b[prefix]) prefix++;
  let endA = a.length;
  let endB = b.length;
  while (endA > prefix && endB > prefix && a[endA - 1] === b[endB - 1]) { endA--; endB--; }
  const grid = Array.from({ length: endA - prefix + 1 }, () => new Uint16Array(endB - prefix + 1));
  for (let i = endA - 1; i >= prefix; i--) {
    for (let j = endB - 1; j >= prefix; j--) {
      grid[i - prefix][j - prefix] = a[i] === b[j] ? grid[i - prefix + 1][j - prefix + 1] + 1
        : Math.max(grid[i - prefix + 1][j - prefix], grid[i - prefix][j - prefix + 1]);
    }
  }
  const rows = [];
  let i = 0;
  let j = 0;
  const equal = () => { rows.push({ type: ' ', text: b[j].replace(/\n$/, ''), old: i + 1, new: j + 1 }); i++; j++; };
  while (i < prefix) equal();
  while (i < endA || j < endB) {
    if (i < endA && j < endB && a[i] === b[j]) equal();
    else if (i < endA && (j === endB || grid[i - prefix + 1][j - prefix] >= grid[i - prefix][j - prefix + 1])) {
      rows.push({ type: '-', text: a[i].replace(/\n$/, ''), old: ++i, new: null, boundary: j });
    } else rows.push({ type: '+', text: b[j].replace(/\n$/, ''), old: null, new: ++j, boundary: i });
  }
  while (i < a.length) equal();
  return rows;
}

function recompute(file) {
  const rows = diffRows(file.head, file.full);
  const staged = diffRows(file.head, file.index);
  const indexed = diffRows(file.index, file.full);
  const sameIndex = new Set(indexed.filter(row => row.type === ' ').map(row => row.new));
  const deleted = new Set(staged.filter(row => row.type === '-').map(row => row.old));
  file.context = {};
  file.plus = 0;
  file.minus = 0;
  const ranges = [];
  rows.forEach((row, i) => {
    if (row.type === ' ') { file.context[row.new] = row.old; return; }
    row.stage = row.type === '-' ? (deleted.has(row.old) ? 'full' : 'none') : (sameIndex.has(row.new) ? 'full' : 'none');
    if (row.type === '+') file.plus++; else file.minus++;
    const start = Math.max(0, i - 3);
    const end = Math.min(rows.length, i + 4);
    if (ranges.length && ranges.at(-1)[1] >= start) ranges.at(-1)[1] = end;
    else ranges.push([start, end]);
  });
  file.hunks = ranges.map(([start, end]) => ({ id: file.path.replaceAll('/', '-') + '-h' + start, rows: rows.slice(start, end) }));
  const marks = new Set(rows.filter(row => row.type !== ' ').map(row => row.stage));
  file.stage = marks.size > 1 ? 'partial' : [...marks][0] || 'none';
  file.hunks.forEach(hunk => {
    const marks = new Set(hunk.rows.filter(row => row.type !== ' ').map(row => row.stage));
    hunk.stage = marks.size > 1 ? 'partial' : [...marks][0] || 'none';
  });
}

function initialize(file) {
  file.headExists ??= !!file.head;
  file.indexExists ??= !!file.index;
  file.workExists ??= !!file.full;
  if (file.status === 'R') file.renameGroup ??= 'Staged';
  file.disk = file.full;
  file.undo = [];
  file.redo = [];
  return file;
}

function sample(path, full, head = '') {
  const file = { path, full, head, index: head, status: head ? 'M' : 'A', hunks: [] };
  recompute(file);
  return file;
}

function makeWindow(repo, worktree, branch, source, single = false) {
  return { id: nextWindow++, repo, worktree, branch, single, files: structuredClone(source).map(initialize),
    current: 0, mode: single ? 'full' : 'stream', collapsed: false, flow: 'Unstaged', flows: { Unstaged: makeFlow(single), Staged: makeFlow(false) }, clean: false, live: false };
}

function makeDemoWindow(worktree = data.repo, branch = 'main') {
  const win = makeWindow(data.repo, worktree, branch, data.files);
  win.agentData = { updated: data.updated, live: data.live, initial: data.files.find(file => file.path === data.updated.path).full };
  win.directories = data.treeDirectories;
  for (const item of data.treeFiles) {
    if (!win.files.some(file => file.path === item.path)) win.files.push(initialize(sample(item.path, item.full, item.full)));
  }
  return win;
}

function makeFolderWindow() {
  const win = makeWindow('Harbor', 'Harbor', '', data.folderFiles.map(item => sample(item.path, item.full, item.full)));
  win.folder = true;
  win.directories = data.folderDirectories;
  win.treeSelected = true;
  win.flows.Unstaged.mode = 'full';
  return win;
}

function windowLabel(win) {
  return win.single ? win.files[0].path : win.repo + (win.worktree !== win.repo ? '/' + win.worktree : '');
}

function windowBar() {
  $('#windows').innerHTML = windows.map(win => `<button data-window="${win.id}" class="${win === activeWindow ? 'active' : ''}" aria-current="${win === activeWindow}">${esc(windowLabel(win))}${win.files.some(dirty) ? '<span class="unsaved" aria-label="Unsaved changes">●</span>' : ''}</button>`).join('');
  $('#windows').querySelectorAll('button').forEach(button => button.onclick = () => activateWindow(+button.dataset.window));
}

function makeFlow(single) {
  return { current: 0, mode: single ? 'full' : 'stream', expanded: new Set(), collapsedFiles: new Set() };
}

function titleBar() {
  const win = activeWindow;
  $('#workspace').innerHTML = `<span>${esc(win.single ? win.files[0].path : win.repo + (win.worktree !== win.repo ? ' › ' + win.worktree : ''))}${win.files.some(dirty) ? '<span class="unsaved" aria-label="Unsaved changes">●</span>' : ''}</span>${win.single || win.folder ? '' : `<span class="branch">${esc(win.branch)}</span>`}`;
  document.title = 'spale · ' + windowLabel(win);
  reader.setAttribute('aria-label', win.folder ? 'Full file' : 'Continuous changes');
  $('.window').classList.toggle('sidebar-collapsed', win.collapsed || win.single);
  $('.window').classList.toggle('single-file', win.single);
  $('#back').hidden = mode !== 'full' || win.single || win.folder;
  $('#full').hidden = mode === 'full' || clean || win.single || win.folder || !$('#stream').children.length;
  $('#prev').hidden = $('#next').hidden = !!win.folder || win.single;
  $('#simulate').disabled = win.single || win.folder;
  $('#stage').disabled = win.single || win.folder;
  $('#clean').disabled = win.single || win.folder;
  $('#context-choice').textContent = win.folder ? 'Plain folder' : 'Git repository';
  $('.window').classList.toggle('folder-window', !!win.folder);
  updateSidebarLayout();
}

function storeFlow() {
  Object.assign(flowState(), { current, mode, savedAnchor,
    anchor: captureAnchor(mode === 'full' ? $('#fullfile') : $('#stream')),
    caret: selectionRange() });
}

function restoreFlow() {
  const state = flowState();
  current = state.current;
  mode = state.mode;
  savedAnchor = state.savedAnchor;
  stopScroll();
  render();
  $('#fullfile').hidden = mode !== 'full';
  reader.classList.toggle('clean', clean);
  if (mode === 'full') openFile(current);
  restoreReadingAnchor(state.anchor);
  if (state.caret && mode === 'stream' && !groupStatus(state.caret.file, flow)) openFile(files.indexOf(state.caret.file));
  if (state.caret && editable()) restoreCaret(state.caret.file, state.caret.start);
  $('#clean').textContent = clean ? 'Restore changes' : 'Clean state';
  $('#prev').disabled = $('#next').disabled = clean;
  titleBar();
  windowBar();
}

function switchFlow(group, index = null) {
  if (activeWindow.folder) return;
  activeWindow.treeSelected = false;
  const full = mode === 'full';
  if (group !== flow) {
    storeFlow();
    clearSelection();
    flow = group;
    activeWindow.flow = flow;
    restoreFlow();
  }
  if (index !== null) {
    clearSelection();
    current = index;
    if (full || mode === 'full') openFile(index);
    else {
      render();
      scrollToEl($('#file-' + index));
    }
    sidebar();
  }
}

function activateWindow(id) {
  const target = windows.find(win => win.id === id);
  if (!target || target === activeWindow) return;
  if (activeWindow) {
    storeFlow();
    Object.assign(activeWindow, { flow, clean, live });
  }
  clearSelection();
  const fading = activeWindow ? beginViewFade() : null;
  activeWindow = target;
  files = target.files;
  flow = target.flow;
  clean = target.clean;
  live = target.live;
  restoreFlow();
  finishViewFade(fading);
}

function conflict(file) {
  return file.conflict ? `<div class="conflict" contenteditable="false"><span>文件已在磁盘上改变</span><button data-save="${esc(file.path)}">保存（覆盖磁盘）</button><button data-revert="${esc(file.path)}">还原（采用磁盘版本）</button></div>` : '';
}

function restoreReadingAnchor(anchor) {
  if (!anchor) { reader.scrollTop = 0; return; }
  const scope = mode === 'full' ? $('#fullfile') : $('#file-' + anchor.file);
  let row = scope?.querySelector(`[data-line="${anchor.line}"]`);
  if (!row) {
    const fold = [...(scope?.querySelectorAll('[data-fold]') || [])]
      .find(button => +button.dataset.from <= +anchor.line && +button.dataset.to >= +anchor.line);
    if (fold?.nextElementSibling.hidden) fold.click();
    row = scope?.querySelector(`[data-line="${anchor.line}"]`);
  }
  if (row) reader.scrollTop += row.getBoundingClientRect().top - anchor.top;
}

function refresh(caret = null) {
  const anchor = captureAnchor(mode === 'full' ? $('#fullfile') : $('#stream'));
  const scroll = reader.scrollTop;
  render();
  if (mode === 'full') openFile(current);
  const restored = anchor && (mode === 'full' ? $('#fullfile') : $('#file-' + anchor.file))?.querySelector(`[data-line="${anchor.line}"]`);
  reader.scrollTop = restored ? reader.scrollTop + restored.getBoundingClientRect().top - anchor.top : scroll;
  titleBar();
  windowBar();
  if (caret && mode === 'stream' && !groupStatus(caret.file, flow)) openFile(files.indexOf(caret.file));
  if (caret) restoreCaret(caret.file, caret.offset);
}

function point(node, offset) {
  const element = node?.nodeType === Node.TEXT_NODE ? node.parentElement : node;
  const source = element?.closest('.source');
  if (!editable() || !source || source.closest('.del') || !reader.contains(source)) return null;
  const line = source.closest('.line');
  const section = source.closest('.file-section');
  const file = files[mode === 'full' ? current : +section.dataset.index];
  const range = document.createRange();
  range.selectNodeContents(source);
  try { range.setEnd(node, offset); } catch { return null; }
  const start = linesOf(file.full).slice(0, +line.dataset.line - 1).reduce((sum, text) => sum + text.length + 1, 0);
  return { file, offset: start + Math.min(source.textContent.length, range.toString().length) };
}

function selectionRange() {
  const selection = getSelection();
  const a = point(selection.anchorNode, selection.anchorOffset);
  const b = point(selection.focusNode, selection.focusOffset);
  if (!a || !b || a.file !== b.file) return null;
  return { file: a.file, start: Math.min(a.offset, b.offset), end: Math.max(a.offset, b.offset) };
}

function restoreCaret(file, offset) {
  if (!editable()) return;
  const text = file.full.slice(0, offset);
  const number = text.split('\n').length;
  const column = text.length - text.lastIndexOf('\n') - 1;
  let scope = mode === 'full' ? $('#fullfile') : $('#file-' + files.indexOf(file));
  let source = scope?.querySelector(`[data-line="${number}"] .source`);
  if (!source && mode === 'stream') {
    const fold = [...scope.querySelectorAll('[data-fold]')].find(button => +button.dataset.from <= number && +button.dataset.to >= number);
    if (fold) fold.click();
    source = scope.querySelector(`[data-line="${number}"] .source`);
  }
  if (!source && file.full.endsWith('\n') && number === file.full.split('\n').length) {
    [...scope.querySelectorAll('.code-block')].at(-1)?.insertAdjacentHTML('beforeend', row({ text: '', type: ' ', new: number }));
    source = scope.querySelector(`[data-line="${number}"] .source`);
  }
  if (!source) return;
  source.closest('[contenteditable="true"]').focus({ preventScroll: true });
  const walker = document.createTreeWalker(source, NodeFilter.SHOW_TEXT);
  let remaining = column;
  let node;
  while ((node = walker.nextNode())) {
    if (remaining <= node.length) break;
    remaining -= node.length;
  }
  const range = document.createRange();
  if (node) range.setStart(node, remaining);
  else range.setStart(source, 0);
  range.collapse(true);
  getSelection().removeAllRanges();
  getSelection().addRange(range);
  current = files.indexOf(file);
  if (mode === 'stream') navigationTarget = $('#file-' + current);
}

function clearSelection() {
  if (document.activeElement?.isContentEditable) document.activeElement.blur();
  getSelection().removeAllRanges();
}

function replaceText(range, text, end = range.end) {
  if (!editable()) return;
  const file = range.file;
  file.undo.push({ text: file.full, offset: range.start });
  file.redo = [];
  file.full = file.full.slice(0, range.start) + text + file.full.slice(end);
  recompute(file);
  refresh({ file, offset: range.start + text.length });
}

function historyEdit(redo = false) {
  if (!editable()) return;
  const file = selectionRange()?.file || files[current];
  const source = redo ? file.redo : file.undo;
  const target = redo ? file.undo : file.redo;
  const state = source.pop();
  if (!state) return;
  target.push({ text: file.full, offset: selectionRange()?.start || 0 });
  file.full = state.text;
  recompute(file);
  refresh({ file, offset: state.offset });
}

function saveFile(file = selectionRange()?.file || files[current]) {
  const caret = selectionRange();
  if (activeWindow.untitled) {
    const name = prompt('文件名', file.path);
    if (!name?.trim()) return;
    file.path = name.trim();
    activeWindow.repo = file.path;
    activeWindow.untitled = false;
  }
  file.disk = file.full;
  file.conflict = false;
  refresh(caret ? { file, offset: caret.start } : null);
}

reader.addEventListener('pointerdown', event => {
  if (!editable()) return;
  if (event.target.closest('.del, del')) { event.preventDefault(); return; }
  if (event.target.closest('button')) return;
  const source = event.target.closest('.source');
  if (!source) return;
  const section = source.closest('.file-section');
  current = mode === 'full' ? current : +section.dataset.index;
});
reader.addEventListener('compositionstart', () => { composing = true; });
reader.addEventListener('compositionend', event => {
  composing = false;
  if (!editable()) return;
  const selection = getSelection();
  const source = (selection.focusNode?.parentElement)?.closest('.source');
  if (!source) return;
  const range = selectionRange();
  if (!range) return;
  const number = +source.closest('.line').dataset.line;
  const list = linesOf(range.file.full);
  const start = list.slice(0, number - 1).reduce((sum, text) => sum + text.length + 1, 0);
  replaceText({ file: range.file, start, end: start + list[number - 1].length }, source.textContent);
});
reader.addEventListener('beforeinput', event => {
  if (!editable()) { event.preventDefault(); return; }
  if (composing || event.isComposing) return;
  event.preventDefault();
  const range = selectionRange();
  if (!range) return;
  if (event.inputType === 'historyUndo' || event.inputType === 'historyRedo') { historyEdit(event.inputType === 'historyRedo'); return; }
  let text = event.data ?? '';
  if (event.inputType === 'insertParagraph' || event.inputType === 'insertLineBreak') {
    const prior = range.file.full.slice(0, range.start).split('\n').at(-1);
    text = '\n' + prior.match(/^[\t ]*/)[0];
  } else if (event.inputType.startsWith('delete')) {
    if (range.start === range.end) {
      if (event.inputType.includes('Backward')) range.start = Math.max(0, range.start - 1);
      else range.end = Math.min(range.file.full.length, range.end + 1);
    }
    text = '';
  } else if (!event.inputType.startsWith('insert')) return;
  replaceText(range, text);
});
reader.addEventListener('paste', event => {
  event.preventDefault();
  const range = selectionRange();
  if (range) replaceText(range, event.clipboardData.getData('text/plain').replace(/\r\n/g, '\n'));
});
reader.addEventListener('cut', event => {
  if (!editable()) { event.preventDefault(); return; }
  const range = selectionRange();
  if (!range || range.start === range.end) return;
  event.preventDefault();
  event.clipboardData.setData('text/plain', range.file.full.slice(range.start, range.end));
  replaceText(range, '');
});
reader.addEventListener('drop', event => event.preventDefault());
reader.addEventListener('click', event => {
  const save = event.target.closest('[data-save]');
  const revert = event.target.closest('[data-revert]');
  if (save) saveFile(files.find(file => file.path === save.dataset.save));
  if (revert) {
    const file = files.find(file => file.path === revert.dataset.revert);
    file.undo.push({ text: file.full, offset: 0 });
    file.redo = [];
    file.full = file.disk;
    file.conflict = false;
    recompute(file);
    refresh();
  }
});

document.addEventListener('keydown', event => {
  if (!activeWindow) return;
  const key = event.key.toLowerCase();
  if ((event.metaKey || event.ctrlKey) && !event.altKey) {
    if (key === 'b') {
      event.preventDefault();
      if (!activeWindow.single) { activeWindow.collapsed = !activeWindow.collapsed; titleBar(); }
    } else if (key === 's') { event.preventDefault(); saveFile(); }
    else if (key === 'z') { event.preventDefault(); historyEdit(event.shiftKey); }
    else if (key === 'l' && mode === 'full') {
      event.preventDefault();
      const line = Number(prompt('行号', '1'));
      if (!Number.isInteger(line) || line < 1) return;
      const file = files[current];
      const number = Math.min(line, linesOf(file.full).length);
      const offset = linesOf(file.full).slice(0, number - 1).reduce((sum, text) => sum + text.length + 1, 0);
      restoreCaret(file, offset);
      $('#fullfile').querySelector(`[data-line="${number}"]`)?.scrollIntoView({ block: 'center' });
    }
    return;
  }
  if (event.altKey || composing) return;
  if (['ArrowUp', 'ArrowDown', 'PageUp', 'PageDown', 'Home', 'End', ' '].includes(event.key)) stopScroll();
  if (event.key === 'Escape' && mode === 'full' && !activeWindow.single) {
    event.preventDefault();
    back();
  } else if (event.key === 'Tab' && reader.contains(event.target)) {
    const range = selectionRange();
    if (!range) return;
    event.preventDefault();
    const candidates = linesOf(range.file.full).map(line => line.match(/^(\t+| +)\S/)).filter(Boolean).map(match => match[1]);
    const indentation = candidates.some(value => value.startsWith('\t')) ? '\t' : candidates.sort((a, b) => a.length - b.length)[0] || '\t';
    replaceText(range, indentation);
  }
});

$('#open-window').onclick = () => {
  const win = makeDemoWindow('accounts-' + nextWindow, 'feat/accounts');
  windows.push(win);
  activateWindow(win.id);
};
$('#new-file').onclick = () => {
  const win = makeWindow('Untitled', '', '', [sample('Untitled', '')], true);
  win.untitled = true;
  windows.push(win);
  activateWindow(win.id);
  restoreCaret(win.files[0], 0);
};
$('#close-window').onclick = () => {
  const position = windows.indexOf(activeWindow);
  windows.splice(position, 1);
  clearSelection();
  activeWindow = null;
  if (windows.length) activateWindow(windows[Math.min(position, windows.length - 1)].id);
  else { files = []; $('#stream').replaceChildren(); $('#fullfile').replaceChildren(); $('#workspace').textContent = 'spale'; windowBar(); }
};

$('#stage').onclick = () => {
  if (activeWindow.single || activeWindow.folder) return;
  const file = files[current];
  file.index = file.disk;
  file.indexExists = file.workExists || !!file.disk;
  file.renameGroup = file.renameGroup === 'Unstaged' ? 'Staged' : file.renameGroup;
  file.untracked = false;
  activeWindow.flows.Staged.collapsedFiles.delete(file.path);
  clearSelection();
  recompute(file);
  refresh();
};

function updateSidebarLayout() {
  $('#changes-panel').hidden = !!activeWindow?.folder;
  $('#tree-panel').hidden = !!activeWindow?.single;
  const expanded = $('#tree-heading').getAttribute('aria-expanded') === 'true';
  $('#tree-body').classList.toggle('collapsed', !expanded);
  $('#tree-body').inert = !expanded;
}

function renderTree() {
  activeWindow.expandedFolders ??= new Set(['.github', '.vscode', 'Archive', 'build']);
  const root = { children: new Map() };
  const add = (path, index) => {
    let parent = root;
    path.split('/').forEach((name, depth, parts) => {
      if (!parent.children.has(name)) parent.children.set(name, { name, path: parts.slice(0, depth + 1).join('/'), children: new Map() });
      parent = parent.children.get(name);
      if (index !== undefined && depth === parts.length - 1) parent.index = index;
    });
  };
  (activeWindow.directories || []).forEach(path => add(path));
  files.forEach((file, index) => {
    if (file.workExists) add(file.path, index);
  });
  const children = (parent, depth = 0) => [...parent.children.values()]
    .sort((a, b) => {
      const folders = Number(b.index === undefined) - Number(a.index === undefined);
      const left = a.name.toLowerCase();
      const right = b.name.toLowerCase();
      return folders || (left < right ? -1 : left > right ? 1 : 0);
    })
    .map(node => {
      const folder = node.index === undefined;
      const empty = folder && node.children.size === 0;
      const expandable = folder && (!empty || emptyFolderStyle === 'message');
      const expanded = expandable && activeWindow.expandedFolders.has(node.path);
      const hidden = hiddenItemStyle === 'muted' && node.name.startsWith('.');
      const file = files[node.index];
      const attributes = folder
        ? expandable ? `data-folder="${esc(node.path)}" aria-expanded="${expanded}"` : 'aria-disabled="true"'
        : `data-tree-file="${node.index}"`;
      return `<div class="tree-node"><button class="tree-row ${hidden ? 'hidden-item' : ''} ${!folder && activeWindow.treeSelected && current === node.index ? 'active' : ''}" style="--depth:${depth}" ${attributes} title="${esc(node.path)}">
        <span class="tree-chevron ${expanded ? 'open' : ''}">${expandable ? '›' : ''}</span>
        <svg viewBox="0 0 16 16" aria-hidden="true"><path d="${folder ? 'M2 4h5l1.5 2H14v7H2z' : 'M4 2h5l3 3v9H4z M9 2v4h3'}"/></svg>
        <span class="tree-name">${esc(node.name)}</span>${file ? dirtyMark(file) : ''}</button>
        ${expandable ? `<div class="tree-children ${expanded ? 'open' : ''}"><div>${empty ? `<div class="tree-empty" style="--depth:${depth + 1}">Empty</div>` : children(node, depth + 1)}</div></div>` : ''}</div>`;
    }).join('');
  $('#tree').innerHTML = children(root);
  $('#tree').querySelectorAll('[data-folder]').forEach(button => button.onclick = () => {
    const path = button.dataset.folder;
    const expanded = !activeWindow.expandedFolders.has(path);
    if (expanded) activeWindow.expandedFolders.add(path);
    else activeWindow.expandedFolders.delete(path);
    button.setAttribute('aria-expanded', String(expanded));
    button.querySelector('.tree-chevron').classList.toggle('open', expanded);
    const body = button.nextElementSibling;
    body.inert = !expanded;
    body.classList.toggle('open', expanded);
  });
  $('#tree').querySelectorAll('.tree-children:not(.open)').forEach(body => { body.inert = true; });
  $('#tree').querySelectorAll('[data-tree-file]').forEach(button => button.onclick = () => {
    activeWindow.treeSelected = true;
    clearSelection();
    openFile(+button.dataset.treeFile);
  });
  updateSidebarLayout();
}

$('#context-choice').onclick = () => {
  const target = windows.find(win => activeWindow.folder ? !win.folder && !win.single : win.folder);
  if (target) activateWindow(target.id);
};
$('#empty-choice').onclick = () => {
  emptyFolderStyle = emptyFolderStyle === 'leaf' ? 'message' : 'leaf';
  $('#empty-choice').textContent = `Empty: ${emptyFolderStyle === 'leaf' ? 'no arrow' : 'expand + message'}`;
  renderTree();
};
$('#hidden-choice').onclick = () => {
  hiddenItemStyle = hiddenItemStyle === 'muted' ? 'regular' : 'muted';
  $('#hidden-choice').textContent = `Hidden: ${hiddenItemStyle === 'muted' ? 'muted' : 'regular'}`;
  renderTree();
};
$('#tree-heading').onclick = () => {
  const expanded = $('#tree-heading').getAttribute('aria-expanded') !== 'true';
  $('#tree-heading').setAttribute('aria-expanded', String(expanded));
  $('#tree-body').classList.toggle('collapsed', !expanded);
  $('#tree-body').inert = !expanded;
  document.querySelector('aside').classList.toggle('tree-closed', !expanded);
};
