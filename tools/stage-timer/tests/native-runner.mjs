import assert from 'node:assert/strict';import {writeFile,mkdir} from 'node:fs/promises';import path from 'node:path';
export async function run({win,api,getPrefs,dataDir}){
 const results=[],output=path.resolve(dataDir,'../test-results/desktop');await mkdir(output,{recursive:true});
 const delay=ms=>new Promise(r=>setTimeout(r,ms));
 const read=()=>win.webContents.executeJavaScript(`({time:document.querySelector('#time').textContent,stage:document.querySelector('#stage').textContent,lock:document.querySelector('#lock').textContent,button:getComputedStyle(document.querySelector('#lock')).visibility,textColor:getComputedStyle(document.querySelector('#time')).color,border:getComputedStyle(document.querySelector('#card')).borderTopColor,nudge:document.querySelector('#visual').classList.contains('nudge'),hover:document.body.classList.contains('hover'),audioCount:Number(document.body.dataset.audioCount||0),audioState:document.body.dataset.audioState})`);
 const wait=async(fn,timeout=7000)=>{const at=Date.now();while(Date.now()-at<timeout){if(await fn())return;await delay(50);}throw Error('等待条件超时');};
 const move=async(x,y)=>{win.webContents.sendInputEvent({type:'mouseMove',x,y});await delay(150);};
 const click=async(x,y)=>{await move(x,y);win.webContents.sendInputEvent({type:'mouseDown',x,y,button:'left',clickCount:1});win.webContents.sendInputEvent({type:'mouseUp',x,y,button:'left',clickCount:1});await delay(150);};
 try{
  await wait(async()=>!!(await api('native')).state);await delay(400);
  assert.equal(win.isAlwaysOnTop(),true);assert.equal(win.isFocusable(),false);assert.equal(win.isVisible(),true);results.push('真实 BrowserWindow：无焦点、可见、always-on-top');
  await move(80,45);assert.equal((await read()).button,'visible');
  if(!getPrefs().locked)await click(211,113);assert.equal(getPrefs().locked,true);assert.equal((await read()).lock,'取消锁定');
  await move(100,60);await move(211,113);assert.equal((await read()).button,'visible');results.push('鼠标从数字移动到解锁按钮，按钮始终可见');
  await move(-20,-20);assert.equal((await read()).button,'hidden');assert.equal(getPrefs().locked,true);await move(80,45);assert.equal((await read()).button,'visible');assert.equal(getPrefs().locked,true);results.push('移出隐藏按钮，移入显示取消锁定；悬停不解锁');
  const before=win.getBounds();await click(211,113);assert.equal(getPrefs().locked,false);assert.deepEqual(win.getBounds(),before);results.push('点击解锁不触发拖动或计时操作');
  await click(211,113);assert.equal(getPrefs().locked,true);await move(-20,-20);
  await api('action',{type:'end'});await api('action',{type:'edit'});
  const draft={name:'原生窗口秒级验收',total:.4,stages:[{name:'颜色与动效',minutes:1/3},{name:'自动切换',minutes:1/15}]};
  await api('action',{type:'draft',payload:draft});await api('action',{type:'start'});await wait(async()=>(await read()).stage.includes('颜色与动效'));
  assert.equal((await read()).textColor,'rgb(255, 255, 255)');assert.equal((await read()).border,'rgb(245, 156, 70)');
  await api('action',{type:'pause'});await wait(async()=>(await read()).stage.includes('已暂停'));const frozen=(await read()).time;await delay(1200);assert.equal((await read()).time,frozen);assert.equal((await read()).nudge,false);await api('action',{type:'resume'});results.push('真实悬浮窗暂停冻结数字与动效，恢复继续计时');
  const samples=[];let observedMotion=false;
  const stationary=win.getBounds();
  await wait(async()=>{const x=await read();samples.push({at:Date.now(),...x});if(x.nudge)observedMotion=true;assert.deepEqual(win.getBounds(),stationary);return x.stage.includes('自动切换');},23000);
  assert.ok(samples.some(x=>x.textColor!=='rgb(255, 255, 255)'&&x.textColor!=='rgb(255, 83, 76)'));assert.ok(samples.some(x=>x.textColor==='rgb(255, 83, 76)'));assert.ok(observedMotion);await delay(250);assert.equal((await read()).textColor,'rgb(255, 255, 255)');assert.equal((await read()).border,'rgb(245, 156, 70)');results.push('20 秒阶段实际经历中间色与红色警示；最后 10% 有动效且原生窗口位置始终不变；下一阶段恢复白字橙框');
  await wait(async()=>(await read()).time==='计划时间结束',6000);assert.equal((await read()).nudge,false);assert.ok((await read()).audioCount>=2);assert.equal((await read()).audioState,'running');results.push('4 秒下一阶段自动结束，显示计划时间结束且停止动效；两次阶段提醒均启动真实 Web Audio');
  await writeFile(path.join(output,'finished.png'),(await win.webContents.capturePage()).toPNG());
  // A longer 10%-zone gives enough room to measure pulse cadence and hover suppression.
  await api('action',{type:'edit'});const slow={name:'脉冲间隔验收',total:2,stages:[{name:'末段动效验收',minutes:2}]};await api('action',{type:'draft',payload:slow});await api('action',{type:'start'});
  results.push('原生交互与计时测试使用独立测试计划，未读取或覆盖正式计划');
  await writeFile(path.join(output,'native-results.json'),JSON.stringify({passed:true,results,samples,finalBounds:win.getBounds(),prefs:getPrefs()},null,2));console.log('NATIVE_TEST_PASS',JSON.stringify(results));
 }catch(e){await writeFile(path.join(output,'native-results.json'),JSON.stringify({passed:false,results,error:e.stack,state:await read(),bounds:win.getBounds(),prefs:getPrefs()},null,2));console.error('NATIVE_TEST_FAIL',e);}
}
