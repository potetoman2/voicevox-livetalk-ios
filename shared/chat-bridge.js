/* Runs only in the selected https://chatgpt.com top-level document. */
(() => {
  if(location.hostname!=='chatgpt.com'||window!==window.top||window.LiveTalkMobileChat)return;
  const emit=event=>{
    if(window.webkit?.messageHandlers?.chatEvent)window.webkit.messageHandlers.chatEvent.postMessage(event);
    else if(window.LiveTalkChat)window.LiveTalkChat.event(JSON.stringify(event));
  };
  let attached=false,baseline=new Map(),active=null,route=location.pathname,allowRoute=false;
  function reset(){baseline=new Map(LiveTalkDOM.messages(document).map(m=>[m.key,m.text]));active=null;}
  function arm(){reset();route=location.pathname;attached=true;emit({type:'attached',title:document.title});}
  function poll(){
    if(!attached)return;
    if(route!==location.pathname){
      if(allowRoute&&route==='/'&&/^\/c\//.test(location.pathname)){route=location.pathname;allowRoute=false;}
      else {attached=false;emit({type:'detached',message:'チャットが変わりました。「このチャットで通話」を押してください'});return;}
    }
    const candidate=LiveTalkDOM.messages(document).filter(m=>m.text&&baseline.get(m.key)!==m.text).at(-1);
    if(candidate){
      if(!active||active.key!==candidate.key){active={key:candidate.key,id:String(Date.now()),text:'',time:Date.now()};emit({type:'start',id:active.id});}
      if(active.text!==candidate.text){active.text=candidate.text;active.time=Date.now();emit({type:'snapshot',id:active.id,text:active.text});}
    }
    if(active&&!LiveTalkDOM.button(document,'stop')&&Date.now()-active.time>1200){
      emit({type:'snapshot',id:active.id,text:active.text,done:true});baseline.set(active.key,active.text);active=null;
    }
  }
  window.LiveTalkMobileChat={arm,async send(text){
    if(!attached)throw Error('ChatGPT画面で「このチャットで通話」を押してください');
    reset();allowRoute=route==='/';await LiveTalkDOM.submit(document,String(text));
  },async stop(){attached=false;await LiveTalkDOM.stop(document);reset();attached=true;}};
  document.addEventListener('click',e=>{if(e.target.closest('button')===LiveTalkDOM.button(document,'send')){reset();allowRoute=route==='/';}},true);
  document.addEventListener('keydown',e=>{if(e.key==='Enter'&&!e.shiftKey&&e.target===LiveTalkDOM.editor(document)){reset();allowRoute=route==='/';}},true);
  setInterval(poll,150);
})();
