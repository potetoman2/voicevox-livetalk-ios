const {test}=require('node:test'),assert=require('node:assert/strict'),{app}=require('./app-fixture.cjs');
test('an unapproved GPT build explains its limit and does not restore authentication',async()=>{
 const f=await app({agreed:true,init:{styles:[{name:'Voice',styles:[{id:3,name:'Normal'}]}],asrAvailable:true,planUsageAvailable:false,experimentalAvailable:false,planUsageUnavailableReason:'GPTの商用接続は承認待ちです。'}});
 try{assert.equal(f.$('chatOpen').disabled,true);assert.match(f.$('chatStatus').textContent,/承認待ち/);assert.equal(f.$('planHint').hidden,false);assert.equal(f.calls.some(c=>['gptStatus','gptSignIn','gptSend','chatOpen'].includes(c.command)),false);assert.equal(f.$('read').disabled,false);}finally{f.close();}
});
test('first-run consent is on home and reading is gated until preparation succeeds',async()=>{const f=await app();try{assert.equal(f.$('onboarding').hidden,false);assert.equal(f.$('paste').disabled,true);await f.click('prepare');assert.equal(f.$('onboarding').hidden,true);assert.equal(f.$('paste').disabled,false);assert.match(f.$('credit').textContent,/VOICEVOX:ずんだもん/);}finally{f.close();}});
test('returning users prepare automatically without a redundant consent prompt',async()=>{const f=await app({agreed:true});try{assert.equal(f.$('onboarding').hidden,true);assert.equal(f.calls.filter(c=>c.command==='init').length,1);assert.equal(f.calls.find(c=>c.command==='init').args.interactive,false);}finally{f.close();}});
test('invalid model metadata never unlocks reading',async()=>{const f=await app({agreed:true,init:{styles:[],asrAvailable:true}});try{assert.equal(f.$('paste').disabled,true);assert.match(f.$('capabilities').textContent,/声が見つかりません/);}finally{f.close();}});

test('permission errors remain visible and lead directly to device settings',async()=>{
 const f=await app({agreed:true,settings:{experimental:true},handler:m=>{if(m.command==='asrStart')throw Error('マイクが許可されていません');}});
 try{f.w.LiveTalkEvent({type:'attached'});await f.wait(20);await f.click('mic');assert.equal(f.$('errorPanel').hidden,false);assert.match(f.$('retry').textContent,/設定/);await f.click('retry');assert.ok(f.calls.some(c=>c.command==='openSettings'));assert.equal(f.$('mic').textContent,'会話を始める');}finally{f.close();}
});
test('failed send keeps question text and does not offer a duplicate automatic retry',async()=>{
 const f=await app({agreed:true,settings:{experimental:true},handler:m=>{if(m.command==='chatSend')throw Error('ChatGPTの送信を確認できません');}});
 try{f.w.LiveTalkEvent({type:'attached'});await f.wait(20);f.$('input').value='残す質問';await f.click('send');assert.equal(f.$('input').value,'残す質問');assert.match(f.$('retry').textContent,/ChatGPT/);await f.click('retry');assert.equal(f.calls.filter(c=>c.command==='chatSend').length,1);}finally{f.close();}
});

test('one tap pastes and reads without login; clipboard is accessed only on request',async()=>{
 const f=await app({agreed:true,clipboard:'コピーした回答。'});
 try{assert.equal(f.calls.filter(c=>c.command==='paste').length,0);await f.click('paste');await f.until(()=>f.calls.some(c=>c.command==='play'));assert.equal(f.calls.filter(c=>c.command==='paste').length,1);assert.equal(f.$('manual').value,'コピーした回答。');assert.equal(f.calls.some(c=>c.command==='chatSend'),false);}finally{f.close();}
});
test('empty and oversized clipboard never replace draft text or start synthesis',async()=>{
 for(const clipboard of ['   ','長'.repeat(12001),'```js\nconst x=1;\n```']){
  const f=await app({agreed:true,clipboard});
  try{f.$('manual').value='保管する文章';await f.click('paste');assert.equal(f.$('manual').value,'保管する文章');assert.equal(f.calls.some(c=>c.command==='synthesize'),false);assert.equal(f.$('errorPanel').hidden,false);}finally{f.close();}
 }
});

