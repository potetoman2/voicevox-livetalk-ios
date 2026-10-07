const {test}=require('node:test'),assert=require('node:assert/strict');
const {app,until}=require('./app-fixture.cjs');
const free={entitlement:'free',preview:false,available:true,price:'￥980',busy:false};
const init={planUsageAvailable:true,experimentalAvailable:false,asrAvailable:true,styles:[{name:'ずんだもん',styles:[{id:3,name:'ノーマル'}]}]};
const signed={authenticated:true,models:[{id:'test',label:'test',efforts:['none','low']}],model:'test'};

test('unchecked purchase rights block a new purchase while explicit restoration remains available',async()=>{
 const a=await app({agreed:true,handler:m=>m.command==='commerceStatus'?{...free,entitlement:'checking'}:undefined});try{
  assert.equal(a.$('removeAds').disabled,true);assert.equal(a.$('adEnable').disabled,true);
  assert.equal(a.$('restorePurchases').disabled,false);
  await a.click('removeAds');assert.equal(a.calls.some(c=>c.command==='purchaseAdRemoval'),false);
  await a.click('restorePurchases');assert.equal(a.calls.filter(c=>c.command==='restorePurchases').length,1);
 }finally{a.close();}
});

test('rechecking a pending approval does not automatically purchase or grant ad removal',async()=>{
 const a=await app({agreed:true,handler:m=>m.command==='commerceStatus'?{...free,pending:true,available:false}:m.command==='commerceRefresh'?{...free,pending:false,message:'購入情報を確認しました。'}:undefined});try{
  assert.match(a.$('purchaseStatus').textContent,/承認/);
  await a.click('removeAds');assert.equal(a.calls.filter(c=>c.command==='commerceRefresh').length,1);
  assert.equal(a.calls.some(c=>c.command==='purchaseAdRemoval'),false);
  assert.match(a.$('purchaseStatus').textContent,/無料版/);
 }finally{a.close();}
});
test('buying displays native StoreKit price and restoration is a separate explicit action',async()=>{
 const a=await app({agreed:true,handler:m=>m.command==='commerceStatus'?free:undefined});
 try{
  assert.match(a.$('removeAds').textContent,/￥980/);assert.equal(a.$('removeAds').disabled,false);
  assert.equal(a.calls.some(c=>c.command==='purchaseAdRemoval'||c.command==='restorePurchases'),false);
  await a.click('removeAds');assert.equal(a.calls.filter(c=>c.command==='purchaseAdRemoval').length,1);
  await a.click('restorePurchases');assert.equal(a.calls.filter(c=>c.command==='restorePurchases').length,1);
 }finally{a.close();}
});
test('preview cannot invoke purchases and a verified native removal immediately disables buying and ad opt-in',async()=>{
 const a=await app({agreed:true,init,handler:m=>m.command==='gptStatus'?signed:undefined});try{
  assert.equal(a.$('removeAds').disabled,true);await a.click('removeAds');assert.equal(a.calls.some(c=>c.command==='purchaseAdRemoval'),false);
  a.w.LiveTalkEvent({type:'commerce',value:{...free,entitlement:'removed'}});
  assert.equal(a.$('removeAds').disabled,true);assert.equal(a.$('adEnable').disabled,true);
  assert.match(a.$('purchaseStatus').textContent,/広告なし/);
  a.w.LiveTalkEvent({type:'commerce',value:free});assert.equal(a.$('removeAds').disabled,false);
 }finally{a.close();}
});
test('missing or malformed native prices never produce a purchase button with a guessed amount',async()=>{
 const a=await app({agreed:true,handler:m=>m.command==='commerceStatus'?{...free,price:''}:undefined});try{
  assert.match(a.$('removeAds').textContent,/再確認/);assert.doesNotMatch(a.$('removeAds').textContent,/980/);
  await a.click('removeAds');assert.equal(a.calls.some(c=>c.command==='purchaseAdRemoval'),false);assert.equal(a.calls.some(c=>c.command==='commerceRefresh'),true);
  a.w.LiveTalkEvent({type:'commerce',value:{...free,price:{value:980}}});assert.match(a.$('removeAds').textContent,/再確認/);
 }finally{a.close();}
});
test('ad eligibility context changes on settings navigation and active voice conversation',async()=>{
 const a=await app({agreed:true,init,handler:m=>m.command==='gptStatus'?signed:undefined});try{
  a.w.document.querySelector('[data-tab="voice"]').click();await until(()=>a.calls.some(c=>c.command==='commerceContext'&&c.args.settingsVisible));
  a.w.document.querySelector('[data-tab="call"]').click();await until(()=>a.calls.filter(c=>c.command==='commerceContext').at(-1).args.settingsVisible===false);
  await a.until(()=>!a.$('mic').disabled);await a.click('mic');
  assert.equal(a.calls.filter(c=>c.command==='commerceContext').at(-1).args.conversationActive,true);
  await a.click('stop');assert.equal(a.calls.filter(c=>c.command==='commerceContext').at(-1).args.conversationActive,false);
 }finally{a.close();}
});
test('forged paid settings do not affect native rights or cause automatic purchase, restore or ad opt-in',async()=>{
 const a=await app({agreed:true,settings:{paid:true,entitlement:'removed',adConsentVersion:'yes'},handler:m=>m.command==='commerceStatus'?free:undefined});try{
  assert.match(a.$('purchaseStatus').textContent,/無料版/);
  assert.equal(a.calls.some(c=>['purchaseAdRemoval','restorePurchases','adEnable','adPrivacy'].includes(c.command)),false);
  await a.click('save');const saved=a.calls.filter(c=>c.command==='saveSettings').at(-1).args.settings;
  assert.equal(saved.paid,undefined);assert.equal(saved.entitlement,undefined);assert.equal(saved.adConsentVersion,undefined);
 }finally{a.close();}
});
test('a provider consent error or purchase cancellation does not remove conversation readiness',async()=>{
 const a=await app({agreed:true,init,handler:m=>m.command==='gptStatus'?signed:m.command==='commerceStatus'?{...free,adFailed:true}:m.command==='purchaseAdRemoval'?{...free,message:'購入をキャンセルしました。'}:undefined});try{
  await a.until(()=>!a.$('mic').disabled);assert.equal(a.$('mic').disabled,false);
  await a.click('removeAds');assert.equal(a.$('mic').disabled,false);assert.match(a.$('toast').textContent,/キャンセル/);
 }finally{a.close();}
});

