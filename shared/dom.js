/* DOM only: no cookies, bearer credentials or internal ChatGPT endpoints. */
(function(root) {
  const visible = e => !!e && !!(e.offsetWidth || e.offsetHeight || e.getClientRects().length);
  function editor(doc) {
    return [...doc.querySelectorAll('#prompt-textarea[contenteditable="true"],[contenteditable="true"][role="textbox"],textarea#prompt-textarea')]
      .filter(e => visible(e) && !e.disabled && e.getAttribute('aria-disabled') !== 'true').at(-1);
  }
  function readiness(doc) {
    const e=editor(doc);
    if(!e)return {ok:false,code:'EDITOR_MISSING',message:'ChatGPTにログインして、入力欄が表示されるまでお待ちください。使えない場合は返答をコピーして読み上げられます。'};
    if(button(doc,'stop'))return {ok:false,code:'GENERATING',message:'ChatGPTの返答が終わってから接続してください。'};
    if((e.tagName==='TEXTAREA'?e.value:e.textContent).trim())return {ok:false,code:'DRAFT',message:'入力途中の文章を送信または削除してから接続してください。'};
    return {ok:true,code:'READY',message:'質問を送れる状態です'};
  }
  function button(doc, kind) {
    const pattern = kind === 'send' ? /^(送信|Send|Send message|メッセージを送信)$/i
      : /^(停止|Stop|Stop generating|生成を停止|生成を中断|応答の生成を停止)$/i;
    return [...doc.querySelectorAll('button')].filter(visible).find(e =>
      pattern.test(e.getAttribute('aria-label') || '') ||
      (kind === 'send' && e.getAttribute('data-testid') === 'send-button') ||
      (kind === 'stop' && e.getAttribute('data-testid') === 'stop-button'));
  }
  function messages(doc, skipCode = true) {
    const result = [], seen = new Set();
    const nodes = [...doc.querySelectorAll('[data-message-author-role="assistant"],[data-conversation-role="assistant"]')];
    for (const node of nodes) {
      const unit = node.matches('[data-conversation-role]') ? node.parentElement : node;
      const key = unit.getAttribute('data-chatgpt-search-message-ids') || unit.getAttribute('data-message-id') || 'assistant:'+result.length;
      if (seen.has(key)) continue;
      seen.add(key);
      const body = node.matches('[data-conversation-role]') ? node.nextElementSibling : (node.querySelector('.markdown') || node);
      if (!body) continue;
      const copy = body.cloneNode(true);
      copy.querySelectorAll('button,script,style,[aria-hidden="true"],.sr-only').forEach(e => e.remove());
      if (skipCode) copy.querySelectorAll('pre').forEach(e => e.remove());
      copy.querySelectorAll('p,h1,h2,h3,h4,li,br').forEach(e => e.appendChild(doc.createTextNode('\n')));
      const text = (copy.textContent || '').replace(/\n{3,}/g,'\n\n').trim();
      result.push({key, text});
    }
    return result;
  }
  function appendDelta(oldText, newText) {
    if (newText === oldText) return {delta:'', rewrite:false};
    if (newText.startsWith(oldText)) return {delta:newText.slice(oldText.length), rewrite:false};
    return {delta:newText, rewrite:true};
  }
  async function submit(doc, text) {
    const e = editor(doc);
    if (!e) throw Error('ChatGPTの入力欄が見つかりません');
    const existing = e.tagName === 'TEXTAREA' ? e.value.trim() : e.textContent.trim();
    if (existing) throw Error('ChatGPTに入力途中の文章があります。送信または削除してから再試行してください');
    if (button(doc,'stop')) throw Error('前の返答を停止してから送信してください');
    e.focus();
    if (e.tagName === 'TEXTAREA') {
      Object.getOwnPropertyDescriptor(doc.defaultView.HTMLTextAreaElement.prototype,'value').set.call(e,text);
      e.dispatchEvent(new doc.defaultView.Event('input',{bubbles:true}));
    } else {
      const selection = doc.getSelection(), range = doc.createRange();
      range.selectNodeContents(e); selection.removeAllRanges(); selection.addRange(range);
      if (!doc.execCommand('insertText',false,text)) throw Error('入力欄へ挿入できません。手動送信に切り替えてください');
      e.dispatchEvent(new doc.defaultView.InputEvent('input',{bubbles:true,inputType:'insertText',data:text}));
    }
    // Wait for React/ProseMirror to enable the actual visible send control.
    for (let attempt=0; attempt<25; attempt++) {
      const send=button(doc,'send');
      if (send && !send.disabled) { send.click(); return; }
      await new Promise(resolve => setTimeout(resolve,100));
    }
    throw Error('送信ボタンが有効になりません。入力欄の文章を確認してください');
  }
  async function stop(doc) {
    const e=button(doc,'stop');
    if (e && !e.disabled) e.click();
    for (let attempt=0;attempt<30;attempt++) {
      if (!button(doc,'stop')) return;
      await new Promise(resolve => setTimeout(resolve,100));
    }
    throw Error('GPTの生成停止を確認できません。ChatGPT画面で停止してください');
  }
  root.LiveTalkDOM={editor,button,messages,appendDelta,readiness,submit,stop};
  if (typeof module !== 'undefined') module.exports=root.LiveTalkDOM;
})(typeof globalThis !== 'undefined' ? globalThis : this);
