const {test}=require('node:test');
const assert=require('node:assert/strict');
const {settings,canonical,speakable,voiceFor,revisionOffset,SpeechPipeline}=require('../shared/engine.js');
const delay=ms=>new Promise(r=>setTimeout(r,ms));
async function until(predicate){for(let i=0;i<200;i++){if(predicate())return;await delay(5);}throw Error('Timed out');}
function fixture(options={}){
  const spoken=[],synthesized=[],discarded=[],files=new Map(),states=[];
  let serial=0,gen=0,complete=null,calls=0,inFlight=0,maxFlight=0;
  const native=async(command,args)=>{
    if(command==='stop'){gen=args.generation;if(complete){complete.reject(Error('cancelled'));complete=null;}return true;}
    if(command==='synthesize'){
      inFlight++;maxFlight=Math.max(maxFlight,inFlight);calls++;synthesized.push(args.text);
      await delay(options.synthMs??4);inFlight--;
      if(args.generation!==gen)throw Error('cancelled');
      const file=String(++serial);files.set(file,args.text);return file;
    }
    if(command==='discard'){discarded.push(files.get(args.file));files.delete(args.file);return;}
    if(command==='play'){
      if(args.generation!==gen)throw Error('cancelled');
      assert.ok(files.has(args.file),'audio file retained until playback');
      spoken.push(files.get(args.file));
      await new Promise((resolve,reject)=>{complete={resolve,reject};if(!options.manual) setTimeout(resolve,options.playMs??12);});
      complete=null;files.delete(args.file);return true;
    }
    throw Error(command);
  };
  const pipe=new SpeechPipeline(native,(state,text)=>states.push([state,text]));
  return {pipe,spoken,synthesized,discarded,files,states,finish(){complete?.resolve();},get maxFlight(){return maxFlight;},get calls(){return calls;}};
}
test('saved settings reject nonfinite values and unknown presets',()=>{
  const s=settings({speed:Infinity,pitch:999,volume:-1,persona:'injected',autoListen:'yes',firstChars:2});
  assert.equal(s.speed,1.05);assert.equal(s.pitch,.15);assert.equal(s.volume,0);assert.equal(s.persona,'gentle');assert.equal(s.autoListen,false);assert.equal(s.firstChars,8);
});
test('URLs and fenced code are removed while link labels remain',()=>{
  assert.equal(speakable('## 見出し\n```js\nalert(1)\n```\n[説明](https://example.test) https://example.test').trim(),'見出し\n\n説明 リンク');
});
test('emotion zero preserves configured values; emotional changes remain bounded',()=>{
  const s=settings({emotion:0});assert.equal(voiceFor('やった！',s).speed,s.speed);
  const strong=voiceFor('本当にすごい、嬉しい！',settings({speed:2,pitch:.15,intonation:2,emotion:1}));assert.equal(strong.speed,2);assert.equal(strong.pitch,.15);assert.equal(strong.intonation,2);
});
test('short first chunk plays before a response finishes',async()=>{
  const f=fixture();await f.pipe.begin('r1');f.pipe.snapshot('こんにちは。続きは');await until(()=>f.spoken.length===1);assert.equal(f.spoken[0],'こんにちは。');assert.equal(f.pipe.done,false);await f.pipe.stop();
});
test('long response drains a bounded queue in order',async()=>{
  const f=fixture();await f.pipe.begin('r1');const text='一番目です。二番目です。三番目です。四番目です。五番目です。';f.pipe.snapshot(text,true);
  await until(()=>!f.pipe.busy);assert.equal(f.spoken.join(''),text);assert.equal(f.maxFlight,1);assert.equal(f.files.size,0);
});
test('real rewrite lets current speech finish and replaces unsaid tail',async()=>{
  const f=fixture({manual:true});await f.pipe.begin('r');f.pipe.snapshot('最初の文章です。古い返答です。',false);await until(()=>f.spoken.length===1);
  f.pipe.snapshot('最初の文章です。新しい返答です。',true);f.finish();await until(()=>f.spoken.length===2);f.finish();await until(()=>!f.pipe.busy);
  assert.deepEqual(f.spoken,['最初の文章です。','新しい返答です。']);assert.ok(!f.spoken.includes('古い返答です。'));assert.equal(f.files.size,0);
});
test('format-only rewrite does not replay heard text',async()=>{
  const f=fixture({manual:true});await f.pipe.begin('r');f.pipe.snapshot('最初の文章です。',false);await until(()=>f.spoken.length===1);
  f.pipe.snapshot('**最初の文章です。**\n\n次の文章です。',true);f.finish();await until(()=>f.spoken.length===2);f.finish();await until(()=>!f.pipe.busy);assert.equal(canonical(f.spoken.join('')),'最初の文章です。次の文章です。');
});
test('temporary DOM shrink retains speech frontier',async()=>{
  const f=fixture({manual:true});await f.pipe.begin('r');f.pipe.snapshot('最初の文章です。',false);await until(()=>f.spoken.length===1);f.pipe.snapshot('最初',false);
  assert.equal(f.pipe.text,'最初の文章です。');f.pipe.snapshot('最初の文章です。続きです。',true);f.finish();await until(()=>f.spoken.length===2);f.finish();await until(()=>!f.pipe.busy);assert.equal(f.spoken.join(''),'最初の文章です。続きです。');
});
test('interrupt during inference drops old audio and allows new reply',async()=>{
  const f=fixture({synthMs:30});await f.pipe.begin('old');f.pipe.snapshot('取り消される音声です。',true);await delay(4);await f.pipe.begin('new');f.pipe.snapshot('新しい会話です。',true);
  await until(()=>!f.pipe.busy);assert.deepEqual(f.spoken,['新しい会話です。']);assert.equal(f.files.size,0);
});
test('interrupt current playback also reclaims speculative audio',async()=>{
  const f=fixture({manual:true});await f.pipe.begin('r');f.pipe.snapshot('最初です。次です。',true);await until(()=>f.spoken.length===1);await delay(10);await f.pipe.stop();await until(()=>!f.pipe.busy);await delay(10);assert.equal(f.spoken.length,1);assert.equal(f.files.size,0);
});
test('punctuation-only paint does not synthesize an empty WAV',async()=>{
  const f=fixture();await f.pipe.begin('r');f.pipe.snapshot('。！？',true);await until(()=>!f.pipe.busy);assert.equal(f.calls,0);assert.equal(f.spoken.length,0);
});
test('unpunctuated streaming flushes after idle delay',async()=>{
  const f=fixture();f.pipe.configure({idleMs:150});await f.pipe.begin('r');f.pipe.snapshot('短い途中',false);await until(()=>f.spoken.length===1);assert.equal(f.spoken[0],'短い途中');await f.pipe.stop();
});
test('frontier anchor adjusts to an inserted prefix',()=>{
  assert.equal(revisionOffset('最初の文章です。二番目。','補足。最初の文章です。新しい二番目。',8),11);
});