test('ad network failure offers one explicit retry without automatically calling the provider',async()=>{
 const failed={...free,optedIn:true,adFailed:true};
 const a=await app({agreed:true,handler:m=>m.command==='commerceStatus'?failed:m.command==='adRetry'?{...failed,adFailed:false,message:'再確認しました。'}:undefined});try{
  assert.equal(a.$('adRetry').hidden,false);
  assert.match(a.$('adEnable').textContent,/年齢/);
  assert.equal(a.calls.some(c=>c.command==='adRetry'),false);
  await a.click('adRetry');assert.equal(a.calls.filter(c=>c.command==='adRetry').length,1);
  assert.equal(a.$('adRetry').hidden,true);
 }finally{a.close();}
});

test('withdrawn consent and verified ad removal never offer a retry that can restart ads',async()=>{
 const a=await app({agreed:true,handler:m=>m.command==='commerceStatus'?{...free,adFailed:true,optedIn:false}:undefined});try{
  assert.equal(a.$('adRetry').hidden,true);
  a.w.LiveTalkEvent({type:'commerce',value:{...free,adFailed:true,optedIn:true,entitlement:'removed'}});
  assert.equal(a.$('adRetry').hidden,true);assert.equal(a.$('adRetry').disabled,true);
  await a.click('adRetry');assert.equal(a.calls.some(c=>c.command==='adRetry'),false);
  assert.equal(a.$('adPrivacy').disabled,false,'Paid users can still withdraw data consent');
 }finally{a.close();}
});
