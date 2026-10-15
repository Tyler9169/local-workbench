import {app,Menu,shell,dialog} from 'electron';
import {spawn} from 'node:child_process';
import {mkdirSync,openSync,closeSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
if(process.env.STAGE_TIMER_NATIVE_TOKEN){
 void import('./main.mjs');
}else{
 void (async()=>{
 const port=Number(process.env.STAGE_TIMER_TEST_PORT||43121),origin=`http://127.0.0.1:${port}`;
 const dir=process.env.STAGE_TIMER_DATA_DIR||path.join(app.getPath('appData'),'StageTimer');
 app.setPath('userData',path.join(dir,'launcher'));app.setName('留刻计时器');
 const single=app.requestSingleInstanceLock();let child,quitting=false,opened=false;
 const open=async()=>{await shell.openExternal(origin+'/');};
 if(!single)app.quit();else{
 app.on('second-instance',()=>{if(opened)void open();});
 app.on('activate',()=>{if(opened)void open();});
 app.on('window-all-closed',()=>{});
 process.on('SIGTERM',()=>app.quit());
 process.on('SIGINT',()=>app.quit());
 app.on('before-quit',e=>{if(child&&!quitting){e.preventDefault();quitting=true;child.once('exit',()=>app.quit());child.kill('SIGTERM');}});
 await app.whenReady();
 Menu.setApplicationMenu(Menu.buildFromTemplate([{label:'留刻计时器',submenu:[{label:'打开计时器',click:()=>void open()},{label:'打开数据目录',click:()=>void shell.openPath(dir)},{type:'separator'},{label:'退出留刻',role:'quit'}]}]));
 try{
  let response=null;try{response=await fetch(origin+'/api/health',{signal:AbortSignal.timeout(1000)});}catch{}
  if(response){const info=await response.json().catch(()=>null);if(info?.app!=='local.tyler.stagetimer')throw Error('计时器端口被其他服务占用。请先退出旧版计时器，再重新打开；不会停止其他程序。');}
  else{
   const root=fileURLToPath(new URL('../',import.meta.url));mkdirSync(dir,{recursive:true});const log=openSync(path.join(dir,'server.log'),'a',0o600);
   const env={...process.env,PORT:String(port),STAGE_TIMER_DATA_DIR:dir,STAGE_TIMER_ELECTRON:process.execPath};delete env.ELECTRON_RUN_AS_NODE;delete env.STAGE_TIMER_SELF_TEST;
   child=spawn(path.join(process.resourcesPath,'node'),[path.join(root,'server.mjs')],{cwd:root,env,stdio:['ignore',log,log]});closeSync(log);
   let failure=null;child.on('error',e=>failure=e);child.on('exit',()=>{if(!quitting&&opened){dialog.showErrorBox('留刻服务已停止','任务文件已保留，请重新打开应用。');app.quit();}});
   let ready=false;for(let i=0;i<100;i++){if(failure)throw failure;if(child.exitCode!==null)throw Error('服务启动失败，请查看数据目录中的 server.log。');try{const r=await fetch(origin+'/api/health');if((await r.json()).app==='local.tyler.stagetimer'){ready=true;break;}}catch{}await new Promise(r=>setTimeout(r,100));}
   if(!ready)throw Error('服务启动超时，请查看数据目录中的 server.log。');
  }
  opened=true;await open();
 }catch(e){dialog.showErrorBox('留刻未能启动',e.message);app.quit();}
 }
 })();
}
