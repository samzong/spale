const layoutStudy = {
  case: 'demo', theme: 'light', width: '640', count: '5', path: 'long'
};
let layoutDemoWindows;
let windowVisibility = { ids: "", current: null, width: -1 };
const layoutDescriptions = {
  demo: 'Interactive prototype with the selected narrow layouts.',
  c01: 'Keep both actions together below the message when narrow. Wider readers use one row.',
  c02: 'Keep the full path when it fits. Remove leading directories first, then show the filename, and only then shorten the filename in the middle. Hover an elided path for its full name.',
  c03: 'Scroll the window bar horizontally. Keep full names and reveal the current window after activation or resize.'
};

function fileHeader(file) {
  const status = { M: 'Modified', A: 'Added', U: 'Untracked', R: 'Renamed', D: 'Deleted' }[file.status] || '';
  const path = file.status === 'R' && file.oldPath ? file.oldPath + ' → ' + file.path : file.path;
  return `<div contenteditable="false" class="file-head" data-key="head" data-line="head" data-status="${file.status}"><span class="path" data-path="${esc(path)}" data-file-path="${esc(file.path)}" data-old-path="${esc(file.status === 'R' ? file.oldPath || '' : '')}" aria-label="${esc(path)}">${esc(path)}</span>${dirtyMark(files.find(item => item.path === file.path) || file)}<span class="status">${status}</span><span class="counts">${file.plus ? `<span class="plus">+${file.plus}</span>` : ''}${file.minus ? `<span class="minus">−${file.minus}</span>` : ''}</span></div>`;
}

function conflict(file) {
  return file.conflict ? `<div class="conflict" contenteditable="false"><span>Changed on disk</span><div class="conflict-actions"><button data-save="${esc(file.path)}">Keep my version</button><button data-revert="${esc(file.path)}">Use disk version</button></div></div>` : '';
}

function revealCurrentWindow() {
  const bar = $('#windows');
  const ids = windows.map(win => win.id).join(',');
  const width = bar.clientWidth;
  if (ids === windowVisibility.ids && activeWindow?.id === windowVisibility.current && width === windowVisibility.width) return;
  windowVisibility = { ids, current: activeWindow?.id, width };
  const current = bar.querySelector('.active');
  if (!current) return;
  const target = current.getBoundingClientRect();
  const bounds = bar.getBoundingClientRect();
  if (target.left < bounds.left + 8) bar.scrollLeft -= bounds.left + 8 - target.left;
  else if (target.right > bounds.right - 8) bar.scrollLeft += target.right - bounds.right + 8;
}

function windowBar() {
  const bar = $('#windows');
  const scroll = bar.scrollLeft;
  const focus = bar.contains(document.activeElement) ? document.activeElement.dataset.window : null;
  bar.innerHTML = windows.map(win => {
    const label = windowLabel(win);
    return `<button data-window="${win.id}" class="${win === activeWindow ? 'active' : ''}" aria-current="${win === activeWindow}" title="${esc(label)}" aria-label="${esc(label)}${win.files.some(dirty) ? ', Unsaved changes' : ''}"><span class="window-name">${esc(label)}</span>${win.files.some(dirty) ? '<span class="unsaved" aria-label="Unsaved changes">●</span>' : ''}</button>`;
  }).join('');
  bar.querySelectorAll('button').forEach(button => button.onclick = () => activateWindow(+button.dataset.window));
  bar.scrollLeft = scroll;
  if (focus) bar.querySelector(`[data-window="${focus}"]`)?.focus({ preventScroll: true });
  requestAnimationFrame(revealCurrentWindow);
}

function fittedHeaderPaths(path, oldPath, width, measure) {
  const fits = value => measure(value) <= width;
  const candidates = value => {
    const parts = value.split('/');
    const values = [value];
    for (let start = 1; start < parts.length - 1; start++) values.push('…/' + parts.slice(start).join('/'));
    if (parts.length > 1) values.push(parts.at(-1));
    return values;
  };
  const current = candidates(path);
  if (oldPath) {
    const previous = candidates(oldPath);
    let left = 0, right = 0;
    while (!fits(previous[left] + ' → ' + current[right])) {
      if (left === previous.length - 1 && right === current.length - 1) break;
      if (left < previous.length - 1 && (right === current.length - 1 || measure(previous[left]) >= measure(current[right]))) left++;
      else right++;
    }
    if (fits(previous[left] + ' → ' + current[right])) return [previous[left], current[right]];
  } else {
    const candidate = current.find(fits);
    if (candidate !== undefined) return [candidate];
  }
  const filename = current.at(-1);
  if (fits(filename)) return [filename];
  if (!fits('…')) return [''];
  const chars = Array.from(new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(filename), item => item.segment);
  const shorten = count => chars.slice(0, Math.ceil(count / 2)).join('') + '…' + chars.slice(chars.length - Math.floor(count / 2)).join('');
  let low = 0, high = Math.max(0, chars.length - 1);
  while (low < high) {
    const count = Math.ceil((low + high) / 2);
    if (fits(shorten(count))) low = count;
    else high = count - 1;
  }
  return [shorten(low)];
}

