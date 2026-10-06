const fs=require('node:fs'),{JSDOM}=require('jsdom');
const wait=ms=>new Promise(r=>setTimeout(r,ms));
async function until(fn){for(let i=0;i<200;i++){if(fn())return;await wait(5);}throw Error('Timed out waiting for app');}
async function app(options={}){
 const w=new JSDOM(fs.readFileSync('shared/index.html','utf8'),{url:'https://localhost/',runScripts:'outside-only'}).window,calls=[];
 if(options.timers){const schedule=w.setTimeout.bind(w);w.setTimeout=(fn,ms,...args)=>{if(ms===60000){options.timers.push(fn);return 0;}return schedule(fn,ms,...args);};}
 let agreed=options.agreed??false,gen=0;const stored=options.settings||{};
 w.LiveTalkNative={postMessage(raw){const m=JSON.parse(raw);calls.push(m);Promise.resolve().then(async()=>{
  if(options.handler){const r=await options.handler(m);if(r!==undefined)return r;}
  switch(m.command){
   case 'loadSettings':return stored;
   case 'commerceStatus':return {entitlement:'free',preview:true,available:false,price:''};
   case 'init':if(!agreed&&!m.args.interactive)throw Error('利用条件の確認が必要');agreed=true;return options.init||{platform:'iOS',asrAvailable:true,styles:[{name:'ずんだもん',styles:[{id:3,name:'ノーマル'}]}]};
   case 'stop':gen=m.args.generation;return true;
   case 'synthesize':if(m.args.generation!==gen)throw Error('cancelled');return 'test.wav';
   case 'paste':return options.clipboard??'こんにちは。';
   case 'play':case 'discard':case 'saveSettings':case 'asrStop':case 'chatStop':case 'chatSend':case 'asrStart':case 'copy':return true;
   default:return true;
  }
 }).then(v=>w.LiveTalkReply(m.id,v),e=>w.LiveTalkReply(m.id,null,e.message));}};
 w.eval(fs.readFileSync('shared/engine.js','utf8'));w.eval(fs.readFileSync('shared/app.js','utf8'));
 await until(()=>calls.some(c=>c.command==='init'));await wait(10);
 return {w,calls,$:id=>w.document.getElementById(id),wait,until,async click(id){w.document.getElementById(id).click();await wait(20);},close(){w.close();}};
}
module.exports={app,wait,until};