test('rapid adjustments autosave the final value without requiring a save button',async()=>{
 const f=await app({agreed:true});
 try{const slider=f.w.document.querySelector('[data-setting="speed"]');for(const value of [1.1,1.2,1.4]){slider.value=value;slider.dispatchEvent(new f.w.Event('input'));}await f.until(()=>f.calls.some(c=>c.command==='saveSettings'));assert.equal(f.calls.filter(c=>c.command==='saveSettings').length,1);assert.equal(f.calls.find(c=>c.command==='saveSettings').args.settings.speed,1.4);assert.match(f.$('saveStatus').textContent,/保存済み/);}finally{f.close();}
});
test('invalid import does not overwrite existing settings',async()=>{
 const f=await app({agreed:true,settings:{speed:1.3},handler:m=>m.command==='importSettings'?['invalid']:undefined});
 try{await f.click('import');assert.equal(f.w.document.querySelector('[data-setting="speed"]').value,'1.3');assert.equal(f.calls.some(c=>c.command==='saveSettings'),false);assert.equal(f.$('errorPanel').hidden,false);}finally{f.close();}
});

test('stopping during a pending microphone start never revives listening',async()=>{
 let finish;const f=await app({agreed:true,settings:{experimental:true},handler:m=>m.command==='asrStart'?new Promise(r=>finish=r):undefined});
 try{f.w.LiveTalkEvent({type:'attached'});await f.wait(20);f.$('mic').click();await f.until(()=>finish);await f.click('stop');finish(true);await f.wait(20);assert.equal(f.$('mic').textContent,'会話を始める');assert.notEqual(f.$('badge').textContent,'聞いています');}finally{f.close();}
});
test('stale recognition tokens cannot replace a new question',async()=>{
 const f=await app({agreed:true,settings:{experimental:true}});
 try{f.w.LiveTalkEvent({type:'attached'});await f.wait(20);await f.click('mic');const token=f.calls.find(c=>c.command==='asrStart').args.token;f.$('input').value='現在の下書き';f.w.LiveTalkEvent({type:'partial',token:token-1,text:'古い認識'});assert.equal(f.$('input').value,'現在の下書き');await f.click('stop');}finally{f.close();}
});

test('missing first response leaves a visible recovery and late speech is suppressed',async()=>{
 const timers=[],f=await app({agreed:true,settings:{experimental:true},timers});
 try{f.w.LiveTalkEvent({type:'attached'});await f.wait(20);f.$('input').value='質問';await f.click('send');assert.match(f.$('state').textContent,/ChatGPTの返答/);timers.at(-1)();assert.equal(f.$('errorPanel').hidden,false);f.w.LiveTalkEvent({type:'start',id:'late'});f.w.LiveTalkEvent({type:'snapshot',id:'late',text:'遅い回答。',done:true});await f.wait(30);assert.equal(f.calls.some(c=>c.command==='play'),false);}finally{f.close();}
});
test('stop suppresses subsequent old reply events while a new user request can resume',async()=>{
 const f=await app({agreed:true,settings:{experimental:true}});
 try{f.w.LiveTalkEvent({type:'attached'});await f.wait(20);f.$('input').value='質問';await f.click('send');await f.click('stop');f.w.LiveTalkEvent({type:'start',id:'old'});f.w.LiveTalkEvent({type:'snapshot',id:'old',text:'古い回答。',done:true});await f.wait(20);assert.equal(f.calls.some(c=>c.command==='play'),false);f.w.LiveTalkEvent({type:'waiting'});f.w.LiveTalkEvent({type:'start',id:'new'});f.w.LiveTalkEvent({type:'snapshot',id:'new',text:'新しい回答。',done:true});await f.until(()=>f.calls.some(c=>c.command==='play'));}finally{f.close();}
});

test('headset removal stops the call and clears the duplex preference',async()=>{
 const f=await app({agreed:true,settings:{experimental:true,headset:true,autoListen:true}});
 try{f.w.LiveTalkEvent({type:'attached'});await f.wait(20);await f.click('mic');assert.equal(f.$('mic').textContent,'会話を終える');f.w.LiveTalkEvent({type:'routeLost'});await f.wait(30);assert.equal(f.$('headset').checked,false);assert.equal(f.$('mic').textContent,'会話を始める');assert.equal(f.$('errorPanel').hidden,false);const count=f.calls.filter(c=>c.command==='asrStart').length;await f.wait(900);assert.equal(f.calls.filter(c=>c.command==='asrStart').length,count);}finally{f.close();}
});
test('audio interruption stops playback without hiding the app as backgrounded',async()=>{
 const f=await app({agreed:true});
 try{f.w.LiveTalkEvent({type:'audioInterrupted'});await f.wait(20);assert.equal(f.$('read').disabled,false);assert.match(f.$('errorText').textContent,/中断/);assert.ok(f.calls.some(c=>c.command==='stop'));}finally{f.close();}
});