test('corrupt persisted settings and prototype persona keys recover safely',()=>{
 assert.equal(settings(null).persona,'gentle');assert.equal(settings([]).style,3);assert.equal(settings({persona:'__proto__'}).persona,'gentle');
 const {importedSettings}=require('../shared/engine');
 for(const value of [null,[],{}, {version:99,speed:1}])assert.throws(()=>importedSettings(value));
 assert.equal(importedSettings({version:1,speed:1.2}).version,2);
});

test('overlapping response starts cannot replace the newest response ID',async()=>{
 const stops=[],states=[];const p=new SpeechPipeline((cmd,args)=>cmd==='stop'?new Promise(r=>stops.push(r)):Promise.resolve(),s=>states.push(s));
 const first=p.begin('old'),second=p.begin('new');stops[1]();assert.equal(await second,true);stops[0]();assert.equal(await first,false);assert.equal(p.id,'new');assert.equal(states.at(-1),'thinking');
});
test('inference error prevents subsequent snapshots from silently restarting until a new begin',async()=>{
 const states=[];let attempts=0,fail=true;
 const p=new SpeechPipeline(async cmd=>{if(cmd==='synthesize'){attempts++;if(fail)throw Error('core failure');return 'wav';}return true;},s=>states.push(s));
 await p.begin('one');p.snapshot('失敗する短文。',true);await until(()=>states.includes('error'));p.snapshot('後から来た回答。',true);await delay(20);assert.equal(attempts,1);
 fail=false;await p.begin('two');p.snapshot('復帰した短文。',true);await until(()=>states.at(-1)==='idle');assert.equal(attempts,2);
});
test('snapshots after explicit stop are ignored even if an old sender keeps streaming',async()=>{
 const f=fixture();await f.pipe.begin('old');await f.pipe.stop();f.pipe.snapshot('古い回答。',true);await delay(20);assert.equal(f.calls,0);
});

test('unfinished and tilde code fences never leak code into streaming speech',()=>{
 assert.equal(speakable('前の文章。\n```js\nconst privateCode=1;'),'前の文章。');
 assert.equal(speakable('前。\n~~~js\nsecretCode\n~~~\n後。'),'前。\n\n後。');
});
test('short chunks preserve emoji and combining graphemes across boundaries',async()=>{
 const f=fixture();f.pipe.configure({firstChars:8,maxChars:20});const text='長い説明文章です👨‍👩‍👧‍👦の声とe\u0301の例です。';await f.pipe.begin('unicode');f.pipe.snapshot(text,true);await until(()=>f.states.at(-1)?.[0]==='idle');assert.equal(f.spoken.join(''),text);
 for(const chunk of f.spoken){assert.equal(/^[\uDC00-\uDFFF]|[\uD800-\uDBFF]$/.test(chunk),false);assert.equal(chunk.startsWith('\u200d'),false);}
 const {safeCut,rawOffset}=require('../shared/engine');assert.equal(safeCut('あ👨‍👩‍👧‍👦い',3),1);assert.equal(rawOffset('e\u0301次',1),2);
});
