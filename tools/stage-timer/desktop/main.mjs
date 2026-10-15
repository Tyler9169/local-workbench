import {app,BrowserWindow,ipcMain,screen,Notification,Menu,powerMonitor,shell} from 'electron';
import {readFileSync,writeFileSync,mkdirSync,renameSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {clampBounds} from './visual.js';
import {openMain} from './open-main.mjs';
const origin=process.env.STAGE_TIMER_ORIGIN,token=process.env.STAGE_TIMER_NATIVE_TOKEN,dir=process.env.STAGE_TIMER_DATA_DIR;
if(!origin||!token||!dir){console.error('请从网页的“开启悬浮计时”启动桌面窗。');app.exit(1);}
app.setPath('userData',path.join(dir,'electron'));app.setName('留刻悬浮计时');app.commandLine.appendSwitch('autoplay-policy','no-user-gesture-required');
const singleton=app.requestSingleInstanceLock();if(!singleton)app.quit();
let win,snapshot={},ready=false,hover=false,drag=null,prefs={locked:false,x:80,y:80},lastId=0;
try{const p=JSON.parse(readFileSync(path.join(dir,'overlay.json'),'utf8'));if(typeof p.locked==='boolean'&&Number.isFinite(p.x)&&Number.isFinite(p.y))prefs=p;}catch{}
function save(){try{mkdirSync(dir,{recursive:true});writeFileSync(path.join(dir,'overlay.json.tmp'),JSON.stringify(prefs));renameSync(path.join(dir,'overlay.json.tmp'),path.join(dir,'overlay.json'));}catch{snapshot.saveError='悬浮位置保存失败，请检查磁盘空间';}}
function areas(){return screen.getAllDisplays().map(d=>d.workArea);}
function clamp(){if(!win)return;const b=clampBounds(win.getBounds(),areas());win.setBounds(b);prefs.x=b.x;prefs.y=b.y;save();}
function send(){if(ready&&!win.isDestroyed())win.webContents.send('state',{...snapshot,origin,locked:prefs.locked,hover,dragging:!!drag});}
// Native cursor tracking remains active while clicks pass through the window.
let controlRects=[],ignoringMouse=false;
function updateMouse(){
 if(!win||win.isDestroyed()||!ready)return;
 const b=win.getBounds(),p=screen.getCursorScreenPoint(),x=p.x-b.x,y=p.y-b.y;
 const inside=win.isVisible()&&x>=0&&y>=0&&x<b.width&&y<b.height;
 if(prefs.locked&&hover!==inside){hover=inside;send();}
 const onControl=inside&&controlRects.some(r=>x>=r.x&&y>=r.y&&x<r.x+r.width&&y<r.y+r.height);
 const ignore=prefs.locked&&!onControl;
 if(ignore!==ignoringMouse){win.setIgnoreMouseEvents(ignore,{forward:true});ignoringMouse=ignore;}
}
async function api(endpoint,data={}){const response=await fetch(origin+'/api/'+endpoint,{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${token}`},body:JSON.stringify(data),signal:AbortSignal.timeout(1500)});if(!response.ok)throw Error('server');return response.json();}
let polling=false;
async function poll(){if(polling||!ready)return;polling=true;try{snapshot=await api('native');if(snapshot.visible&&!win.isVisible())win.showInactive();else if(!snapshot.visible&&win.isVisible())win.hide();send();if(snapshot.event?.id>lastId){const id=snapshot.event.id;lastId=id;if((await api('claim',{id})).claimed){win.webContents.send('notice',snapshot.event);if(snapshot.notifications&&Notification.isSupported())new Notification({title:'留刻 · 阶段提醒',body:snapshot.event.message,silent:true}).show();}}}catch{snapshot.disconnected=true;send();}finally{polling=false;}}
if(singleton)app.whenReady().then(async()=>{
 const bounds=clampBounds({x:prefs.x,y:prefs.y,width:246,height:132},areas());
 win=new BrowserWindow({...bounds,frame:false,transparent:true,resizable:false,minimizable:false,maximizable:false,fullscreenable:false,hasShadow:false,show:false,focusable:false,acceptFirstMouse:true,skipTaskbar:true,alwaysOnTop:true,type:'panel',webPreferences:{preload:fileURLToPath(new URL('preload.cjs',import.meta.url)),contextIsolation:true,nodeIntegration:false,sandbox:true,backgroundThrottling:false}});
 win.setAlwaysOnTop(true,'floating');win.setVisibleOnAllWorkspaces(true,{visibleOnFullScreen:true});
 win.webContents.setWindowOpenHandler(()=>({action:'deny'}));win.webContents.on('will-navigate',e=>e.preventDefault());
 Menu.setApplicationMenu(Menu.buildFromTemplate([{label:'留刻',submenu:[{label:'退出悬浮窗',click:()=>app.quit()}]}]));
 ipcMain.on('ready',e=>{if(e.sender!==win.webContents)return;ready=true;clamp();void poll();});
 ipcMain.handle('sound-bytes',async(e,url)=>{if(e.sender!==win.webContents||typeof url!=='string'||!/^\/api\/sound-file\?id=[A-Za-z0-9%-]+$/.test(url))throw Error('无效音频');const response=await fetch(origin+url,{headers:{Authorization:`Bearer ${token}`},signal:AbortSignal.timeout(5000)});if(!response.ok)throw Error('音频读取失败');return response.arrayBuffer();});
 ipcMain.handle('open-main',async e=>{if(e.sender!==win.webContents)return false;try{await openMain({origin,app,shell});return true;}catch{return false;}});
 ipcMain.on('controls',(e,rects)=>{if(e.sender!==win.webContents||!Array.isArray(rects))return;controlRects=rects.slice(0,2).filter(r=>['x','y','width','height'].every(k=>Number.isFinite(r?.[k]))&&r.width>0&&r.height>0&&r.width<=246&&r.height<=132);updateMouse();});
 ipcMain.handle('lock',e=>{if(e.sender!==win.webContents)return;prefs.locked=!prefs.locked;drag=null;updateMouse();save();send();return prefs.locked;});
 ipcMain.on('hover',(e,value)=>{if(e.sender!==win.webContents)return;if(prefs.locked){updateMouse();return;}hover=value===true;send();});
 ipcMain.on('drag-start',(e,point)=>{if(e.sender!==win.webContents||prefs.locked||!Number.isFinite(point?.x)||!Number.isFinite(point?.y))return;const bounds=win.getBounds();drag={dx:point.x-bounds.x,dy:point.y-bounds.y};send();});
 ipcMain.on('drag-move',(e,point)=>{if(e.sender!==win.webContents||prefs.locked||!drag||!Number.isFinite(point?.x)||!Number.isFinite(point?.y))return;win.setBounds(clampBounds({...win.getBounds(),x:point.x-drag.dx,y:point.y-drag.dy},areas()));});
 ipcMain.on('drag-end',e=>{if(e.sender!==win.webContents||!drag)return;drag=null;clamp();send();});
 for(const event of ['display-added','display-removed','display-metrics-changed'])screen.on(event,()=>{drag=null;clamp();send();});
 powerMonitor.on('resume',()=>{drag=null;void poll();clamp();});
 app.on('second-instance',()=>{win.showInactive();});
 app.on('before-quit',()=>{if(win&&!win.isDestroyed()){drag=null;clamp();}});
 await win.loadFile(fileURLToPath(new URL('float.html',import.meta.url)));setInterval(poll,100);setInterval(updateMouse,16);
 if(process.env.STAGE_TIMER_SELF_TEST==='1')import('../tests/native-runner.mjs').then(m=>m.run({win,api,getPrefs:()=>({...prefs}),dataDir:dir})).catch(console.error);
});
