const {test}=require('node:test'),assert=require('node:assert/strict'),{app}=require('./app-fixture.cjs');
const init={planUsageAvailable:true,asrAvailable:true,styles:[{name:'ずんだもん',styles:[{id:3,name:'ノーマル'}]}]};
const signed={authenticated:true,models:[{id:'test',label:'test',efforts:['none','low']}],model:'test'};
async function connected(handler,settings){const f=await app({agreed:true,init,settings,handler:m=>m.command==='gptStatus'?signed:handler?.(m)});await f.until(()=>!f.$('mic').disabled);return f;}
const event=(f,e)=>f.w.LiveTalkEvent({...e,provider:'official'});
test('research acknowledgement is dispatched without waiting for the GPT send to finish',async()=>{
 let finish;const f=await connected(m=>m.command==='gptSend'?new Promise(r=>finish=r):undefined);
 try{f.$('input').value='今日のニュースを調べて';f.$('send').click();await f.until(()=>finish);const hint=f.calls.find(c=>c.command==='feedbackBegin');assert.ok(hint.args.enabled);assert.equal(hint.args.text,'今日のニュースを調べて');assert.match(f.$('heard').textContent,/今日のニュース/);assert.equal(f.$('heard').hidden,false);finish(true);await f.wait(20);}finally{f.close();}
});
test('the first real answer stops hints and stale search phases cannot restart them',async()=>{
 const f=await connected();try{f.$('input').value='調べて';await f.click('send');event(f,{type:'start',id:'current'});event(f,{type:'phase',id:'current',phase:'searching'});await f.wait(25);assert.equal(f.calls.filter(c=>c.command==='feedbackSearch').length,1);assert.equal(f.calls.filter(c=>c.command==='stop').at(-1).args.keepFeedback,true,'response start must preserve the pending acknowledgement');event(f,{type:'snapshot',id:'current',text:'見つかった内容を説明します。',done:true});await f.until(()=>f.calls.some(c=>c.command==='feedbackStop'));event(f,{type:'phase',id:'old',phase:'searching'});await f.wait(25);assert.equal(f.calls.filter(c=>c.command==='feedbackSearch').length,1);assert.equal(f.calls.find(c=>c.command==='gptSend').args.text,'調べて');assert.equal(f.calls.some(c=>c.command==='gptSend'&&/待って|調べてみる/.test(c.args.text)),false);}finally{f.close();}
});
test('waiting speech can be disabled and the preference is saved',async()=>{
 const f=await connected();try{f.$('feedback').checked=false;f.$('feedback').dispatchEvent(new f.w.Event('change'));f.$('input').value='ニュース';await f.click('send');assert.equal(f.calls.find(c=>c.command==='feedbackBegin').args.enabled,false);await f.until(()=>f.calls.some(c=>c.command==='saveSettings'&&c.args.settings.feedback===false));}finally{f.close();}
});
test('a failed send stops waiting speech rather than leaving a false ongoing search',async()=>{
 const f=await connected(m=>m.command==='gptSend'?Promise.reject(Error('通信エラー')):undefined);try{f.$('input').value='調べて';await f.click('send');await f.until(()=>!f.$('errorPanel').hidden);assert.ok(f.calls.some(c=>c.command==='feedbackStop'));}finally{f.close();}
});
test('privacy documents are opened only on request and deleting local data clears visible conversation',async()=>{
 const f=await connected(m=>m.command==='deleteLocalData'?{localRemoved:true,remoteRevoked:false}:undefined);try{await f.click('privacy');await f.click('terms');assert.ok(f.calls.some(c=>c.command==='showPrivacy'));assert.ok(f.calls.some(c=>c.command==='showTerms'));f.$('input').value='非公開の質問';f.$('response').textContent='非公開の返答';f.$('manual').value='貼り付けた内容';await f.click('deleteData');assert.equal(f.$('input').value,'');assert.equal(f.$('manual').value,'');assert.doesNotMatch(f.$('response').textContent,/非公開/);assert.equal(f.$('mic').disabled,true);assert.match(f.$('toast').textContent,/ChatGPT側/);}finally{f.close();}
});
test('cancelling deletion preserves the local preferences and visible response',async()=>{
 const f=await connected(m=>m.command==='deleteLocalData'?{cancelled:true}:undefined);try{f.$('response').textContent='残しておく返答';await f.click('deleteData');assert.equal(f.$('response').textContent,'残しておく返答');}finally{f.close();}
});
