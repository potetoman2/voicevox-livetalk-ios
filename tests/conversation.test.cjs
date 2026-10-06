const {test}=require('node:test'),assert=require('node:assert/strict'),{app}=require('./app-fixture.cjs');
const init={planUsageAvailable:true,experimentalAvailable:true,asrAvailable:true,styles:[{name:'ずんだもん',styles:[{id:3,name:'ノーマル'}]}]};
const signed={authenticated:true,account:'テスト用アカウント',accounts:[{id:'fixture-client',label:'テスト用アカウント'}],selectedAccount:'fixture-client',models:[{id:'fixture-model',label:'会話モデル'}],model:'fixture-model'};
const event=(f,e)=>f.w.LiveTalkEvent({...e,provider:'official'});
async function connected(handler){
 const f=await app({agreed:true,init,handler:m=>m.command==='gptStatus'?signed:handler?.(m)});
 await f.until(()=>!f.$('mic').disabled);return f;
}
test('official connection requires validated login and never silently opens the web bridge',async()=>{
 const f=await app({agreed:true,init,handler:m=>m.command==='gptStatus'?{authenticated:false}:m.command==='gptSignIn'?signed:undefined});
 try{await f.until(()=>!f.$('chatOpen').disabled);assert.equal(f.$('mic').disabled,true);await f.click('chatOpen');assert.equal(f.$('mic').disabled,false);assert.ok(f.calls.some(c=>c.command==='gptSignIn'));assert.equal(f.calls.some(c=>c.command==='chatOpen'),false);}finally{f.close();}
});
test('official voice input sends recognized words directly and plays before the reply completes',async()=>{
 const f=await connected();
 try{await f.click('mic');const token=f.calls.filter(c=>c.command==='asrStart').at(-1).args.token;event(f,{type:'asrFinal',token,text:'今日のお昼、何にしよう？'});await f.until(()=>f.calls.some(c=>c.command==='gptSend'));const send=f.calls.find(c=>c.command==='gptSend');assert.equal(send.args.text,'今日のお昼、何にしよう？');assert.equal(f.calls.some(c=>c.command==='chatSend'||c.command==='paste'),false);assert.match(send.args.instructions,/自然な音声会話/);event(f,{type:'start',id:'reply'});event(f,{type:'snapshot',id:'reply',text:'今日は温かいスープはどう？',done:false});await f.until(()=>f.calls.some(c=>c.command==='play'));assert.equal(f.$('errorPanel').hidden,true);}finally{f.close();}
});
test('one start supports two spoken turns without a second microphone button press',async()=>{
 const f=await connected();
 try{await f.click('mic');let token=f.calls.filter(c=>c.command==='asrStart').at(-1).args.token;event(f,{type:'asrFinal',token,text:'こんにちは。'});await f.until(()=>f.calls.some(c=>c.command==='gptSend'));event(f,{type:'start',id:'first'});event(f,{type:'snapshot',id:'first',text:'こんにちは。元気ですか？',done:true});await f.until(()=>f.calls.filter(c=>c.command==='asrStart').length>=2);token=f.calls.filter(c=>c.command==='asrStart').at(-1).args.token;event(f,{type:'asrFinal',token,text:'元気だよ。'});await f.until(()=>f.calls.filter(c=>c.command==='gptSend').length===2);assert.equal(f.calls.filter(c=>c.command==='gptSend')[1].args.text,'元気だよ。');assert.equal(f.calls.some(c=>c.command==='paste'),false);}finally{f.close();}
});
test('ending while an official send is awaiting acknowledgement cannot restart the microphone',async()=>{
 let finish;const f=await connected(m=>m.command==='gptSend'?new Promise(r=>finish=r):undefined);
 try{f.$('input').value='質問';f.$('send').click();await f.until(()=>finish);await f.click('stop');finish(true);event(f,{type:'start',id:'late'});event(f,{type:'snapshot',id:'late',text:'停止後の返答。',done:true});await f.wait(800);assert.equal(f.calls.some(c=>c.command==='play'||c.command==='asrStart'),false);assert.equal(f.$('mic').textContent,'会話を始める');}finally{f.close();}
});
test('a mid-stream usage failure stops queued audio and offers usage management',async()=>{
 const f=await connected();
 try{await f.click('mic');const token=f.calls.find(c=>c.command==='asrStart').args.token;event(f,{type:'asrFinal',token,text:'質問。'});await f.until(()=>f.calls.some(c=>c.command==='gptSend'));event(f,{type:'start',id:'failed'});event(f,{type:'snapshot',id:'failed',text:'途中の返答です。',done:false});await f.until(()=>f.calls.some(c=>c.command==='play'));event(f,{type:'error',message:'ChatGPTの利用上限に達しました。'});await f.until(()=>!f.$('errorPanel').hidden);const count=f.calls.filter(c=>c.command==='asrStart').length;await f.wait(800);assert.equal(f.calls.filter(c=>c.command==='asrStart').length,count);await f.click('retry');assert.equal(f.calls.filter(c=>c.command==='gptManageUsage').length,1);assert.equal(f.calls.some(c=>c.command==='gptSignIn'),false);}finally{f.close();}
});
test('logout suppresses late official snapshots and clears account readiness',async()=>{
 const f=await connected(m=>m.command==='gptSignOut'?{authenticated:false,accounts:signed.accounts,remoteRevoked:true}:undefined);
 try{await f.click('signOut');event(f,{type:'waiting'});event(f,{type:'start',id:'late'});event(f,{type:'snapshot',id:'late',text:'ログアウト後の返答。',done:true});await f.wait(40);assert.equal(f.$('mic').disabled,true);assert.equal(f.calls.some(c=>c.command==='play'),false);}finally{f.close();}
});
test('headset interruption cancels the official request rather than the web bridge',async()=>{
 let playResolve;const f=await connected(m=>m.command==='play'?new Promise(r=>playResolve=r):undefined);
 try{f.$('callHeadset').checked=true;f.$('callHeadset').dispatchEvent(new f.w.Event('change'));await f.click('mic');const token=f.calls.find(c=>c.command==='asrStart').args.token;event(f,{type:'asrFinal',token,text:'最初の質問。'});await f.until(()=>f.calls.some(c=>c.command==='gptSend'));event(f,{type:'start',id:'interrupt'});event(f,{type:'snapshot',id:'interrupt',text:'長いお返事をしています。',done:false});await f.until(()=>playResolve);await f.until(()=>f.calls.filter(c=>c.command==='asrStart').length>=2);await f.wait(550);const listeningToken=f.calls.filter(c=>c.command==='asrStart').at(-1).args.token;const before=f.calls.filter(c=>c.command==='gptStop').length;event(f,{type:'partial',token:listeningToken,text:'別の質問をするね'});await f.until(()=>f.calls.filter(c=>c.command==='gptStop').length>before);assert.equal(f.calls.some(c=>c.command==='chatStop'),false);playResolve(true);await f.wait(30);await f.click('stop');await f.wait(20);}finally{f.close();}
});
