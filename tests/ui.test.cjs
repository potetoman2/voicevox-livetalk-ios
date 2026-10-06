const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {JSDOM}=require('jsdom');
test('initial screen centers voice conversation and keeps manual reading as an optional tool',()=>{
 const d=new JSDOM(fs.readFileSync('shared/index.html','utf8')).window.document;
 assert.equal(d.querySelectorAll('nav [data-tab]').length,2);
 assert.equal(d.getElementById('readingPane').hidden,false);
 assert.equal(d.getElementById('talkPane').hidden,false);
 assert.match(d.getElementById('paste').textContent,/貼り付けて読み上げ/);
 assert.equal(d.getElementById('paste').closest('details').id,'manualTool');
 assert.equal(d.getElementById('manualTool').open,false);
 assert.match(d.getElementById('mic').textContent,/会話を始める/);
 assert.ok(d.getElementById('mic').compareDocumentPosition(d.getElementById('paste')) & 4);
 assert.equal(new Set([...d.querySelectorAll('[id]')].map(e=>e.id)).size,d.querySelectorAll('[id]').length);
});
