const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {JSDOM}=require('jsdom');
function bridge(html){
  const w=new JSDOM(html,{url:'https://chatgpt.com/',runScripts:'outside-only'}).window,events=[];let poll,now=1000;
  w.HTMLElement.prototype.getClientRects=()=>[{}];w.webkit={messageHandlers:{chatEvent:{postMessage:e=>events.push(e)}}};w.setInterval=f=>poll=f;w.Date.now=()=>now;
  w.eval(fs.readFileSync('shared/dom.js','utf8'));w.eval(fs.readFileSync('shared/chat-bridge.js','utf8'));
  return {w,events,tick(ms=0){now+=ms;poll();},close(){w.close();}};
}
test('bridge rejects logged-out arm and never emits attached',()=>{const f=bridge('');assert.equal(f.w.LiveTalkMobileChat.arm().ok,false);assert.equal(f.events.some(e=>e.type==='attached'),false);f.close();});
test('historical rerender is not mistaken for a new answer; new snapshots keep one ID',()=>{
  const f=bridge('<textarea id="prompt-textarea"></textarea><div data-message-author-role="assistant">過去</div>');assert.equal(f.w.LiveTalkMobileChat.arm().ok,true);
  f.w.document.querySelector('[data-message-author-role]').outerHTML='<div data-message-author-role="assistant">過去の再描画</div>';f.tick();assert.equal(f.events.filter(e=>e.type==='start').length,0);
  const n=f.w.document.createElement('div');n.dataset.messageAuthorRole='assistant';n.textContent='新しい';f.w.document.body.append(n);f.tick();n.textContent='新しい回答です';f.tick(100);
  assert.equal(f.events.filter(e=>e.type==='start').length,1);assert.equal(new Set(f.events.filter(e=>e.type==='snapshot').map(e=>e.id)).size,1);
  f.tick(2000);assert.equal(f.events.at(-1).done,undefined);f.tick(4000);assert.equal(f.events.at(-1).done,true);f.close();
});
test('changing chat routes detaches instead of reading another conversation',()=>{const f=bridge('<textarea id="prompt-textarea"></textarea>');f.w.LiveTalkMobileChat.arm();f.w.history.pushState({},'', '/c/other');f.tick();assert.equal(f.events.at(-1).type,'detached');f.close();});
