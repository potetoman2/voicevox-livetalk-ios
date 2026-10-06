const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{pathToFileURL}=require('node:url');
const {chromium}=require('playwright');
test('rendered UI supports small phones, reading, settings, dark mode and enlarged text',async()=>{
 const browser=await chromium.launch({headless:true,...(process.platform==='win32'?{channel:'chrome'}:{})});
 try{
  for(const width of [320,390,768]){
   const page=await browser.newPage({viewport:{width,height:844},colorScheme:width===768?'dark':'light'}),errors=[];
   page.on('pageerror',e=>errors.push(e.message));
   await page.addInitScript(()=>{
    window.__nativeCalls=[];
    window.LiveTalkNative={postMessage(raw){const m=JSON.parse(raw);window.__nativeCalls.push(m);setTimeout(()=>{
     let r=true;
     if(m.command==='loadSettings')r={};
     if(m.command==='init')r={asrAvailable:true,styles:[{name:'ずんだもん',styles:[{id:3,name:'ノーマル'}]}]};
     if(m.command==='paste')r='コピーした返答を、好きな声で読み上げます。';
     if(m.command==='synthesize')r='mock.wav';
     window.LiveTalkReply(m.id,r);
    },0);}};
   });
   await page.goto(pathToFileURL(path.resolve('shared/index.html')).href);
   await page.locator('#onboarding').waitFor({state:'hidden'});
   const overflow=()=>page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1);
   assert.equal(await overflow(),false,'horizontal overflow at '+width);
   assert.ok((await page.locator('#paste').boundingBox()).height>=44);
   if(width===390){fs.mkdirSync('docs/preview',{recursive:true});await page.screenshot({path:'docs/preview/home.png',fullPage:true});}
   await page.locator('#paste').click();
   await page.waitForFunction(()=>window.__nativeCalls.some(c=>c.command==='play'));
   assert.match(await page.locator('#response').textContent(),/コピーした返答/);
   await page.locator('[data-tab="voice"]').click();
   await page.locator('[data-setting="speed"]').evaluate(e=>{e.value='1.4';e.dispatchEvent(new Event('input',{bubbles:true}));});
   await page.waitForFunction(()=>window.__nativeCalls.some(c=>c.command==='saveSettings'&&c.args.settings.speed===1.4));
   if(width===390)await page.screenshot({path:'docs/preview/settings.png',fullPage:true});
   await page.locator('[data-tab="call"]').click();
   await page.evaluate(()=>window.LiveTalkEvent({type:'fontScale',scale:1.6}));
   assert.equal(await overflow(),false,'enlarged text overflow at '+width);
   assert.deepEqual(errors,[]);
   await page.close();
  }
 }finally{await browser.close();}
});
