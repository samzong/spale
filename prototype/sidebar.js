const extensionLanguages = new Map([['mk', 'makefile'], ['mak', 'makefile'], ['php', 'php'], ['vue', 'vue'], ['clj', 'clojure'], ['cljs', 'clojure'], ['cljc', 'clojure'], ['edn', 'clojure'], ['coffee', 'coffeescript'], ['j2', 'jinja'], ['jinja', 'jinja'], ['hpp', 'cpp'], ['hh', 'cpp'], ['hxx', 'cpp'], ['h++', 'cpp'], ['ipp', 'cpp'], ['m', 'objective-c'], ['pl', 'perl'], ['pm', 'perl'], ['markdown', 'markdown'], ['mdown', 'markdown'], ['mkd', 'markdown'], ['mkdn', 'markdown'], ['hbs', 'handlebars'], ['handlebars', 'handlebars'], ['properties', 'properties'], ['cfg', 'properties'], ['conf', 'properties'], ['ini', 'properties'], ['rake', 'ruby'], ['gemspec', 'ruby'], ['ru', 'ruby'], ['podspec', 'ruby'], ['rbi', 'ruby'], ['pyi', 'python'], ['pyw', 'python']]);
const nameLanguages = new Map([['makefile', 'makefile'], ['gnumakefile', 'makefile'], ['containerfile', 'dockerfile'], ['gemfile', 'ruby'], ['rakefile', 'ruby'], ['podfile', 'ruby'], ['vagrantfile', 'ruby'], ['brewfile', 'ruby'], ['guardfile', 'ruby'], ['capfile', 'ruby'], ['fastfile', 'ruby'], ['.bashrc', 'shellscript'], ['.bash_profile', 'shellscript'], ['.bash_login', 'shellscript'], ['.bash_logout', 'shellscript'], ['.profile', 'shellscript'], ['.zshrc', 'shellscript'], ['.zprofile', 'shellscript'], ['.zlogin', 'shellscript'], ['.zlogout', 'shellscript'], ['.zshenv', 'shellscript'], ['pkgbuild', 'shellscript'], ['apkbuild', 'shellscript']]);
let iconTheme;

function sidebar() {
  const changed = new Set();
  $('#files').innerHTML = ['Staged', 'Unstaged'].map(group => {
    const included = clean ? [] : files.map((file, index) => ({ file, index, status: groupStatus(file, group) })).filter(item => item.status);
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
  const collapsed = activeWindow.changedFilesCollapsed ?? changed.size === 0;
  $('#changes-panel').classList.toggle('collapsed', collapsed);
  $('#changes-heading').setAttribute('aria-expanded', String(!collapsed));
  $('#files').inert = collapsed;
  $('#files').querySelectorAll('button').forEach(button => button.onclick = () => switchFlow(button.dataset.group,
    button.dataset.file === undefined ? null : +button.dataset.file));
  renderTree();
}

function readIconTheme(theme) {
  const lower = map => new Map(Object.entries(map || {}).map(([key, value]) => [key.toLowerCase(), value]));
  return {
    paths: new Map(Object.entries(theme.iconDefinitions).map(([id, definition]) => [id, 'symbols/' + definition.iconPath.replace(/^\.\//, '')])),
    extensions: lower(theme.fileExtensions),
    fileNames: lower(theme.fileNames),
    languages: new Map(Object.entries(theme.languageIds || {})),
    folderNames: lower(theme.folderNames),
    file: theme.file,
    folder: theme.folder
  };
}

function fileIcon(name, folder) {
  const theme = iconTheme;
  const lowered = name.toLowerCase();
  if (folder) return theme.paths.get(theme.folderNames.get(lowered) || theme.folder);
  if (theme.fileNames.has(lowered)) return theme.paths.get(theme.fileNames.get(lowered));
  const segments = lowered.split('.').slice(1);
  for (let index = 0; index < segments.length; index++) {
    const id = theme.extensions.get(segments.slice(index).join('.'));
    if (id) return theme.paths.get(id);
  }
  const language = nameLanguages.get(lowered) || extensionLanguages.get(segments.at(-1));
  return theme.paths.get(theme.languages.get(language) || theme.file);
}

function updateSidebarLayout() {
  $('#changes-panel').hidden = !!activeWindow?.folder;
  $('#tree-panel').hidden = !!activeWindow?.single;
  const expanded = $('#tree-heading').getAttribute('aria-expanded') === 'true';
  document.querySelector('aside').classList.toggle('tree-closed', !expanded);
  $('#tree-body').classList.toggle('collapsed', !expanded);
  $('#tree-body').inert = !expanded;
}

function renderTree() {
  activeWindow.expandedFolders ??= new Set(['.github', '.vscode', 'Archive', 'build']);
  const root = { children: new Map() };
  const add = (path, index) => {
    if (path.split('/').some(name => name.toLowerCase() === '.git')) return;
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
      const expandable = folder && node.children.size > 0;
      const expanded = expandable && activeWindow.expandedFolders.has(node.path);
      const hidden = node.name.startsWith('.');
      const file = files[node.index];
      const attributes = folder
        ? expandable ? `data-folder="${esc(node.path)}" aria-expanded="${expanded}"` : 'aria-disabled="true"'
        : `data-tree-file="${node.index}"`;
      return `<div class="tree-node"><button class="tree-row ${hidden ? 'hidden-item' : ''} ${!folder && activeWindow.treeSelected && current === node.index ? 'active' : ''}" style="--depth:${depth}" ${attributes} title="${esc(node.path)}">
        <span class="tree-chevron ${expanded ? 'open' : ''}">${expandable ? '›' : ''}</span>
        <img class="tree-icon" src="${esc(fileIcon(node.name, folder))}" alt="">
        <span class="tree-name">${esc(node.name)}</span>${file ? dirtyMark(file) : ''}</button>
        ${expandable ? `<div class="tree-children ${expanded ? 'open' : ''}"><div>${children(node, depth + 1)}</div></div>` : ''}</div>`;
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

document.querySelector('#changes-heading').onclick = () => {
  activeWindow.changedFilesCollapsed = !(activeWindow.changedFilesCollapsed ?? clean);
  sidebar();
};
document.querySelector('#collapse-policy').onchange = event => {
  collapsePolicy = event.target.value;
  windows.forEach(win => { win.changedFilesCollapsed = null; });
  sidebar();
};
document.querySelector('#tree-heading').onclick = () => {
  const expanded = $('#tree-heading').getAttribute('aria-expanded') !== 'true';
  $('#tree-heading').setAttribute('aria-expanded', String(expanded));
  $('#tree-body').classList.toggle('collapsed', !expanded);
  $('#tree-body').inert = !expanded;
  document.querySelector('aside').classList.toggle('tree-closed', !expanded);
};
