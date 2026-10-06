'use strict';
const $=id=>document.getElementById(id),pending=new Map();
const S={ready:false,preparing:false,paired:false,listening:false,call:false,closed:false,state:'idle',asr:false,mode:'talk',callAvailable:true,planAvailable:false,provider:'web',authenticating:false,models:[],phase:'',metrics:{}};
let config=LiveTalk.settings(),serial=0,eventChain=Promise.resolve(),toastTimer,listenTimer,lastVoice='',lastVoiceAt=0,retryAction=null,lastAction=null,saveTimer,saveChain=Promise.resolve(),saveVersion=0,micEpoch=0,micStarting=false,replyTimer,replyEpoch=0,acceptReplies=false,lastPlaybackAt=0,callEpoch=0,sentAt=0,firstVoiceAt=0,feedbackWarmTimer;
let commerce={entitlement:'checking',available:false,busy:false,privacyBusy:false,preview:true},commerceContext='';
function toast(text){$('toast').textContent=text;$('toast').hidden=false;clearTimeout(toastTimer);toastTimer=setTimeout(()=>$('toast').hidden=true,4500);}
function log(text){
 const safe=/^(チャット接続|質問送信|音声準備完了|音声の初回準備が必要|読み上げ音声に近い認識を除外|返答の更新に合わせて、未再生の音声を作り直しました)$/.test(String(text))?String(text):'処理エラー（画面の案内を確認）';
 const box=$('logs');box.textContent=(box.textContent+'\n'+new Date().toLocaleTimeString()+' '+safe).trim().split('\n').slice(-100).join('\n');
}
function native(command,args={}){
 return new Promise((resolve,reject)=>{
  const id=++serial,timer=setTimeout(()=>{pending.delete(id);reject(Error('処理を確認できませんでした。もう一度お試しください。'));},command==='init'&&args.interactive?900000:['showLicenses','showPrivacy','showTerms','showAdLicenses','deleteLocalData','confirmReset','gptSignIn','purchaseAdRemoval','restorePurchases','adEnable','adPrivacy'].includes(command)?900000:['init','synthesize','asrStart','gptStatus','gptAccount','gptSignOut','gptSend','commerceRefresh'].includes(command)?180000:['play','importSettings'].includes(command)?300000:10000);
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
 const labels={idle:S.ready?(S.paired?'会話できます':'未接続'):'準備が必要',thinking:'返答を待っています',speaking:'返答しています',error:'確認が必要'};
 $('badge').textContent=S.listening?'聞いています':S.preparing?'準備中':labels[S.state];
 $('state').textContent=S.listening?'聞いています。話し終わると返答します。':S.state==='speaking'?'VOICEVOXの声で返答しています':S.state==='thinking'?(S.phase==='searching'?'ネットで調べています…':S.waiting?'ChatGPTの返答を待っています…':'返答を音声にしています…'):S.closed?'画面を閉じたため停止しました':S.paired?'接続済み。会話を始められます。':S.ready?'ChatGPTへの接続が必要です':'「音声を準備する」を押してください';
 $('orb').classList.toggle('active',S.listening||['thinking','speaking'].includes(S.state));
 $('callTitle').textContent=S.listening?'うん、聞いています。':S.state==='speaking'?'お返事しています。':S.state==='thinking'?'少し考えています。':'今日は、何を話そう？';
 $('mic').disabled=!S.ready||!S.paired||!S.asr||S.closed||commerce.busy||commerce.privacyBusy;
 $('mic').textContent=S.listening?'会話を終える':S.call?'話し始める（割り込み）':'会話を始める';
 $('callHint').textContent=!S.callAvailable?'この配布版では音声会話を利用できません。':!S.ready?'最初に音声を準備してください。':!S.paired?'ChatGPTへ接続すると、声で会話を始められます。':!S.asr?'この端末では音声認識を利用できません。':S.call?(config.headset?'返答中も話しかけられます。':'返答のあと、自動で聞き始めます。割り込むときはボタンを押してください。'):'一度始めると、話す・返答するを続けられます。';
 $('chatOpen').disabled=!S.callAvailable||S.closed||S.authenticating;$('chatOpen').textContent=S.authenticating?'接続を確認しています…':S.planAvailable?'Continue with ChatGPT':S.paired?'接続を確認する':'ChatGPTへの接続を試す';
 $('planHint').hidden=!S.planAvailable;$('accountSection').hidden=!S.planAvailable;
 $('send').disabled=!S.ready||!S.paired||S.closed;
 $('read').disabled=!S.ready||S.closed;$('paste').disabled=!S.ready||S.closed;$('testVoice').disabled=!S.ready||S.closed;
 $('modePicker').hidden=true;
 $('readingPane').hidden=false;$('talkPane').hidden=!S.callAvailable;
 if(!S.callAvailable)$('manualTool').open=true;
 document.querySelector('[data-tab="call"]').textContent=S.callAvailable?'会話':'読み上げ';
 for(const [id,mode] of [['modeRead','read'],['modeTalk','talk']]){$(id).classList.toggle('selected',S.mode===mode);$(id).setAttribute('aria-pressed',String(S.mode===mode));}
 const selected=$('style').selectedOptions[0];$('credit').textContent=selected?'音声：VOICEVOX:'+selected.textContent.split(' / ')[0]:'音声：VOICEVOX';
 $('charCount').textContent=$('manual').value.length.toLocaleString()+' / 12,000';
 renderCommerce();syncCommerceContext();
}
function renderCommerce(){
 const removed=commerce.entitlement==='removed',busy=commerce.busy||commerce.privacyBusy;
 $('purchaseStatus').textContent=removed?'広告なしで利用中':busy?'確認しています…':commerce.pending?'Appleの購入承認を待っています。':commerce.entitlement==='checking'?'購入状態を確認しています。':commerce.preview?'公開準備版 · 実際の購入はできません。':'無料版で利用中';
 $('removeAds').textContent=removed?'広告除去は購入済み':commerce.available&&commerce.price?'広告を外す · '+commerce.price+'（買い切り）':commerce.preview?'公開版で購入できます':'購入情報を再確認';
 $('removeAds').disabled=removed||busy||commerce.entitlement==='checking'||commerce.preview||S.closed;
 $('restorePurchases').disabled=busy||commerce.preview||S.closed;
 $('purchaseNote').textContent=commerce.preview?'公開時の日本向け価格は980円を予定しています。この版では料金は発生しません。':'購入画面に表示されるApp Storeの価格が適用されます。返金後は広告除去が取り消されます。';
 $('adEnable').textContent=commerce.preview?'テスト広告の表示を確認する':'無料版の広告設定';
 $('adEnable').disabled=removed||busy||commerce.entitlement==='checking'||S.closed;
 $('adPrivacy').disabled=busy||S.closed;
 if(commerce.adFailed&&!busy)$('purchaseStatus').textContent+=' · 広告を読み込めません。会話は使えます。';
}
function setCommerce(value){
 if(!value||typeof value!=='object')return;
 commerce={entitlement:['checking','free','removed'].includes(value.entitlement)?value.entitlement:'checking',available:value.available===true,busy:value.busy===true,privacyBusy:value.privacyBusy===true,preview:value.preview!==false,price:typeof value.price==='string'?value.price.slice(0,40):'',pending:value.pending===true,adFailed:value.adFailed===true};update();
}
function syncCommerceContext(){
 const args={settingsVisible:!$('voice').hidden,conversationActive:S.call||S.listening||micStarting||S.authenticating||['thinking','speaking'].includes(S.state)};
 const key=JSON.stringify(args);if(key===commerceContext)return;commerceContext=key;
 native('commerceContext',args).catch(()=>{if(commerceContext===key)commerceContext='';});
}
function showError(e){
 if(e?.message==='cancelled')return;
 const message=String(e?.message||e).slice(0,500);log(message);
 $('errorText').textContent=message;$('errorPanel').hidden=false;$('errorPanel').focus();
 if(/許可されていません/.test(message)){retryAction=()=>native('openSettings');$('retry').textContent='iPhoneの設定を開く';}
 else if(/利用上限|利用枠を使えません/.test(message)&&S.planAvailable){retryAction=()=>native('gptManageUsage');$('retry').textContent='利用枠を確認';$('manageUsage').hidden=false;}
 else if(/ChatGPT|チャット|返答を確認/.test(message)){retryAction=()=>connect();$('retry').textContent='ChatGPTの接続を確認';}
 else{retryAction=lastAction;$('retry').textContent='もう一度試す';}
 $('retry').hidden=!retryAction;const active=S.call||acceptReplies;S.call=false;update();if(active)halt().catch(()=>{});
}
function clearReplyWait(){clearTimeout(replyTimer);replyEpoch++;S.waiting=false;}
function waitForReply(){
 clearReplyWait();S.waiting=true;S.state='thinking';update();const epoch=replyEpoch;
 replyTimer=setTimeout(()=>{if(epoch!==replyEpoch||!S.waiting)return;S.waiting=false;S.call=false;acceptReplies=false;S.state='idle';update();showError(Error('ChatGPTの返答を確認できませんでした。ChatGPT画面で通信エラーや利用上限を確認してください。'));},60000);
}
function laterListen(){clearTimeout(listenTimer);if(S.call&&config.autoListen&&!S.closed&&S.state==='idle')listenTimer=setTimeout(()=>{if(S.call&&S.state==='idle')startListening().catch(showError);},config.headset?120:Math.max(220,420-(Date.now()-lastPlaybackAt)));}
function heardText(){return pipe.text.slice(0,LiveTalk.rawOffset(pipe.text,pipe.heard));}
function stopGPT(){return S.provider==='official'?native('gptStop',{heard:heardText(),responseID:pipe.id}):native('chatStop');}
function cancelPending(commands){for(const [id,p] of pending)if(commands.includes(p.command)){clearTimeout(p.timer);pending.delete(id);p.reject(Error('cancelled'));}}
async function stopListening(){micEpoch++;micStarting=false;cancelPending(['asrStart']);S.listening=false;clearTimeout(listenTimer);update();await native('asrStop');}
async function startListening(){
 if(!S.ready||!S.paired||!S.asr)throw Error('音声を準備し、ChatGPTを接続してください。端末内の音声認識が使えない場合は文字で質問できます。');
 if(S.listening||micStarting||S.closed)return;if(S.state==='speaking'&&!config.headset)return;
 const epoch=++micEpoch;micStarting=true;
 try{await native('asrStart',{headset:config.headset,token:epoch,tempo:config.tempo});if(epoch===micEpoch&&S.call&&!S.closed){S.listening=true;update();}}finally{if(epoch===micEpoch)micStarting=false;}
}
const pipe=new LiveTalk.SpeechPipeline(native,(next,text)=>{
 if(S.state==='speaking'&&next==='idle')lastPlaybackAt=Date.now();S.state=next;update();
 if(next==='speaking'){lastVoice=text||'';lastVoiceAt=Date.now();if(!config.headset)stopListening().catch(showError);else if(S.call)startListening().catch(showError);}
 if(next==='idle')laterListen();
 if(next==='error')showError(Error(text||'音声を再生できませんでした。'));
},log);
window.LiveTalkEvent=event=>{
 if(!event||typeof event!=='object'||typeof event.type!=='string')return;
 if(event.type==='commerce'){setCommerce(event.value);return;}
 if(event.type==='adOverlay'){halt().catch(showError);toast('広告を開くため、会話を終了しました。');return;}
 if(['attached','detached','connectionError','waiting','start','snapshot','phase','sources','timing','searchUnavailable','error'].includes(event.type)){
  if(event.provider==='official'){if(!S.planAvailable)return;}
  else if(S.provider==='official'||(['attached','waiting','start','snapshot'].includes(event.type)&&!config.experimental))return;
 }
 if(['partial','asrFinal','snapshot','sharedText'].includes(event.type)&&(typeof event.text!=='string'||event.text.length>12000)){showError(Error('受け取った文章が長すぎるか、形式が正しくありません。'));return;}

 if(['partial','asrFinal','asrError','asrIdle'].includes(event.type)&&event.token!==undefined&&event.token!==micEpoch)return;
 if(event.type==='partial'){
  if(!S.call||S.closed||!S.listening)return;$('input').value=event.text||'';
  const heard=LiveTalk.canonical(event.text||''),echo=LiveTalk.canonical(lastVoice);
  if(config.headset&&S.state==='speaking'&&heard.length>=4&&Date.now()-lastVoiceAt>500&&!echo.includes(heard)){acceptReplies=false;clearReplyWait();stopGPT().catch(showError);pipe.stop().catch(showError);}return;
 }
 if(event.type==='asrFinal'){
  S.listening=false;update();if(!S.call||S.closed)return;const t=(event.text||'').trim();
  if(!t){laterListen();return;}
  if(config.headset&&LiveTalk.canonical(t).length>=4&&LiveTalk.canonical(lastVoice).includes(LiveTalk.canonical(t))&&Date.now()-lastVoiceAt<3000){log('読み上げ音声に近い認識を除外');laterListen();return;}
  $('input').value=t;send(t).catch(showError);return;
 }
 if(event.type==='asrError'){S.listening=false;S.call=false;update();showError(Error(event.message));return;}
 if(event.type==='asrIdle'){S.listening=false;update();laterListen();return;}
 if(event.type==='background'){callEpoch++;S.closed=true;S.call=false;acceptReplies=false;clearReplyWait();saveNow().catch(showError);stopGPT().catch(()=>{});stopListening().catch(()=>{});pipe.stop().catch(()=>{});update();return;}
 if(event.type==='routeLost'||event.type==='audioInterrupted'){
  callEpoch++;S.call=false;acceptReplies=false;clearReplyWait();config.headset=false;saveSoon();stopGPT().catch(showError);
  stopListening().catch(showError);pipe.stop().catch(showError);renderSettings();
  showError(Error(event.type==='routeLost'?'イヤホンが外れたため停止しました。接続し直すか、イヤホン設定を解除して再開してください。':'電話などで音声が中断されたため停止しました。再生ボタンで再開してください。'));return;
 }
 if(event.type==='fontScale'){const scale=Math.max(1,Math.min(2,Number(event.scale)||1));document.documentElement.style.setProperty('--text-scale',scale);return;}
 if(event.type==='audioStarted'){if(acceptReplies&&event.generation===pipe.generation&&sentAt&&!firstVoiceAt){firstVoiceAt=Date.now();S.metrics.voiceMs=firstVoiceAt-sentAt;renderLatency();}return;}
 if(event.type==='carplayResponse'){if(typeof event.text==='string'&&event.text.length<=12000){$('response').textContent=event.text;renderSources(event.sources);}return;}
 if(event.type==='carplay'){S.closed=event.active===true;S.call=false;acceptReplies=false;clearReplyWait();$('carplayStatus').textContent=S.closed?'CarPlayで会話中です。iPhoneでの会話は停止しています。':'CarPlayとの接続を終了しました。';update();return;}
 if(event.type==='foreground'){S.closed=false;update();return;}
 if(event.type==='sharedText'){try{$('manual').value=LiveTalk.inputText(event.text);}catch(e){showError(e);return;}$('manualTool').open=true;document.querySelector('[data-tab="call"]').click();update();toast('文章を受け取りました。「この文章を読み上げる」で再生できます。');return;}
 eventChain=eventChain.then(async()=>{
  if(event.type==='attached'){S.provider=event.provider==='official'?'official':'web';S.paired=true;acceptReplies=false;clearReplyWait();S.mode='talk';$('chatStatus').textContent=S.provider==='official'?'接続済み · ChatGPTの利用枠で会話できます。':'実験接続済み · ChatGPT画面との連携です。';log('チャット接続');update();}
  else if(event.type==='detached'||event.type==='connectionError'){S.paired=false;S.call=false;acceptReplies=false;clearReplyWait();$('chatStatus').textContent=event.message||'未接続';await stopListening();await pipe.stop();if(!event.quiet)showError(Error(event.message));update();}
  else if(event.type==='waiting'&&S.paired&&!S.closed){acceptReplies=true;waitForReply();}
  else if(event.type==='start'&&acceptReplies&&S.paired&&!S.closed){clearReplyWait();S.phase='';$('sources').replaceChildren();await pipe.begin(event.id,true);}
  else if(event.type==='phase'&&acceptReplies&&event.id===pipe.id){S.phase=event.phase==='searching'?'searching':'';S.waiting=true;if(S.phase==='searching')native('feedbackSearch',{generation:pipe.generation}).catch(()=>{});update();}
  else if(event.type==='searchUnavailable'&&acceptReplies&&event.id===pipe.id){toast('このモデルではネット検索を使えないため、通常の会話で返答します。');}
  else if(event.type==='sources'&&acceptReplies&&event.id===pipe.id){renderSources(event.sources);}
  else if(event.type==='timing'&&acceptReplies&&event.id===pipe.id){S.metrics.textMs=Math.max(0,Number(event.firstTextMs)||0);renderLatency();}
  else if(event.type==='snapshot'&&acceptReplies&&!S.closed&&event.id===pipe.id){S.phase='';if(LiveTalk.speakable(event.text).trim()||event.done)native('feedbackStop').catch(()=>{});$('response').textContent=LiveTalk.speakable(event.text);pipe.snapshot(event.text,event.done===true);}
  else if(event.type==='error'){await halt().catch(()=>{});S.state='idle';update();showError(Error(event.message));}
 }).catch(showError);
};
async function send(text){
 text=LiveTalk.inputText(text);
 if(!S.paired||!S.ready)throw Error('ChatGPTを開いて、ログイン後「接続する」を押してください。');
 const epoch=callEpoch;
 await stopListening();await pipe.stop();
 if(epoch!==callEpoch||S.closed)return;
 const outgoing=config.sendPersona?LiveTalk.PRESETS[config.persona].prompt+'\n\n'+text:text;
 acceptReplies=true;sentAt=Date.now();firstVoiceAt=0;S.metrics={};S.phase='';waitForReply();
 $('heard').textContent='聞き取った内容：'+text;$('heard').hidden=false;
 native('feedbackBegin',{generation:pipe.generation,text,webSearch:config.webSearch,settings:config,enabled:config.feedback}).catch(()=>{});
 const instructions=LiveTalk.PRESETS[config.persona].prompt+'\n自然な音声会話として、原則1〜3文の短い返答にしてください。質問の内容に答え、必要なら一つだけ聞き返してください。Markdown、箇条書き、読み上げに不要な記号は避けてください。機械的な相槌や考え中の言葉を毎回は入れないでください。';
 try{await native(S.provider==='official'?'gptSend':'chatSend',S.provider==='official'?{text,instructions,effort:config.effort,webSearch:config.webSearch}:{text:outgoing});}catch(e){native('feedbackStop').catch(()=>{});if(epoch!==callEpoch)return;clearReplyWait();acceptReplies=false;S.state='idle';throw e;}if(epoch!==callEpoch||S.closed)return;S.call=true;if(config.thinking&&!config.feedback)native('cue').catch(showError);
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
 if(S.paired&&S.models.length)renderEfforts();
 $('persona').value=config.persona;$('style').value=String(config.style);
 for(const e of document.querySelectorAll('[data-setting]')){e.value=config[e.dataset.setting];$('out-'+e.dataset.setting).textContent=Number(config[e.dataset.setting]).toFixed(2);}
 for(const k of ['headset','autoListen','thinking','sendPersona','experimental'])$(k).checked=config[k]===true;
 $('callHeadset').checked=config.headset===true;
 $('feedback').checked=config.feedback===true;
 for(const k of ['effort','webSearch','tempo'])$(k).value=config[k];
 $('modeSummary').textContent=($('effort').selectedOptions[0]?.textContent||'モデル標準')+' · '+(config.webSearch==='off'?'検索なし':config.webSearch==='on'?'毎回ネット検索':'必要なときに検索');
 pipe.configure(S.provider==='official'?{...config,firstChars:18,maxChars:52,idleMs:config.tempo==='natural'?350:180}:config);update();
 clearTimeout(feedbackWarmTimer);if(S.ready&&config.feedback&&!S.closed)feedbackWarmTimer=setTimeout(()=>native('feedbackWarm',{settings:config,enabled:true}).catch(()=>{}),600);
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
for(const k of ['headset','autoListen','thinking','sendPersona','experimental'])$(k).onchange=()=>{
 config[k]=$(k).checked;renderSettings();saveSoon();
 if(k==='experimental'&&!config.experimental&&S.provider==='web')halt(true).catch(showError);
};
for(const b of document.querySelectorAll('[data-tab]'))b.onclick=()=>{for(const p of document.querySelectorAll('.page'))p.hidden=p.id!==b.dataset.tab;for(const n of document.querySelectorAll('[data-tab]')){n.classList.toggle('selected',n===b);n.setAttribute('aria-pressed',String(n===b));}syncCommerceContext();};
function action(id,fn){$(id).onclick=async()=>{if($(id).dataset.busy)return;$(id).dataset.busy='1';try{lastAction=['prepare','read','paste','testVoice','save','chatOpen'].includes(id)?fn:null;await fn();}catch(e){showError(e);}finally{delete $(id).dataset.busy;update();}};}
const effortLabels={none:'思考なし',minimal:'最小',low:'低',medium:'中',high:'高',xhigh:'極高',max:'最大'};
function renderEfforts(){
 const model=S.models.find(m=>m.id===$('model').value),levels=Array.isArray(model?.efforts)?model.efforts.filter(e=>Object.hasOwn(effortLabels,e)):[];
 $('effort').replaceChildren(new Option('インスタント（速さを優先）','instant'),new Option('モデル標準','default'));
 for(const level of levels)if(level!=='none'&&level!=='minimal')$('effort').add(new Option(effortLabels[level],level));
 if(![...$('effort').options].some(o=>o.value===config.effort))config.effort='instant';
 const fastest=levels.find(e=>e!=='minimal'||config.webSearch==='off');
 $('effortHint').textContent=fastest?'インスタントは、このモデルの「'+effortLabels[fastest]+'」で応答します。高・極高は深く考える分、待ち時間が増えます。':'このモデルは思考レベルを公開していないため、標準設定で応答します。';
 $('effort').disabled=!S.paired;
}
function renderSources(sources){
 $('sources').replaceChildren();if(!Array.isArray(sources))return;
 const seen=new Set();for(const source of sources.slice(0,20)){
  if(typeof source?.url!=='string'||source.url.length>2048)continue;
  let url;try{url=new URL(source.url);}catch{continue;}
  if(!['https:','http:'].includes(url.protocol)||!url.hostname||url.username||url.password||seen.has(url.href))continue;seen.add(url.href);
  if(seen.size===1){const title=document.createElement('p');title.textContent='参照したページ';$('sources').append(title);}
  const b=document.createElement('button');b.type='button';b.textContent=String(source.title||url.hostname).slice(0,180)+' · '+url.hostname;b.onclick=()=>native('openSource',{url:url.href}).catch(showError);$('sources').append(b);
 }
}
function renderLatency(){const parts=[];if(Number.isFinite(S.metrics.textMs))parts.push('GPTの書き始め '+(S.metrics.textMs/1000).toFixed(2)+'秒');if(Number.isFinite(S.metrics.voiceMs))parts.push('送信から声が出るまで '+(S.metrics.voiceMs/1000).toFixed(2)+'秒');$('latency').textContent=parts.length?parts.join(' / '):'応答時間：会話すると表示されます。';}
function accountStatus(value){
 if(!value||typeof value!=='object')return;
 if(S.planAvailable){S.provider='official';S.paired=value.authenticated===true;}
 $('accountStatus').textContent=S.paired?(value.account||'ChatGPTに接続済み'):'未接続';
 $('account').replaceChildren();for(const a of value.accounts||[])$('account').add(new Option(a.label,a.id));
 if(!$('account').options.length)$('account').add(new Option('ログインしてください',''));$('account').value=value.selectedAccount||'';
 S.models=Array.isArray(value.models)?value.models:[];
 $('model').replaceChildren();for(const m of S.models)$('model').add(new Option(m.label,m.id));
 if(!$('model').options.length)$('model').add(new Option('接続すると選べます',''));$('model').value=value.model||'';
 renderEfforts();
 $('signOut').disabled=!S.paired;$('model').disabled=!S.paired;
 $('connectionTitle').textContent=S.paired?(value.account||'ChatGPTに接続済み'):'ChatGPTに接続';
 $('chatStatus').textContent=S.paired?'接続済み · ChatGPTの利用枠で会話できます。':'未接続 · ChatGPTでログインしてください。';
 renderSettings();
}
async function connect(newAccount=false){
 if(S.planAvailable){
  await halt();S.authenticating=true;update();
  try{accountStatus(await native('gptSignIn',{newAccount}));$('errorPanel').hidden=true;$('manageUsage').hidden=true;}
  finally{S.authenticating=false;update();}
 }else{config.experimental=true;renderSettings();await saveNow();await native('chatOpen');}
}
action('modeSummary',()=>{document.querySelector('[data-tab="voice"]').click();$('accountSection').open=true;$('effort').focus();});
action('chatOpen',()=>connect());action('addAccount',()=>connect(true));
action('signOut',async()=>{await halt();const result=await native('gptSignOut');accountStatus(result);if(result.remoteRevoked===false)toast('端末からログアウトしました。遠隔の解除は未確認です。ChatGPTの設定で接続を解除できます。');});
action('manageUsage',()=>native('gptManageUsage'));action('manageUsageSettings',()=>native('gptManageUsage'));
$('model').onchange=async()=>{try{await halt();await native('gptModel',{model:$('model').value});renderEfforts();renderSettings();saveSoon();toast('会話モデルを変更しました。');}catch(e){showError(e);}};
$('account').onchange=async()=>{try{await halt();accountStatus(await native('gptAccount',{account:$('account').value}));}catch(e){S.paired=false;update();showError(e);}};
for(const k of ['effort','webSearch','tempo'])$(k).onchange=async()=>{try{await halt();config=LiveTalk.settings({...config,[k]:$(k).value});renderEfforts();renderSettings();saveSoon();}catch(e){showError(e);}};
$('callHeadset').onchange=()=>{config.headset=$('callHeadset').checked;renderSettings();saveSoon();};
$('feedback').onchange=()=>{config.feedback=$('feedback').checked;if(!config.feedback)native('feedbackStop').catch(()=>{});renderSettings();saveSoon();};
action('send',()=>send($('input').value));
action('mic',async()=>{if(S.listening){await halt();}else{callEpoch++;acceptReplies=false;clearReplyWait();await stopGPT();await pipe.stop();config.autoListen=true;saveSoon();S.call=true;await startListening();}});
async function halt(detach=false){
 callEpoch++;S.call=false;acceptReplies=false;clearReplyWait();const errors=[];
 const spoken=heardText(),responseID=pipe.id;
 for(const fn of [()=>stopListening(),()=>S.provider==='official'?native('gptStop',{heard:spoken,responseID}):S.paired?native(detach?'chatDetach':'chatStop'):Promise.resolve(),()=>pipe.stop()]){
  try{await fn();}catch(e){if(e.message!=='cancelled')errors.push(e);}
 }
 if(detach){S.paired=false;$('chatStatus').textContent='未接続';}
 update();if(errors.length)throw errors[0];
}
action('stop',async()=>{await halt();toast('停止しました。');});

action('copyInput',async()=>{await native('copy',{text:$('input').value});toast('質問をコピーしました。');});
action('paste',async()=>{const text=LiveTalk.inputText(await native('paste'));$('manual').value=text;update();await read(text);});
action('read',()=>read($('manual').value));
async function read(text){text=LiveTalk.inputText(text);if(!S.ready)throw Error('最初に音声を準備してください。');if(config.volume===0)throw Error('音量が0になっています。設定で音量を上げてください。');S.call=false;acceptReplies=false;clearReplyWait();$('errorPanel').hidden=true;await stopListening();const id='manual:'+Date.now();if(await pipe.begin(id)){ $('sources').replaceChildren();$('response').textContent=text;pipe.snapshot(text,true); }}
action('testVoice',()=>read('こんにちは。好きな声で、いつもの返答を読み上げます。'));
action('save',async()=>{await saveNow();toast('設定を保存しました。');});
action('export',()=>native('exportSettings',{settings:config}));
action('import',async()=>{const imported=LiveTalk.importedSettings(await native('importSettings'));config=imported;selectAvailableStyle();renderSettings();await saveNow();toast('設定を読み込みました。');});
action('reset',async()=>{if(await native('confirmReset')){config=LiveTalk.settings();selectAvailableStyle();renderSettings();await saveNow();toast('初期設定に戻しました。');}});
action('licenses',()=>native('showLicenses'));
action('privacy',()=>native('showPrivacy'));
action('terms',()=>native('showTerms'));
for(const [id,command] of [['removeAds','purchaseAdRemoval'],['restorePurchases','restorePurchases'],['adEnable','adEnable'],['adPrivacy','adPrivacy']])action(id,async()=>{await halt();const operation=command==='purchaseAdRemoval'&&(!commerce.available||!commerce.price)?'commerceRefresh':command;const value=await native(operation);setCommerce(value);if(value?.message)toast(value.message);});
action('adLicenses',()=>native('showAdLicenses'));
action('refundHelp',()=>native('openSource',{url:'https://support.apple.com/ja-jp/118223'}));
action('contactSupport',()=>native('contactSupport'));
action('deleteData',async()=>{await halt();const result=await native('deleteLocalData');if(result?.cancelled)return;if(result?.localRemoved!==true)throw Error('削除を確認できませんでした。');config=LiveTalk.settings();S.ready=false;S.paired=false;S.models=[];$('response').textContent='会話の返答がここに表示されます。';$('sources').replaceChildren();$('heard').hidden=true;$('heard').textContent='';$('input').value='';$('manual').value='';$('logs').textContent='';$('latency').textContent='応答時間：会話すると表示されます。';renderSettings();toast(result.remoteRevoked===false?'端末のデータを削除しました。ChatGPT側の接続解除は、ChatGPTの設定でも確認してください。':'同意を撤回し、端末のデータを削除しました。');});
action('diagnostics',async()=>{await native('copy',{text:'LiveTalk 2.4\n'+$('capabilities').textContent+'\n'+$('latency').textContent+'\n'+$('logs').textContent});toast('診断をコピーしました。');});
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
  S.planAvailable=result.planUsageAvailable===true;
  S.callAvailable=S.planAvailable||result.experimentalAvailable!==false;
  if(S.planAvailable)S.provider='official';
  if(result.experimentalAvailable===false||S.planAvailable){config.experimental=false;$('experimentalSection').hidden=true;}
  $('capabilities').textContent='音声：準備済み · 端末内音声認識：'+(S.asr?'対応':'未対応（文字入力をご利用ください）');
  log('音声準備完了');renderSettings();
  if(S.planAvailable){S.authenticating=true;update();try{accountStatus(await native('gptStatus',{restore:true}));}catch(e){showError(e);}finally{S.authenticating=false;update();}}
 }finally{S.preparing=false;update();}
}
action('prepare',()=>prepare(true));renderSettings();
(async()=>{
 try{setCommerce(await native('commerceStatus'));}catch{renderCommerce();}
 try{config=LiveTalk.settings(await native('loadSettings'));renderSettings();$('saveStatus').textContent='設定を読み込みました';}catch(e){showError(e);}
 try{await prepare();}catch(e){$('capabilities').textContent=e.message;log('音声の初回準備が必要');if(!/利用条件/.test(e.message))showError(e);update();}
})();
