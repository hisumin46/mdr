// 훑어보기 확장용 렌더러. DOM 이 없는 JavaScriptCore 에서 돈다.
// 원문에 섞인 HTML 은 속성 없는 단순 태그만 통과시키고 나머지는 글자로 보여 준다.
var mdrRender = (function () {
  'use strict';

  var SAFE_TAG = /^<\/?(br|hr|kbd|sub|sup|details|summary|b|i|u|s|em|strong|mark|del|ins|small|p|div|span|center)\s*\/?>$/i;

  function escapeHtml(text) {
    return String(text)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  var parser = new marked.Marked({
    gfm: true,
    renderer: {
      code: function (token) {
        var lang = (token.lang || '').trim().split(/\s+/)[0];
        var body = escapeHtml(token.text);
        if (lang && hljs.getLanguage(lang)) {
          try {
            body = hljs.highlight(token.text, { language: lang }).value;
          } catch (_) { /* 하이라이트 실패 시 원문 그대로 */ }
        }
        return '<pre><code>' + body + '</code></pre>\n';
      },
      html: function (token) {
        var raw = token.text;
        return SAFE_TAG.test(raw.trim()) ? raw : escapeHtml(raw);
      },
    },
  });

  return function (source) {
    source = String(source).replace(/^﻿/, '');
    var head = '';
    var match = source.match(/^---\r?\n([\s\S]*?)\r?\n---[ \t]*(\r?\n|$)/);
    if (match) {
      head = '<pre class="frontmatter">' + escapeHtml(match[1]) + '</pre>';
      source = source.slice(match[0].length);
    }
    var body = parser.parse(source)
      .replace(/<table>/g, '<div class="table-wrap"><table>')
      .replace(/<\/table>/g, '</table></div>');
    return head + body;
  };
})();
