(function () {
  'use strict';

  const view = document.getElementById('view');
  const editor = document.getElementById('editor');
  const statusEl = document.getElementById('status');
  const toastEl = document.getElementById('toast');
  const findBar = document.getElementById('findbar');
  const findInput = document.getElementById('findinput');
  const findCount = document.getElementById('findcount');
  const page = document.scrollingElement;
  const toggleButton = document.getElementById('btn-toggle');
  const saveButton = document.getElementById('btn-save');

  let text = '';      // 현재 내용 (수정 중인 내용 포함)
  let saved = '';     // 디스크에 저장된 내용
  let mode = 'view';
  let dirty = false;

  const post = (message) => window.webkit.messageHandlers.mdr.postMessage(message);

  // ── 렌더링 ────────────────────────────────────────────────

  function slugify(heading, used) {
    const base = heading.trim().toLowerCase()
      .replace(/[^\p{L}\p{N}\s_-]/gu, '')
      .replace(/\s/g, '-');
    let slug = base;
    for (let n = 1; used.has(slug); n++) slug = base + '-' + n;
    used.add(slug);
    return slug;
  }

  function render() {
    let source = text.replace(/^﻿/, '');
    let frontMatter = null;
    const match = source.match(/^---\r?\n([\s\S]*?)\r?\n---[ \t]*(\r?\n|$)/);
    if (match) {
      frontMatter = match[1];
      source = source.slice(match[0].length);
    }

    view.innerHTML = DOMPurify.sanitize(marked.parse(source, { gfm: true }));

    if (frontMatter !== null) {
      const pre = document.createElement('pre');
      pre.className = 'frontmatter';
      pre.textContent = frontMatter;
      view.prepend(pre);
    }
    if (!text.trim()) {
      view.innerHTML = '<p class="empty">빈 파일입니다. ⌘E 로 작성을 시작하세요.</p>';
    }

    const used = new Set();
    view.querySelectorAll('h1, h2, h3, h4, h5, h6').forEach((h) => {
      h.id = slugify(h.textContent, used);
    });
    view.querySelectorAll('pre code[class*="language-"]').forEach((code) => {
      const lang = (code.className.match(/language-([\w+#-]+)/) || [])[1];
      if (lang && hljs.getLanguage(lang)) hljs.highlightElement(code);
    });
    view.querySelectorAll('table').forEach((table) => {
      const wrap = document.createElement('div');
      wrap.className = 'table-wrap';
      table.replaceWith(wrap);
      wrap.append(table);
    });

    if (!findBar.hidden) runFind(false);
  }

  // ── 상태 ──────────────────────────────────────────────────

  function refreshStatus() {
    const next = text !== saved;
    if (next !== dirty) {
      dirty = next;
      post({ type: 'dirty', value: dirty });
    }
    toggleButton.textContent = mode === 'edit' ? '미리보기' : '수정';
    saveButton.hidden = !(mode === 'edit' || dirty);
    if (mode === 'edit') {
      statusEl.textContent = '⌘S 저장 · esc 미리보기';
      statusEl.hidden = false;
    } else if (dirty) {
      statusEl.textContent = '저장 안 됨';
      statusEl.hidden = false;
    } else {
      statusEl.hidden = true;
    }
  }

  let toastTimer = 0;
  function notice(message) {
    toastEl.textContent = message;
    toastEl.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { toastEl.hidden = true; }, 2600);
  }

  const ratioOf = (el) => {
    const range = el.scrollHeight - el.clientHeight;
    return range > 0 ? el.scrollTop / range : 0;
  };
  const applyRatio = (el, ratio) => {
    el.scrollTop = ratio * (el.scrollHeight - el.clientHeight);
  };

  function setMode(next) {
    if (next === mode) return;
    if (next === 'edit') {
      const ratio = ratioOf(page);
      closeFind();
      editor.value = text;
      document.body.dataset.mode = 'edit';
      mode = 'edit';
      editor.focus();
      editor.setSelectionRange(0, 0);
      applyRatio(editor, ratio);
    } else {
      const ratio = ratioOf(editor);
      text = editor.value;
      render();
      document.body.dataset.mode = 'view';
      mode = 'view';
      applyRatio(page, ratio);
    }
    refreshStatus();
  }

  // ── 찾기 (미리보기 전용, DOM 을 건드리지 않는 CSS Highlight) ──

  let hits = [];
  let hitIndex = -1;

  function clearHighlights() {
    if (!window.CSS || !CSS.highlights) return;
    CSS.highlights.delete('find');
    CSS.highlights.delete('find-current');
  }

  function showHit() {
    if (!window.CSS || !CSS.highlights) return;
    CSS.highlights.delete('find-current');
    if (hitIndex < 0) return;
    const range = hits[hitIndex];
    CSS.highlights.set('find-current', new Highlight(range));
    const rect = range.getBoundingClientRect();
    if (rect.top < 60 || rect.bottom > window.innerHeight - 40) {
      window.scrollBy(0, rect.top - window.innerHeight / 3);
    }
  }

  function runFind(jump) {
    clearHighlights();
    hits = [];
    const query = findInput.value.toLowerCase();
    if (query) {
      const walker = document.createTreeWalker(view, NodeFilter.SHOW_TEXT);
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        const haystack = node.nodeValue.toLowerCase();
        for (let at = haystack.indexOf(query); at !== -1; at = haystack.indexOf(query, at + query.length)) {
          const range = new Range();
          range.setStart(node, at);
          range.setEnd(node, at + query.length);
          hits.push(range);
        }
      }
    }
    if (hits.length && window.CSS && CSS.highlights) {
      CSS.highlights.set('find', new Highlight(...hits));
    }
    hitIndex = hits.length ? Math.min(Math.max(hitIndex, 0), hits.length - 1) : -1;
    if (jump && hits.length) {
      // 현재 화면 위치 이후의 첫 결과부터 시작
      const first = hits.findIndex((range) => range.getBoundingClientRect().bottom >= 0);
      hitIndex = first === -1 ? 0 : first;
    }
    findCount.textContent = query ? (hits.length ? (hitIndex + 1) + ' / ' + hits.length : '없음') : '';
    if (jump) showHit(); else if (hitIndex >= 0 && window.CSS && CSS.highlights) {
      CSS.highlights.set('find-current', new Highlight(hits[hitIndex]));
    }
  }

  function findStep(direction) {
    if (findBar.hidden) return openFind();
    if (!hits.length) return;
    hitIndex = (hitIndex + direction + hits.length) % hits.length;
    findCount.textContent = (hitIndex + 1) + ' / ' + hits.length;
    showHit();
  }

  function openFind() {
    if (mode === 'edit') return notice('찾기는 미리보기에서만 됩니다 (esc)');
    findBar.hidden = false;
    findInput.focus();
    findInput.select();
    runFind(true);
  }

  function closeFind() {
    if (findBar.hidden) return;
    findBar.hidden = true;
    clearHighlights();
    hits = [];
    hitIndex = -1;
  }

  findInput.addEventListener('input', () => { hitIndex = -1; runFind(true); });
  findInput.addEventListener('keydown', (event) => {
    if (event.isComposing) return;
    if (event.key === 'Enter') {
      event.preventDefault();
      findStep(event.shiftKey ? -1 : 1);
    }
  });

  // ── 입력 ──────────────────────────────────────────────────

  editor.addEventListener('input', () => {
    text = editor.value;
    refreshStatus();
  });

  editor.addEventListener('keydown', (event) => {
    if (event.key === 'Tab' && !event.isComposing) {
      event.preventDefault();
      document.execCommand('insertText', false, '  ');
    }
  });

  toggleButton.addEventListener('click', () => window.mdr.toggle());
  saveButton.addEventListener('click', () => window.mdr.save());

  document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape' || event.isComposing) return;
    if (!findBar.hidden) closeFind();
    else if (mode === 'edit') setMode('view');
  });

  document.addEventListener('click', (event) => {
    const anchor = event.target.closest ? event.target.closest('a') : null;
    if (!anchor) return;
    const href = anchor.getAttribute('href');
    if (!href) return;
    event.preventDefault();
    if (href.startsWith('#')) {
      let id = href.slice(1);
      try { id = decodeURIComponent(id); } catch (_) { /* 그대로 사용 */ }
      const target = document.getElementById(id) || document.getElementById(id.toLowerCase());
      if (target) target.scrollIntoView();
      return;
    }
    post({ type: 'link', href: anchor.href });
  });

  // ── 앱(Swift)에서 부르는 API ───────────────────────────────

  window.mdr = {
    load(content, base, keepScroll) {
      const top = page.scrollTop;
      const editorTop = editor.scrollTop;
      document.getElementById('base').href = base;
      text = saved = content;
      if (mode === 'edit') {
        editor.value = content;
        editor.scrollTop = editorTop;
      }
      render();
      page.scrollTop = keepScroll ? top : 0;
      refreshStatus();
    },
    toggle() { setMode(mode === 'view' ? 'edit' : 'view'); },
    save() {
      if (mode === 'edit') text = editor.value;
      if (text === saved) return setMode('view');
      post({ type: 'save', text });
    },
    saved(content) {
      saved = content;
      setMode('view');
      refreshStatus();
      notice('저장했습니다');
    },
    text() { return mode === 'edit' ? editor.value : text; },
    notice,
    find: openFind,
    findStep,
  };

  const baseEl = document.createElement('base');
  baseEl.id = 'base';
  document.head.append(baseEl);

  post({ type: 'ready' });
})();
