const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {JSDOM}=require('jsdom');
test('initial screen exposes the API-free action and exactly two main destinations',()=>{
 const d=new JSDOM(fs.readFileSync('shared/index.html','utf8')).window.document;
 assert.equal(d.querySelectorAll('nav [data-tab]').length,2);
 assert.equal(d.getElementById('readingPane').hidden,false);
 assert.equal(d.getElementById('talkPane').hidden,true);
 assert.match(d.getElementById('paste').textContent,/貼り付けて読み上げ/);
 assert.ok(d.getElementById('paste').closest('details')===null);
 assert.equal(new Set([...d.querySelectorAll('[id]')].map(e=>e.id)).size,d.querySelectorAll('[id]').length);
});
