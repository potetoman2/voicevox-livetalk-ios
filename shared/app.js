'use strict';
const $=id=>document.getElementById(id), pending=new Map();let serial=0,closed=false,ready=false,paired=false,listening=false,call=false,state='idle',eventChain=Promise.resolve();
let config=LiveTalk.settings(),toastTimer,listenTimer,lastVoice='',lastVoiceAt=0;
function toast(text){$('toast').textContent=text;$('toast').hidden=false;clearTimeout(toastTimer);toastTimer=setTimeout(()=>$('toast').hidden=true,4500);}
function log(text){const box=$('logs');box.textContent=(box.textContent+'\n'+new Date().toLocaleTimeString()+' '+text).trim().split('\n').slice(-150).join('\n');box.scrollTop=box.scrollHeight;}
function native(command,args={}) {
  return new Promise((resolve,reject)=>{
    const id=++serial;
    const timer=setTimeout(()=>{pending.delete(id);reject(Error('処理がタイムアウトしました。準備・ログを確認してください'));},['synthesize','init','asrStart'].includes(command)?120000:['play','importSettings','exportSettings'].includes(command)?300000:10000);
    pending.set(id,{resolve,reject,timer});const message=JSON.stringify({id,command,args});
    if(window.LiveTalkNative)window.LiveTalkNative.postMessage(message);
    else if(window.webkit?.messageHandlers?.native)window.webkit.messageHandlers.native.postMessage(message);
    else {clearTimeout(timer);pending.delete(id);reject(Error('スマホアプリとして開いてください。ブラウザー表示は画面確認用です'));}
  });
}
window.LiveTalkReply=(id,result,error)=>{const p=pending.get(id);if(!p)return;clearTimeout(p.timer);pending.delete(id);if(error)p.reject(Error(error));else p.resolve(result);};
function laterListen(){clearTimeout(listenTimer);if(call&&config.autoListen&&!closed&&state==='idle')listenTimer=setTimeout(()=>{if(state==='idle')startListening().catch(showError);},450);}
async function stopListening(){listening=false;clearTimeout(listenTimer);await native('asrStop');$('mic').textContent='話しかける';}
async function startListening(){
  if(!ready)throw Error('先に音声を準備してください');
  if(!paired)throw Error('ChatGPT画面で「このチャットで通話」を押してください');
  if(listening||closed)return;
  if(state==='speaking'&&!config.headset)return;
  await native('asrStart',{headset:config.headset});listening=true;$('mic').textContent='聞いています…';$('badge').textContent='聞いています';
}
function showError(e){log(e.message||String(e));toast(e.message||String(e));}
const pipe=new LiveTalk.SpeechPipeline(native,(next,text)=>{
  state=next;$('badge').textContent=({idle:'待機中',thinking:'返答を待っています',speaking:'読み上げ中',error:'確認が必要'})[next];
  $('state').textContent=({idle:'次は、何を話そう。',thinking:'返答を待っています…',speaking:'VOICEVOXで話しています',error:'準備・ログを確認してください'})[next];
  $('orb').classList.toggle('active',next==='speaking'||next==='thinking');
  if(next==='speaking'){
    lastVoice=text||'';lastVoiceAt=Date.now();
    if(!config.headset)stopListening().catch(showError);else if(call)startListening().catch(showError);
  }
  if(next==='idle')laterListen();
},log);
window.LiveTalkEvent=event=>{
  if(event.type==='partial'){
    $('input').value=event.text;
    const heard=LiveTalk.canonical(event.text),echo=LiveTalk.canonical(lastVoice);
    if(config.headset&&state==='speaking'&&heard.length>=4&&Date.now()-lastVoiceAt>700&&!echo.includes(heard)) {
      native('chatStop').catch(showError);pipe.stop().catch(showError);
    }
    return;
  }
  if(event.type==='asrFinal'){
    if(!call||closed)return;
    listening=false;$('mic').textContent='話しかける';const t=(event.text||'').trim();
    if(!t){laterListen();return;}
    if(config.headset&&LiveTalk.canonical(t).length>=4&&LiveTalk.canonical(lastVoice).includes(LiveTalk.canonical(t))&&Date.now()-lastVoiceAt<3000){log('読み上げ音声に近い認識結果を除外しました');if(call)startListening().catch(showError);return;}
    $('input').value=t;send(t).catch(showError);return;
  }
  if(event.type==='asrError'){listening=false;call=false;showError(Error(event.message));return;}
  if(event.type==='asrIdle'){listening=false;if(state==='idle')laterListen();return;}
  if(event.type==='background'){closed=true;call=false;stopListening().catch(()=>{});pipe.stop().catch(()=>{});return;}
  if(event.type==='foreground'){closed=false;return;}
  if(event.type==='sharedText'){$('manual').value=event.text;toast('共有された文章を「読み上げる」で再生できます');return;}
  eventChain=eventChain.then(async()=>{
    if(event.type==='attached'){paired=true;$('chatStatus').textContent='このチャットに接続しました';log('ChatGPTのチャットを接続しました');}
    else if(event.type==='detached'){paired=false;call=false;await stopListening();await pipe.stop();showError(Error(event.message));}
    else if(event.type==='start'){await pipe.begin(event.id);}
    else if(event.type==='snapshot'){if(event.id===pipe.id){$('response').textContent=event.text;pipe.snapshot(event.text,event.done===true);}}
    else if(event.type==='error')showError(Error(event.message));
  }).catch(showError);
};
async function send(text){
  if(!text.trim())return;
  if(!paired)throw Error('ChatGPT画面で使うチャットを選んでください。外部アプリの場合は「質問をコピー」を使えます');
  if(!ready)throw Error('先に音声を準備してください');
  await stopListening();await pipe.stop();
  const outgoing=config.sendPersona?LiveTalk.PRESETS[config.persona].prompt+'\n\n'+text:text;
  await native('chatSend',{text:outgoing});call=true;
  if(config.thinking)native('cue').catch(showError);
  $('input').value='';log('質問を送信しました');
}
function renderSettings(){
  $('persona').value=config.persona;
  $('style').value=String(config.style);
  for(const el of document.querySelectorAll('[data-setting]')){const key=el.dataset.setting;el.value=config[key];$('out-'+key).textContent=Number(config[key]).toFixed(2);}
  for(const key of ['headset','autoListen','thinking','sendPersona'])$(key).checked=config[key];
  pipe.configure(config);
}
const fields=[['speed','話速',0.5,2,0.01],['pitch','声の高さ',-0.15,0.15,0.005],['intonation','抑揚',0,2,0.01],['volume','音量',0,2,0.01],['emotion','感情の強さ',0,1,0.01],['pre','読み始めの間（秒）',0,1,0.01],['post','読み終わりの間（秒）',0,1,0.01],['comma','読点の間（秒）',0,1,0.01],['sentence','文末の間（秒）',0,1,0.01]];
for(const [key,label,min,max,step] of fields){
  const l=document.createElement('label');l.textContent=label;
  const output=document.createElement('output');output.id='out-'+key;l.append(output);
  const input=document.createElement('input');input.type='range';input.min=min;input.max=max;input.step=step;input.dataset.setting=key;input.setAttribute('aria-label',label);l.append(input);$('sliders').append(l);
  input.addEventListener('input',()=>{config=LiveTalk.settings({...config,[key]:Number(input.value)});renderSettings();});
}
for(const [key,p] of Object.entries(LiveTalk.PRESETS)){$('persona').add(new Option(p.label,key));}
$('persona').onchange=()=>{const persona=$('persona').value,p=LiveTalk.PRESETS[persona];config=LiveTalk.settings({...config,persona,speed:p.speed,pitch:p.pitch,intonation:p.intonation});renderSettings();};
$('style').onchange=()=>{config.style=Number($('style').value);renderSettings();};
for(const key of ['autoListen','headset','thinking','sendPersona'])$(key).onchange=()=>{config[key]=$(key).checked;renderSettings();};
for(const b of document.querySelectorAll('[data-tab]'))b.onclick=()=>{for(const p of document.querySelectorAll('.page'))p.hidden=p.id!==b.dataset.tab;for(const n of document.querySelectorAll('[data-tab]'))n.classList.toggle('selected',n===b);};
const action=(id,fn)=>$(id).onclick=()=>Promise.resolve().then(fn).catch(showError);
action('chatOpen',()=>native('chatOpen'));
action('send',()=>send($('input').value));
action('mic',async()=>{call=true;if(listening)await stopListening();else{await native('chatStop');await pipe.stop();await startListening();}});
action('stop',async()=>{call=false;await stopListening();await pipe.stop();if(paired)await native('chatStop');toast('停止しました。「話しかける」で会話を再開できます');});
action('copyInput',async()=>{await native('copy',{text:$('input').value});toast('質問をコピーしました');});
action('paste',async()=>{$('manual').value=await native('paste');});
action('read',async()=>{call=false;await stopListening();await pipe.begin('manual');$('response').textContent=$('manual').value;pipe.snapshot($('manual').value,true);});
action('testVoice',async()=>{call=false;await stopListening();await pipe.begin('test');pipe.snapshot('こんにちは。スマホの中で、VOICEVOXが話しています。',true);});
action('save',async()=>{await native('saveSettings',{settings:config});toast('設定を保存しました');});
action('export',()=>native('exportSettings',{settings:config}));
action('import',async()=>{config=LiveTalk.settings(await native('importSettings'));renderSettings();await native('saveSettings',{settings:config});toast('設定を読み込みました');});
$('clearLogs').onclick=()=>{$('logs').textContent='';};
async function prepare(interactive=false){
  $('badge').textContent='音声を準備しています';const result=await native('init',{interactive});
  ready=true;$('style').replaceChildren();
  for(const speaker of result.styles||[])for(const style of speaker.styles||[])if(!style.type||style.type==='talk')$('style').add(new Option(speaker.name+' / '+style.name,String(style.id)));
  if(!$('style').querySelector('option[value="'+config.style+'"]'))config.style=Number($('style').options[0]?.value||0);
  $('mic').disabled=!result.asrAvailable;$('capabilities').textContent=result.platform+' / VOICEVOX準備済み / 端末内音声認識：'+(result.asrAvailable?'対応':'未対応（文字入力をご利用ください）');
  log('音声モデルを読み込みました');$('badge').textContent='待機中';renderSettings();
}
action('prepare',()=>prepare(true));
renderSettings();
(async()=>{try{const saved=await native('loadSettings');config=LiveTalk.settings(saved);renderSettings();await prepare();}catch(e){$('badge').textContent='準備が必要';$('capabilities').textContent=e.message;log(e.message);}})();
