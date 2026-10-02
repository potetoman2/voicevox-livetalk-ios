/* Shared, dependency-free conversation and speech pipeline. */
(function(root) {
  'use strict';
  const DEFAULTS = Object.freeze({version:1,style:3,speed:1.05,pitch:0,intonation:1.1,volume:1,
    pre:0.02,post:0.03,comma:0.08,sentence:0.12,emotion:0.35,persona:'gentle',
    firstChars:18,maxChars:48,idleMs:350,autoListen:false,headset:false,thinking:false,sendPersona:false});
  const PRESETS = Object.freeze({
    gentle:{label:'優しい相談相手',prompt:'優しい相談相手として日本語で話してください。共感を添え、短い自然な文で返してください。',speed:0.98,pitch:0.01,intonation:1.05},
    partner:{label:'元気な相棒',prompt:'明るい相棒として日本語で話してください。親しみやすく、短い自然な文で返してください。',speed:1.12,pitch:0.03,intonation:1.2},
    secretary:{label:'冷静な秘書',prompt:'冷静な秘書として日本語で話してください。要点を簡潔に、音声で聞き取りやすく返してください。',speed:1.05,pitch:-0.02,intonation:0.95},
    explain:{label:'ゆっくり解説',prompt:'落ち着いた解説役として日本語で話してください。一度に一つの要点を、短い文で説明してください。',speed:0.9,pitch:0,intonation:1.05}
  });
  const clamp=(v,min,max,fallback)=>Number.isFinite(Number(v))?Math.min(max,Math.max(min,Number(v))):fallback;
  function settings(value={}) {
    const s={...DEFAULTS};
    for (const [key,min,max] of [['speed',0.5,2],['pitch',-0.15,0.15],['intonation',0,2],['volume',0,2],
      ['pre',0,1],['post',0,1],['comma',0,1],['sentence',0,1],['emotion',0,1],['firstChars',8,50],['maxChars',20,100],['idleMs',150,1500]])
      s[key]=clamp(value[key]??s[key],min,max,s[key]);
    s.style=Math.round(clamp(value.style??s.style,0,2147483647,s.style));
    s.persona=PRESETS[value.persona]?value.persona:s.persona;
    for(const key of ['autoListen','headset','thinking','sendPersona']) s[key]=value[key]===true;
    return s;
  }
  function speakable(text) {
    return String(text).replace(/```[\s\S]*?```/g,'').replace(/\[([^\]]+)\]\([^)]*\)/g,'$1')
      .replace(/https?:\/\/\S+/g,'リンク').replace(/^[ \t]*(?:#{1,6}\s+|[-*+]\s+|\d+[.)]\s+)/gm,'')
      .replace(/[*_`]/g,'').replace(/[ \t]+/g,' ').replace(/\n{3,}/g,'\n\n');
  }
  function canonical(text) {return speakable(text).normalize('NFKC').replace(/\s/g,'');}
  function voiceFor(text,s) {
    let joy=/(すごい|嬉し|うれし|やった|楽し|おめでとう)/.test(text)?1:0;
    let calm=/(残念|つらい|辛い|悲し|大丈夫|心配)/.test(text)?1:0;
    let surprise=/(本当|驚|びっくり|えっ)/.test(text)?1:0;
    return {...s,speed:clamp(s.speed*(1+s.emotion*(joy*0.08-calm*0.08)),0.5,2,s.speed),
      pitch:clamp(s.pitch+s.emotion*(joy*0.03+surprise*0.02-calm*0.015),-0.15,0.15,s.pitch),
      intonation:clamp(s.intonation+s.emotion*(joy*0.15+surprise*0.2-calm*0.1),0,2,s.intonation)};
  }
  // A frontier represents speech already played, rather than text merely synthesized.
  function revisionOffset(oldText,newText,heard) {
    const target=canonical(newText), old=canonical(oldText), n=Math.min(heard,old.length);
    if(!n)return 0;
    if(target.startsWith(old.slice(0,n))) return n;
    // Match the last heard suffix, then continue after it. Never restart a whole response.
    for(let count=Math.min(32,n);count>=6;count--) {
      const anchor=old.slice(n-count,n), index=target.indexOf(anchor);
      if(index>=0)return index+count;
    }
    // Real rewrite of already heard content: only resume from the next sentence.
    let i=0, sentences=0;
    for(const ch of old.slice(0,n))if(/[。！？!?\n]/.test(ch))sentences++;
    if(!sentences)return Math.min(n,target.length);
    for(;i<target.length;i++)if(/[。！？!?]/.test(target[i])&&!--sentences)return i+1;
    return Math.min(n,target.length);
  }
  function rawOffset(text,count) {
    if(!count)return 0;
    let length=0;
    for(let i=0;i<text.length;i++) {length+=canonical(text[i]).length;if(length>=count)return i+1;}
    return text.length;
  }
  class SpeechPipeline {
    constructor(native,onState=()=>{},onLog=()=>{}) {
      this.native=native;this.onState=onState;this.onLog=onLog;this.generation=0;
      this.s=settings();this.text='';this.cursor=0;this.heard=0;this.queue=[];
      this.busy=false;this.playing=null;this.revision=0;this.done=false;this.id=null;
    }
    configure(s){this.s=settings(s);}
    async stop() {
      this.generation++;this.revision++;this.queue=[];this.id=null;this.done=true;
      clearTimeout(this.timer);this.cursor=this.text.length;
      await this.native('stop',{generation:this.generation});this.onState('idle');
    }
    async begin(id) {
      await this.stop();this.id=id;this.text='';this.cursor=0;this.heard=0;this.done=false;
      this.onState('thinking');
    }
    snapshot(text,done=false) {
      text=speakable(text);
      if(text!==this.text && !text.startsWith(this.text)) {
        const a=canonical(this.text),b=canonical(text);
        if(a.startsWith(b) && !done) return; // transient partial DOM paint
        const heard=this.heard+(this.playing?.length||0);
        this.revision++;this.queue=[];
        this.cursor=rawOffset(text,revisionOffset(this.text,text,heard));
        this.heard=canonical(text.slice(0,this.cursor)).length;
        this.onLog('返答の更新に合わせて、未再生の音声を作り直しました');
      }
      this.text=text;this.done=done;clearTimeout(this.timer);this.extract(false);
      if(done)this.extract(true);
      else this.timer=setTimeout(()=>this.extract(true),this.s.idleMs);
    }
    extract(force) {
      while(this.queue.length<3 && this.cursor<this.text.length) {
        const remaining=this.text.slice(this.cursor);
        const limit=this.heard||this.queue.length||this.playing?this.s.maxChars:this.s.firstChars;
        const punctuation=remaining.match(/[。！？!?\n、,]/);
        let length=punctuation?punctuation.index+1:0;
        if(length>this.s.maxChars)length=this.s.maxChars;
        if(!length && remaining.length>=limit) length=limit;
        if(!length && force) length=remaining.length;
        if(!length)break;
        const chunk=remaining.slice(0,length);this.cursor+=length;
        if(!/[\p{L}\p{N}]/u.test(chunk))continue;
        this.queue.push({text:chunk,length:canonical(chunk).length,revision:this.revision});
      }
      this.pump();
    }
    async synth(item,gen) {
      const file=await this.native('synthesize',{text:item.text,settings:voiceFor(item.text,this.s),generation:gen});
      return {...item,file};
    }
    async pump() {
      if(this.busy)return;this.busy=true;const gen=this.generation;
      let prepared=null,current=null,failed=false;
      try {
        while(gen===this.generation) {
          const item=prepared?await prepared:this.queue.length?await this.synth(this.queue.shift(),gen):null;
          prepared=null;
          if(!item)break;
          if(gen!==this.generation||item.revision!==this.revision){await this.native('discard',{file:item.file});continue;}
          this.playing=item;current=item;this.onState('speaking',item.text);
          // Begin one bounded future synthesis while the current short WAV plays.
          if(this.queue.length) {prepared=this.synth(this.queue.shift(),gen);prepared.catch(()=>{});}
          await this.native('play',{file:item.file,generation:gen});
          if(gen!==this.generation)break;
          // A rewrite already moved the frontier, including this current sentence.
          if(item.revision===this.revision)this.heard+=item.length;
          this.playing=null;current=null;this.extract(this.done);
        }
      } catch(error) {
        if(gen===this.generation && error.message!=='cancelled') {
          failed=true;this.onLog(error.message);this.queue=[];this.done=true;this.onState('error',error.message);
        }
      } finally {
        // Stop may leave one uncancellable core inference; reclaim its result.
        if(prepared)prepared.then(item=>this.native('discard',{file:item.file})).catch(()=>{});
        if(current)this.native('discard',{file:current.file}).catch(()=>{});
        this.busy=false;this.playing=null;
        if(this.queue.length)this.pump();
        else if(this.done&&gen===this.generation&&!failed)this.onState('idle');
      }
    }
  }
  const api={DEFAULTS,PRESETS,settings,speakable,canonical,revisionOffset,voiceFor,SpeechPipeline};
  root.LiveTalk=api;if(typeof module!=='undefined')module.exports=api;
})(typeof globalThis!=='undefined'?globalThis:this);
