/* Experimental, user-selected ChatGPT document only. No credentials or internal APIs. */
(() => {
  if(location.hostname!=='chatgpt.com'||window!==window.top||window.LiveTalkMobileChat)return;
  const emit=event=>window.webkit?.messageHandlers?.chatEvent?.postMessage(event);
  let attached=false,count=0,active=null,route=location.pathname,allowRoute=false,epoch=0,waiting=false,waitAt=0;
  function reset(){count=LiveTalkDOM.messages(document).length;active=null;waiting=false;}
  function detach(message){attached=false;epoch++;reset();emit({type:'detached',message});}
  function arm(){
    const status=LiveTalkDOM.readiness(document);
    if(!status.ok){attached=false;emit({type:'connectionError',...status});return status;}
    epoch++;reset();route=location.pathname;attached=true;emit({type:'attached'});return status;
  }
  function sent(){reset();emit({type:'waiting'});waiting=true;waitAt=Date.now();allowRoute=route==='/';}
  function poll(){
    if(!attached)return;
    if(route!==location.pathname){
      if(allowRoute&&route==='/'&&/^\/c\//.test(location.pathname)){route=location.pathname;allowRoute=false;}
      else {detach('別のチャットに移動しました。使うチャットで「接続する」を押してください。');return;}
    }
    const all=LiveTalkDOM.messages(document),candidate=all.slice(count).filter(m=>m.text).at(-1);
    if(candidate){
      if(!active||active.key!==candidate.key){active={key:candidate.key,id:epoch+':'+Date.now(),text:'',time:Date.now(),sawStop:false};waiting=false;emit({type:'start',id:active.id});}
      if(LiveTalkDOM.button(document,'stop'))active.sawStop=true;
      if(active.text!==candidate.text){active.text=candidate.text;active.time=Date.now();emit({type:'snapshot',id:active.id,text:active.text});}
    }
    if(active&&!LiveTalkDOM.button(document,'stop')&&Date.now()-active.time>(active.sawStop?1500:5000)){
      emit({type:'snapshot',id:active.id,text:active.text,done:true});count=all.length;active=null;
    }
    if(waiting&&Date.now()-waitAt>120000){waiting=false;emit({type:'error',code:'NO_REPLY',message:'返答を確認できませんでした。ChatGPT画面でエラーや利用上限を確認してください。'});}
  }
  window.LiveTalkMobileChat={arm,status:()=>LiveTalkDOM.readiness(document),async send(text){
    if(!attached)throw Error('ChatGPTを開いて「接続する」を押してください。');
    if(!String(text).trim()||String(text).length>12000)throw Error('質問は1〜12,000文字にしてください。');
    sent();try{await LiveTalkDOM.submit(document,String(text));}catch(e){waiting=false;throw e;}
  },async stop(){
    const current=++epoch,wasAttached=attached;attached=false;
    try{await LiveTalkDOM.stop(document);}finally{if(current===epoch){reset();attached=wasAttached&&route===location.pathname;}}
  },detach:()=>detach('接続を解除しました。')};
  document.addEventListener('click',e=>{if(attached&&e.target.closest('button')===LiveTalkDOM.button(document,'send'))sent();},true);
  document.addEventListener('keydown',e=>{if(attached&&e.key==='Enter'&&!e.shiftKey&&LiveTalkDOM.editor(document)?.contains(e.target))sent();},true);
  setInterval(poll,150);
})();