test('diagnostics never contain conversation text or raw exception secrets',async()=>{
 const secret='customer@example.com secret-response-456';
 const f=await app({agreed:true,handler:m=>{if(m.command==='synthesize')throw Error(secret);}});
 try{f.$('manual').value=secret;await f.click('read');await f.until(()=>!f.$('errorPanel').hidden);await f.click('diagnostics');const text=f.calls.filter(c=>c.command==='copy').at(-1).args.text;assert.equal(text.includes(secret),false);assert.equal(text.includes('customer@example.com'),false);}finally{f.close();}
});
test('invalid bridge snapshots are rejected without starting synthesis',async()=>{
 const f=await app({agreed:true,settings:{experimental:true}});
 try{for(const e of [null,{}, {type:'snapshot',text:42},{type:'snapshot',text:'長'.repeat(12001)}])f.w.LiveTalkEvent(e);await f.wait(20);assert.equal(f.calls.some(c=>c.command==='synthesize'),false);assert.equal(f.$('errorPanel').hidden,false);}finally{f.close();}
});

test('incoming shared text switches to reading without auto-playing untrusted content',async()=>{
 const f=await app({agreed:true});
 try{f.w.document.querySelector('[data-tab="voice"]').click();f.w.LiveTalkEvent({type:'sharedText',text:'ショートカットからの文章。'});await f.wait(20);assert.equal(f.$('call').hidden,false);assert.equal(f.$('manual').value,'ショートカットからの文章。');assert.equal(f.calls.some(c=>c.command==='play'),false);await f.click('read');await f.until(()=>f.calls.some(c=>c.command==='play'));}finally{f.close();}
});

test('voice attribution follows the selected speaker and terms remain accessible',async()=>{
 const f=await app({agreed:true,init:{asrAvailable:true,styles:[{name:'四国めたん',styles:[{id:2,name:'ノーマル'}]},{name:'ずんだもん',styles:[{id:3,name:'ノーマル'}]}]}});
 try{f.$('style').value='2';f.$('style').dispatchEvent(new f.w.Event('change'));assert.equal(f.$('credit').textContent,'音声：VOICEVOX:四国めたん');await f.click('licenses');assert.equal(f.calls.filter(c=>c.command==='showLicenses').length,1);}finally{f.close();}
});

test('silent volume yields an actionable explanation instead of apparent playback failure',async()=>{
 const f=await app({agreed:true,settings:{volume:0}});
 try{f.$('manual').value='聞こえるはずの文章。';await f.click('read');assert.match(f.$('errorText').textContent,/音量が0/);assert.equal(f.calls.some(c=>c.command==='play'),false);}finally{f.close();}
});
test('dynamic type changes enlarge the UI without altering settings or starting audio',async()=>{
 const f=await app({agreed:true});
 try{f.w.LiveTalkEvent({type:'fontScale',scale:1.6});assert.equal(f.w.document.documentElement.style.getPropertyValue('--text-scale'),'1.6');assert.equal(f.calls.some(c=>c.command==='play'),false);}finally{f.close();}
});

test('store flavor hides experimental integration even if old settings enabled it',async()=>{
 const f=await app({agreed:true,settings:{experimental:true},init:{experimentalAvailable:false,asrAvailable:true,styles:[{name:'ずんだもん',styles:[{id:3,name:'ノーマル'}]}]}});
 try{assert.equal(f.$('experimentalSection').hidden,true);assert.equal(f.$('modePicker').hidden,true);assert.equal(f.$('talkPane').hidden,true);assert.equal(f.$('paste').disabled,false);}finally{f.close();}
});

test('stop still stops audio if microphone shutdown reports an error',async()=>{
 const f=await app({agreed:true,handler:m=>{if(m.command==='asrStop')throw Error('microphone shutdown failed');}});
 try{const before=f.calls.filter(c=>c.command==='stop').length;await f.click('stop');assert.ok(f.calls.filter(c=>c.command==='stop').length>before);assert.equal(f.$('errorPanel').hidden,false);}finally{f.close();}
});
test('turning off experimental integration stops, detaches and ignores later reply events',async()=>{
 const f=await app({agreed:true,settings:{experimental:true}});
 try{f.w.LiveTalkEvent({type:'attached'});await f.wait(20);await f.click('mic');f.$('experimental').checked=false;f.$('experimental').dispatchEvent(new f.w.Event('change'));await f.wait(30);assert.ok(f.calls.some(c=>c.command==='chatDetach'));assert.equal(f.$('mic').textContent,'会話を始める');f.w.LiveTalkEvent({type:'waiting'});f.w.LiveTalkEvent({type:'start',id:'late'});f.w.LiveTalkEvent({type:'snapshot',id:'late',text:'停止後の回答。',done:true});await f.wait(30);assert.equal(f.calls.some(c=>c.command==='play'),false);}finally{f.close();}
});
