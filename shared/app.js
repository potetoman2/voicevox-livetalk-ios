'use strict';
const $=id=>document.getElementById(id),pending=new Map();
const S={ready:false,preparing:false,paired:false,listening:false,call:false,closed:false,state:'idle',asr:false,mode:'read'};
let config=LiveTalk.settings(),serial=0,eventChain=Promise.resolve(),toastTimer,listenTimer,lastVoice='',lastVoiceAt=0,retryAction=null,lastAction=null,saveTimer,saveChain=Promise.resolve(),saveVersion=0,micEpoch=0,micStarting=false,replyTimer,replyEpoch=0,acceptReplies=false,lastPlaybackAt=0;
function toast(text){$('toast').textContent=text;$('toast').hidden=false;clearTimeout(toastTimer);toastTimer=setTimeout(()=>$('toast').hidden=true,4500);}
function log(text){
 const safe=/^(チャット接続|質問送信|音声準備完了|音声の初回準備が必要|読み上げ音声に近い認識を除外|返答の更新に合わせて、未再生の音声を作り直しました)$/.test(String(text))?String(text):'処理エラー（画面の案内を確認）';
 const box=$('logs');box.textContent=(box.textContent+'\n'+new Date().toLocaleTimeString()+' '+safe).trim().split('\n').slice(-100).join('\n');
}
function native(command,args={}){
 return new Promise((resolve,reject)=>{
  const id=++serial,timer=setTimeout(()=>{pending.delete(id);reject(Error('処理を確認できませんでした。もう一度お試しください。'));},command==='init'&&args.interactive?900000:['showLicenses','confirmReset'].includes(command)?900000:['init','synthesize','asrStart'].includes(command)?120000:['play','importSettings'].includes(command)?300000:10000);
  pending.set(id,{resolve,reject,timer,command});const m=JSON.stringify({id,command,args});
  if(window.LiveTalkNative)window.LiveTalkNative.postMessage(m);
  else if(window.webkit?.messageHandlers?.native)window.webkit.messageHandlers.native.postMessage(m);
  else{clearTimeout(timer);pending.delete(id);reject(Error('iPhoneのLiveTalkアプリで開いてください。'));}
 });
}
window.LiveTalkReply=(id,result,error)=>{const p=pending.get(id);if(!p)return;clearTimeout(p.timer);pending.delete(id);if(error)p.reject(Error(error));else p.resolve(result);};
function update(){
 $('onboarding').hidden=S.ready;$('prepare').disabled=S.preparing;$('prepare').textContent=S.preparing?'準備しています…':'音声を準備する';
 $('onboardText').textContent=S.preparing?'初回は少し時間がかかります。この画面でお待ちください。':'このiPhoneの中で音声を作ります。最初に利用条件を確認してください。';
 const labels={idle:S.ready?'準備できました':'準備が必要',thinking:'返答を待っています',speaking:'読み上げ中',error:'確認が必要'};
 $('badge').textContent=S.listening?'聞いています':S.preparing?'準備中':labels[S.state];
 $('state').textContent=S.listening?'話し終わると質問を送ります':S.state==='speaking'?'好きな声で、読み上げています':S.state==='thinking'?(S.waiting?'ChatGPTの返答を待っています…':'文章を音声にしています…'):S.closed?'画面を閉じたため停止しました':S.ready?'読み上げできます':'「音声を準備する」を押してください';
 $('orb').classList.toggle('active',['thinking','speaking'].includes(S.state));
 $('mic').disabled=!S.ready||!S.paired||!S.asr||S.closed;$('mic').textContent=S.listening?'聞くのを止める':'話しかける';
 $('send').disabled=!S.ready||!S.paired||S.closed;
 $('read').disabled=!S.ready||S.closed;$('paste').disabled=!S.ready||S.closed;$('testVoice').disabled=!S.ready||S.closed;
 $('modePicker').hidden=!config.experimental;S.mode=config.experimental?S.mode:'read';
 $('readingPane').hidden=S.mode!=='read';$('talkPane').hidden=S.mode!=='talk';
 for(const [id,mode] of [['modeRead','read'],['modeTalk','talk']]){$(id).classList.toggle('selected',S.mode===mode);$(id).setAttribute('aria-pressed',String(S.mode===mode));}
 const selected=$('style').selectedOptions[0];$('credit').textContent=selected?'音声：VOICEVOX:'+selected.textContent.split(' / ')[0]:'音声：VOICEVOX';
 $('charCount').textContent=$('manual').value.length.toLocaleString()+' / 12,000';
}
function showError(e){
 if(e?.message==='cancelled')return;
 const message=String(e?.message||e).slice(0,500);log(message);
 $('errorText').textContent=message;$('errorPanel').hidden=false;$('errorPanel').focus();
 if(/許可されていません/.test(message)){retryAction=()=>native('openSettings');$('retry').textContent='iPhoneの設定を開く';}
 else if(/ChatGPT|チャット|返答を確認/.test(message)){retryAction=()=>native('chatOpen');$('retry').textContent='ChatGPTを確認';}
 else{retryAction=lastAction;$('retry').textContent='もう一度試す';}
 $('retry').hidden=!retryAction;S.call=false;update();
}
function clearReplyWait(){clearTimeout(replyTimer);replyEpoch++;S.waiting=false;}
function waitForReply(){
 clearReplyWait();S.waiting=true;S.state='thinking';update();const epoch=replyEpoch;
 replyTimer=setTimeout(()=>{if(epoch!==replyEpoch||!S.waiting)return;S.waiting=false;S.call=false;acceptReplies=false;S.state='idle';update();showError(Error('ChatGPTの返答を確認できませんでした。ChatGPT画面で通信エラーや利用上限を確認してください。'));},60000);
}
function laterListen(){clearTimeout(listenTimer);if(S.call&&config.autoListen&&!S.closed&&S.state==='idle')listenTimer=setTimeout(()=>{if(S.call&&S.state==='idle')startListening().catch(showError);},config.headset?450:Math.max(450,800-(Date.now()-lastPlaybackAt)));}
function cancelPending(commands){for(const [id,p] of pending)if(commands.includes(p.command)){clearTimeout(p.timer);pending.delete(id);p.reject(Error('cancelled'));}}
async function stopListening(){micEpoch++;micStarting=false;cancelPending(['asrStart']);S.listening=false;clearTimeout(listenTimer);update();await native('asrStop');}
async function startListening(){
 if(!S.ready||!S.paired||!S.asr)throw Error('音声を準備し、ChatGPTを接続してください。端末内の音声認識が使えない場合は文字で質問できます。');
 if(S.listening||micStarting||S.closed)return;if(S.state==='speaking'&&!config.headset)return;
 const epoch=++micEpoch;micStarting=true;
 try{await native('asrStart',{headset:config.headset,token:epoch});if(epoch===micEpoch&&S.call&&!S.closed){S.listening=true;update();}}finally{if(epoch===micEpoch)micStarting=false;}
}
const pipe=new LiveTalk.SpeechPipeline(native,(next,text)=>{
 if(S.state==='speaking'&&next==='idle')lastPlaybackAt=Date.now();S.state=next;update();
 if(next==='speaking'){lastVoice=text||'';lastVoiceAt=Date.now();if(!config.headset)stopListening().catch(showError);else if(S.call)startListening().catch(showError);}
 if(next==='idle')laterListen();
 if(next==='error')showError(Error(text||'音声を再生できませんでした。'));
},log);
window.LiveTalkEvent=event=>{
 if(!event||typeof event!=='object'||typeof event.type!=='string')return;
 if(['partial','asrFinal','snapshot','sharedText'].includes(event.type)&&(typeof event.text!=='string'||event.text.length>12000)){showError(Error('受け取った文章が長すぎるか、形式が正しくありません。'));return;}

 if(['partial','asrFinal','asrError','asrIdle'].includes(event.type)&&event.token!==undefined&&event.token!==micEpoch)return;
 if(event.type==='partial'){
  if(!S.call||S.closed||!S.listening)return;$('input').value=event.text||'';
  const heard=LiveTalk.canonical(event.text||''),echo=LiveTalk.canonical(lastVoice);
  if(config.headset&&S.state==='speaking'&&heard.length>=4&&Date.now()-lastVoiceAt>700&&!echo.includes(heard)){native('chatStop').catch(showError);pipe.stop().catch(showError);}return;
 }
 if(event.type==='asrFinal'){
  S.listening=false;update();if(!S.call||S.closed)return;const t=(event.text||'').trim();
  if(!t){laterListen();return;}
  if(config.headset&&LiveTalk.canonical(t).length>=4&&LiveTalk.canonical(lastVoice).includes(LiveTalk.canonical(t))&&Date.now()-lastVoiceAt<3000){log('読み上げ音声に近い認識を除外');laterListen();return;}
  $('input').value=t;send(t).catch(showError);return;
 }
 if(event.type==='asrError'){S.listening=false;S.call=false;update();showError(Error(event.message));return;}
 if(event.type==='asrIdle'){S.listening=false;update();laterListen();return;}
 if(event.type==='background'){S.closed=true;S.call=false;acceptReplies=false;clearReplyWait();saveNow().catch(showError);stopListening().catch(()=>{});pipe.stop().catch(()=>{});update();return;}
 if(event.type==='routeLost'||event.type==='audioInterrupted'){
  S.call=false;acceptReplies=false;clearReplyWait();config.headset=false;saveSoon();
  stopListening().catch(showError);pipe.stop().catch(showError);renderSettings();
  showError(Error(event.type==='routeLost'?'イヤホンが外れたため停止しました。接続し直すか、イヤホン設定を解除して再開してください。':'電話などで音声が中断されたため停止しました。再生ボタンで再開してください。'));return;
 }
 if(event.type==='fontScale'){const scale=Math.max(1,Math.min(2,Number(event.scale)||1));document.documentElement.style.setProperty('--text-scale',scale);return;}
 if(event.type==='foreground'){S.closed=false;update();return;}
 if(event.type==='sharedText'){try{$('manual').value=LiveTalk.inputText(event.text);}catch(e){showError(e);return;}S.mode='read';document.querySelector('[data-tab="call"]').click();update();toast('文章を受け取りました。「この文章を読み上げる」で再生できます。');return;}
 eventChain=eventChain.then(async()=>{
  if(event.type==='attached'){S.paired=true;acceptReplies=false;clearReplyWait();S.mode='talk';$('chatStatus').textContent='接続済み · 話しかけるか、文字で質問できます。';log('チャット接続');update();}
  else if(event.type==='detached'||event.type==='connectionError'){S.paired=false;S.call=false;acceptReplies=false;clearReplyWait();$('chatStatus').textContent=event.message||'未接続';await stopListening();await pipe.stop();if(!event.quiet)showError(Error(event.message));update();}
  else if(event.type==='waiting'&&S.paired&&!S.closed){acceptReplies=true;waitForReply();}
  else if(event.type==='start'&&acceptReplies&&S.paired&&!S.closed){clearReplyWait();await pipe.begin(event.id);}
  else if(event.type==='snapshot'&&acceptReplies&&!S.closed&&event.id===pipe.id){$('response').textContent=event.text;pipe.snapshot(event.text,event.done===true);}
  else if(event.type==='error'){clearReplyWait();acceptReplies=false;S.call=false;S.state='idle';update();showError(Error(event.message));}
 }).catch(showError);
};
async function send(text){
 text=LiveTalk.inputText(text);
 if(!S.paired||!S.ready)throw Error('ChatGPTを開いて、ログイン後「接続する」を押してください。');
 await stopListening();await pipe.stop();
 const outgoing=config.sendPersona?LiveTalk.PRESETS[config.persona].prompt+'\n\n'+text:text;
 acceptReplies=true;waitForReply();
 try{await native('chatSend',{text:outgoing});}catch(e){clearReplyWait();acceptReplies=false;S.state='idle';throw e;}S.call=true;if(config.thinking)native('cue').catch(showError);
 $('input').value='';log('質問送信');update();
}
function saveSoon(){
 clearTimeout(saveTimer);$('saveStatus').textContent='保存しています…';
 saveTimer=setTimeout(()=>saveNow().catch(showError),250);
}
function saveNow(){
 clearTimeout(saveTimer);const version=++saveVersion,value={...config};
 saveChain=saveChain.catch(()=>{}).then(()=>native('saveSettings',{settings:value}));
 return saveChain.then(()=>{if(version===saveVersion)$('saveStatus').textContent='自動保存済み';},e=>{$('saveStatus').textContent='保存できませんでした';throw e;});
}
function selectAvailableStyle(){
 const values=[...$('style').options].map(o=>Number(o.value));
 if(S.ready&&!values.includes(config.style))config.style=values[0];
}
function renderSettings(){
 $('persona').value=config.persona;$('style').value=String(config.style);
 for(const e of document.querySelectorAll('[data-setting]')){e.value=config[e.dataset.setting];$('out-'+e.dataset.setting).textContent=Number(config[e.dataset.setting]).toFixed(2);}
 for(const k of ['headset','autoListen','thinking','sendPersona','experimental'])$(k).checked=config[k]===true;
 pipe.configure(config);update();
}
const fields=[['speed','読む速さ',.5,2,.01],['pitch','声の高さ',-.15,.15,.005],['volume','音量',0,2,.01],['intonation','抑揚',0,2,.01],['emotion','感情の強さ',0,1,.01],['pre','読み始めの間（秒）',0,1,.01],['post','読み終わりの間（秒）',0,1,.01],['comma','読点の間（秒）',0,1,.01],['sentence','文末の間（秒）',0,1,.01]];
for(const [i,[key,label,min,max,step]] of fields.entries()){
 const l=document.createElement('label');l.textContent=label;const o=document.createElement('output');o.id='out-'+key;l.append(o);
 const e=document.createElement('input');e.type='range';Object.assign(e,{min,max,step});e.dataset.setting=key;e.id='setting-'+key;l.htmlFor=e.id;o.htmlFor=e.id;e.setAttribute('aria-describedby',o.id);e.setAttribute('aria-label',label);l.append(e);$(i<3?'sliders':'advancedSliders').append(l);
 e.oninput=()=>{config=LiveTalk.settings({...config,[key]:Number(e.value)});renderSettings();saveSoon();};
}
for(const [k,p] of Object.entries(LiveTalk.PRESETS))$('persona').add(new Option(p.label,k));
$('persona').onchange=()=>{const persona=$('persona').value,p=LiveTalk.PRESETS[persona];config=LiveTalk.settings({...config,persona,speed:p.speed,pitch:p.pitch,intonation:p.intonation});renderSettings();saveSoon();};
$('style').onchange=()=>{config.style=Number($('style').value);renderSettings();saveSoon();};
for(const k of ['headset','autoListen','thinking','sendPersona','experimental'])$(k).onchange=()=>{config[k]=$(k).checked;renderSettings();saveSoon();};
for(const b of document.querySelectorAll('[data-tab]'))b.onclick=()=>{for(const p of document.querySelectorAll('.page'))p.hidden=p.id!==b.dataset.tab;for(const n of document.querySelectorAll('[data-tab]')){n.classList.toggle('selected',n===b);n.setAttribute('aria-pressed',String(n===b));}};
function action(id,fn){$(id).onclick=async()=>{if($(id).dataset.busy)return;$(id).dataset.busy='1';try{lastAction=['prepare','read','paste','testVoice','save','chatOpen'].includes(id)?fn:null;await fn();}catch(e){showError(e);}finally{delete $(id).dataset.busy;update();}};}
action('chatOpen',()=>native('chatOpen'));
action('send',()=>send($('input').value));
action('mic',async()=>{if(S.listening){S.call=false;await stopListening();}else{await native('chatStop');await pipe.stop();S.call=true;await startListening();}});
action('stop',async()=>{S.call=false;acceptReplies=false;clearReplyWait();await stopListening();await pipe.stop();if(S.paired)await native('chatStop');toast('停止しました。');});
action('copyInput',async()=>{await native('copy',{text:$('input').value});toast('質問をコピーしました。');});
action('paste',async()=>{const text=LiveTalk.inputText(await native('paste'));$('manual').value=text;update();await read(text);});
action('read',()=>read($('manual').value));
async function read(text){text=LiveTalk.inputText(text);if(!S.ready)throw Error('最初に音声を準備してください。');if(config.volume===0)throw Error('音量が0になっています。設定で音量を上げてください。');S.call=false;acceptReplies=false;clearReplyWait();$('errorPanel').hidden=true;await stopListening();const id='manual:'+Date.now();if(await pipe.begin(id)){ $('response').textContent=text;pipe.snapshot(text,true); }}
action('testVoice',()=>read('こんにちは。好きな声で、いつもの返答を読み上げます。'));
action('save',async()=>{await saveNow();toast('設定を保存しました。');});
action('export',()=>native('exportSettings',{settings:config}));
action('import',async()=>{const imported=LiveTalk.importedSettings(await native('importSettings'));config=imported;selectAvailableStyle();renderSettings();await saveNow();toast('設定を読み込みました。');});
action('reset',async()=>{if(await native('confirmReset')){config=LiveTalk.settings();selectAvailableStyle();renderSettings();await saveNow();toast('初期設定に戻しました。');}});
action('licenses',()=>native('showLicenses'));
action('diagnostics',async()=>{await native('copy',{text:'LiveTalk 2.0\n'+$('capabilities').textContent+'\n'+$('logs').textContent});toast('診断をコピーしました。');});
$('clearLogs').onclick=()=>{$('logs').textContent='';};$('manual').oninput=update;
$('modeRead').onclick=()=>{S.mode='read';update();};$('modeTalk').onclick=()=>{S.mode='talk';update();};
$('dismissError').onclick=()=>{$('errorPanel').hidden=true;};$('retry').onclick=async()=>{const fn=retryAction;$('errorPanel').hidden=true;if(fn){try{await fn();}catch(e){showError(e);}}};
async function prepare(interactive=false){
 if(S.preparing)return;S.preparing=true;update();
 try{
  const result=await native('init',{interactive}),styles=[];
  for(const speaker of result?.styles||[])for(const style of speaker.styles||[])if(!style.type||style.type==='talk')styles.push({name:speaker.name+' / '+style.name,id:style.id});
  if(!styles.length)throw Error('読み上げる声が見つかりません。アプリを入れ直してお試しください。');
  $('style').replaceChildren();for(const style of styles)$('style').add(new Option(style.name,String(style.id)));
  if(!styles.some(s=>s.id===config.style))config.style=styles[0].id;
  S.ready=true;S.asr=result.asrAvailable===true;
  if(result.experimentalAvailable===false){config.experimental=false;$('experimentalSection').hidden=true;}
  $('capabilities').textContent='音声：準備済み · 端末内音声認識：'+(S.asr?'対応':'未対応（文字入力をご利用ください）');
  log('音声準備完了');renderSettings();
 }finally{S.preparing=false;update();}
}
action('prepare',()=>prepare(true));renderSettings();
(async()=>{
 try{config=LiveTalk.settings(await native('loadSettings'));renderSettings();$('saveStatus').textContent='設定を読み込みました';}catch(e){showError(e);}
 try{await prepare();}catch(e){$('capabilities').textContent=e.message;log('音声の初回準備が必要');if(!/利用条件/.test(e.message))showError(e);update();}
})();