function fitHeaderPaths() {
  const context = document.createElement('canvas').getContext('2d');
  document.querySelectorAll('.file-head .path').forEach(element => {
    context.font = getComputedStyle(element).font;
    const oldPath = element.dataset.oldPath || null;
    const pieces = fittedHeaderPaths(element.dataset.filePath, oldPath, element.clientWidth, value => context.measureText(value).width);
    const text = pieces.join(' → ');
    if (oldPath || text !== element.dataset.path) element.title = element.dataset.path;
    else element.removeAttribute('title');
    if (element.textContent !== text || !element.querySelector('.directory')) {
      element.innerHTML = pieces.map(piece => {
        const split = piece.lastIndexOf('/') + 1;
        return `<span class="directory">${esc(piece.slice(0, split))}</span>${esc(piece.slice(split))}`;
      }).join(' → ');
    }
  });
}

function applyLayoutChoice() {
  const root = document.documentElement;
  root.style.setProperty('--study-width', layoutStudy.width + 'px');
  theme = layoutStudy.theme;
  appearance();
  $('#context-choice').disabled = layoutStudy.case !== 'demo';
  ['count', 'path'].forEach(key => { $('#study-' + key).disabled = layoutStudy.case === 'demo'; });
  $('#study-description').textContent = layoutDescriptions[layoutStudy.case];
  ['case', 'theme', 'width', 'count', 'path'].forEach(key => { $('#study-' + key).value = layoutStudy[key]; });
  history.replaceState(null, '', '?' + new URLSearchParams({ study: layoutStudy.case, theme: layoutStudy.theme, width: layoutStudy.width, count: layoutStudy.count, path: layoutStudy.path }));
  fitHeaderPaths();
  requestAnimationFrame(revealCurrentWindow);
}

function resetLayoutScene() {
  if (layoutStudy.case === 'demo') {
    activeWindow = null;
    windows = structuredClone(layoutDemoWindows);
    activateWindow(windows[0].id);
    applyLayoutChoice();
    return;
  }
  const paths = {
    long: 'Sources/Accounts/Authentication/SessionManagement/Coordinators/AccountSettingsCoordinator.swift',
    mixed: 'Sources/账户管理/Authentication/会话恢复/AccountSessionCoordinator.swift',
    renamed: 'new/dir/new.swift',
    deleted: 'Sources/Accounts/Authentication/LegacySessionCoordinator.swift',
    unbroken: 'Sources/AccountAuthenticationSessionPersistenceAndRestorationCoordinator.swift'
  };
  const before = 'struct Session {\n    let timeout = 30\n    let retries = 2\n}\n';
  const after = before.replace('30', '60').replace('2', '3');
  const fixture = sample(paths[layoutStudy.path], layoutStudy.path === 'deleted' ? '' : after, before);
  if (layoutStudy.path === 'renamed') {
    fixture.status = 'R'; fixture.renameGroup = 'Unstaged'; fixture.oldPath = 'old/dir/old.swift';
  }
  if (layoutStudy.path === 'deleted') fixture.workExists = false;
  windows = Array.from({ length: +layoutStudy.count }, (_, index) => {
    const repo = 'ledger-' + ['authentication', 'accounting', 'notifications', 'reconciliation', 'reporting'][index % 5];
    const win = makeWindow(repo, repo, 'main', [fixture]);
    if (index >= 5) win.worktree = 'review-' + (index + 1);
    if (layoutStudy.case === 'c01') {
      win.files[0].full = after.replace('60', '90');
      win.files[0].conflict = true;
      recompute(win.files[0]);
    }
    return win;
  });
  activeWindow = null;
  activateWindow(windows[layoutStudy.case === 'c03' ? windows.length - 1 : 0].id);
  applyLayoutChoice();
}

function initializeLayoutStudy() {
  layoutDemoWindows = structuredClone(windows);
  const params = new URLSearchParams(location.search);
  ['case', 'theme', 'width', 'count', 'path'].forEach(key => {
    const value = params.get(key === 'case' ? 'study' : key);
    const allowed = [...$('#study-' + key).options].map(option => option.value);
    if (allowed.includes(value)) layoutStudy[key] = value;
  });
  ['case', 'width', 'count', 'path'].forEach(key => $('#study-' + key).onchange = event => {
    layoutStudy[key] = event.target.value;
    resetLayoutScene();
  });
  $('#study-theme').onchange = event => { layoutStudy.theme = event.target.value; applyLayoutChoice(); };
  $('#study-reset').onclick = resetLayoutScene;
  $('#appearance').onclick = () => { layoutStudy.theme = theme === 'dark' ? 'light' : 'dark'; applyLayoutChoice(); };
  const paths = new MutationObserver(fitHeaderPaths);
  paths.observe($('#stream'), { childList: true });
  paths.observe($('#fullfile'), { childList: true });
  new ResizeObserver(fitHeaderPaths).observe(reader);
  new ResizeObserver(revealCurrentWindow).observe($('#windows'));
  resetLayoutScene();
}
