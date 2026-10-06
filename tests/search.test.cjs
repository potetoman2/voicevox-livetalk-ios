const {test}=require('node:test'),assert=require('node:assert/strict'),{app}=require('./app-fixture.cjs');
const init={planUsageAvailable:true,experimentalAvailable:true,asrAvailable:true,styles:[{name:'ずんだもん',styles:[{id:3,name:'ノーマル'}]}]};
const status={authenticated:true,models:[{id:'fast',label:'速いモデル',efforts:['none','low','medium','high','xhigh']},{id:'limited',label:'別のモデル',efforts:['low','medium']}],model:'fast'};
const event=(f,e)=>f.w.LiveTalkEvent({...e,provider:'official'});
async function connected(){const f=await app({agreed:true,init,handler:m=>m.command==='gptStatus'?status:undefined});await f.until(()=>!f.$('mic').disabled);return f;}
test('instant, model-supported effort and search mode are sent and autosaved',async()=>{
 const f=await connected();try{
  assert.ok([...f.$('effort').options].some(o=>o.value==='xhigh'));assert.match(f.$('effortHint').textContent,/思考なし/);
  f.$('effort').value='xhigh';f.$('effort').dispatchEvent(new f.w.Event('change'));await f.wait(30);
  f.$('webSearch').value='on';f.$('webSearch').dispatchEvent(new f.w.Event('change'));await f.wait(30);
  f.$('input').value='最近の研究を調べて';await f.click('send');const send=f.calls.filter(c=>c.command==='gptSend').at(-1);assert.equal(send.args.effort,'xhigh');assert.equal(send.args.webSearch,'on');
  await f.until(()=>f.calls.some(c=>c.command==='saveSettings'&&c.args.settings.effort==='xhigh'&&c.args.settings.webSearch==='on'));
 }finally{f.close();}
});
test('switching model removes unsupported effort and resets to instant',async()=>{
 const f=await connected();try{f.$('effort').value='xhigh';f.$('effort').dispatchEvent(new f.w.Event('change'));await f.wait(30);f.$('model').value='limited';f.$('model').dispatchEvent(new f.w.Event('change'));await f.wait(40);assert.equal(f.$('effort').value,'instant');assert.equal([...f.$('effort').options].some(o=>o.value==='xhigh'),false);assert.match(f.$('effortHint').textContent,/「低」/);}finally{f.close();}
});
test('search phase, safe clickable sources and timing are displayed without speaking citation markup',async()=>{
 const f=await connected();try{
  f.$('input').value='調べて';await f.click('send');event(f,{type:'start',id:'search'});event(f,{type:'phase',id:'search',phase:'searching'});await f.wait(25);assert.match(f.$('state').textContent,/ネットで調べ/);
  event(f,{type:'snapshot',id:'search',text:'調べた結果です。\uE200cite\uE202turn1\uE201',done:true});
  event(f,{type:'sources',id:'search',sources:[{url:'https://example.org/news',title:'参考資料'},{url:'https://example.org/news',title:'重複'},{url:'javascript:alert(1)',title:'悪いリンク'}]});event(f,{type:'timing',id:'search',firstTextMs:320});await f.wait(50);
  assert.equal(f.$('sources').querySelectorAll('button').length,1);f.$('sources').querySelector('button').click();await f.wait(15);assert.ok(f.calls.some(c=>c.command==='openSource'&&c.args.url==='https://example.org/news'));
  assert.match(f.$('latency').textContent,/0.32秒/);assert.equal(f.calls.some(c=>c.command==='synthesize'&&c.args.text.includes('\uE200')),false);
  event(f,{type:'sources',id:'old',sources:[{url:'https://example.net'}]});await f.wait(15);assert.match(f.$('sources').textContent,/参考資料/);
 }finally{f.close();}
});
test('fast and natural tempo reach the native speech recognizer',async()=>{
 const f=await connected();try{await f.click('mic');assert.equal(f.calls.filter(c=>c.command==='asrStart').at(-1).args.tempo,'fast');await f.click('stop');f.$('tempo').value='natural';f.$('tempo').dispatchEvent(new f.w.Event('change'));await f.wait(35);await f.click('mic');assert.equal(f.calls.filter(c=>c.command==='asrStart').at(-1).args.tempo,'natural');}finally{f.close();}
});
test('returning CarPlay results show sources without starting phone playback',async()=>{
 const f=await connected();try{event(f,{type:'carplay',active:true});assert.equal(f.$('mic').disabled,true);event(f,{type:'carplay',active:false});event(f,{type:'carplayResponse',text:'車で調べた結果',sources:[{url:'https://example.org',title:'出典'}]});assert.equal(f.$('response').textContent,'車で調べた結果');assert.equal(f.$('sources').querySelectorAll('button').length,1);assert.equal(f.calls.some(c=>c.command==='play'),false);}finally{f.close();}
});
