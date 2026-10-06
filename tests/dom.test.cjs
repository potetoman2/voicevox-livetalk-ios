const {test}=require('node:test');
const assert=require('node:assert/strict');
const {JSDOM}=require('jsdom');
const DOM=require('../shared/dom');
function documentOf(html){const {document}=new JSDOM(html).window; for(const e of document.querySelectorAll('*'))e.getClientRects=()=>[{width:10,height:10}];return document;}
test('current contenteditable editor is detected without an optional role',()=>assert.ok(DOM.editor(documentOf('<div id="prompt-textarea" contenteditable="true"></div>'))));
test('logged-out, disabled, draft and generating screens cannot report connected',()=>{
  for(const html of ['', '<textarea id="prompt-textarea" disabled></textarea>'])assert.equal(DOM.readiness(documentOf(html)).code,'EDITOR_MISSING');
  assert.equal(DOM.readiness(documentOf('<textarea id="prompt-textarea">下書き</textarea>')).code,'DRAFT');
  assert.equal(DOM.readiness(documentOf('<textarea id="prompt-textarea"></textarea><button data-testid="stop-button"></button>')).code,'GENERATING');
  assert.equal(DOM.readiness(documentOf('<textarea id="prompt-textarea"></textarea>')).ok,true);
});
test('textarea insertion dispatches input and sends through the visible control',async()=>{
  const doc=documentOf('<textarea id="prompt-textarea"></textarea><button data-testid="send-button" disabled></button>');let sent='';
  const editor=DOM.editor(doc),button=DOM.button(doc,'send');editor.oninput=()=>button.disabled=false;button.onclick=()=>sent=editor.value;
  await DOM.submit(doc,'こんにちは');assert.equal(sent,'こんにちは');
});
module.exports={documentOf};
