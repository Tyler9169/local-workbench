import http from 'node:http';
import {readFile,writeFile,mkdir,rename} from 'node:fs/promises';
import {existsSync,openSync,closeSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
import {randomBytes} from 'node:crypto';
import {createSounds} from './sounds.mjs';
import {dataPath} from './data-path.mjs';
import {Runtime} from './runtime.mjs';
import {validSaved} from './dist/engine.js';
const port=Number(process.env.PORT||43121),origin=`http://127.0.0.1:${port}`,root=fileURLToPath(new URL('.',import.meta.url));
const dataDir=await dataPath({legacy:fileURLToPath(new URL('.data/',import.meta.url))});
let saved=null;try{saved=JSON.parse(await readFile(`${dataDir}/runtime.json`,'utf8'));if(!validSaved(saved.state))throw Error('invalid');}catch(e){if(e.code!=='ENOENT'){console.error('桌面保存数据无法读取，已保留原文件。请检查 .data/runtime.json。');process.exit(1);}}
const sounds=await createSounds(dataDir);
const runtime=new Runtime(saved);let persist=Promise.resolve(),persistError='',child=null,launching=null;const secret=randomBytes(32).toString('hex');
runtime.onChange=()=>{const data=JSON.stringify(runtime.disk());persist=persist.then(async()=>{await writeFile(`${dataDir}/runtime.json.tmp`,data);await rename(`${dataDir}/runtime.json.tmp`,`${dataDir}/runtime.json`);persistError='';}).catch(()=>{persistError='桌面状态保存失败，请检查磁盘空间；不要退出程序。';});};
const files={'/':'index.html','/index.html':'index.html','/app.js':'app.js','/engine.js':'engine.js','/style.css':'style.css','/remote.js':'remote.js','/sound-player.js':'sound-player.js'};
function json(res,status,value){res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'});res.end(JSON.stringify(value));}
function snapshot(){return {...runtime.snapshot(),saveError:persistError,sound:sounds.snapshot()};}
async function body(req,limit=100000){let value='';for await(const chunk of req){value+=chunk;if(value.length>limit)throw Error('请求过大');}return JSON.parse(value||'{}');}
async function launch(){
 runtime.visible=true;
 if(launching)return launching;if(child&&Date.now()-runtime.nativeSeen<2500)return;if(child)throw Error('桌面组件暂时失去连接，请重启启动终端后再试');
 const executable=process.env.STAGE_TIMER_ELECTRON||fileURLToPath(new URL('node_modules/electron/dist/Electron.app/Contents/MacOS/Electron',import.meta.url));
 if(!existsSync(executable))throw Error('桌面组件未安装，请在项目目录运行 npm install');
 launching=new Promise((resolve,reject)=>{const env={...process.env,STAGE_TIMER_ORIGIN:origin,STAGE_TIMER_NATIVE_TOKEN:secret,STAGE_TIMER_DATA_DIR:dataDir};delete env.ELECTRON_RUN_AS_NODE;const log=openSync(`${dataDir}/desktop.log`,'a');child=spawn(executable,process.env.STAGE_TIMER_ELECTRON?[]:[root],{cwd:root,env,stdio:['ignore',log,log]});closeSync(log);child.once('error',e=>{child=null;reject(e);});child.once('exit',()=>{child=null;runtime.visible=false;runtime.nativeSeen=0;});const begin=Date.now();const check=setInterval(()=>{if(Date.now()-runtime.nativeSeen<1000){clearInterval(check);resolve();}else if(!child||Date.now()-begin>15000){clearInterval(check);if(child)child.kill();reject(Error('桌面窗口启动失败，请检查本地 Electron 安装。'));}},100);}).finally(()=>{launching=null;});return launching;
}
const server=http.createServer(async(req,res)=>{
 try{
  if(req.headers.host!==`127.0.0.1:${port}`&&req.headers.host!==`localhost:${port}`){json(res,403,{error:'只接受本机地址'});return;}
  const path=new URL(req.url,origin).pathname;
  if(path.startsWith('/api/')){
   const native=req.headers.authorization===`Bearer ${secret}`;
   if(req.headers.origin&&![origin,`http://localhost:${port}`].includes(req.headers.origin)){json(res,403,{error:'不接受外部网页请求'});return;}
   if(req.headers['sec-fetch-site']==='cross-site'){json(res,403,{error:'不接受跨站请求'});return;}
   if(req.method==='GET'&&path==='/api/health'){json(res,200,{app:'local.tyler.stagetimer',version:'1.0.0'});return;}
   if(req.method==='GET'&&path==='/api/sounds'){json(res,200,sounds.snapshot());return;}
   if(req.method==='GET'&&path==='/api/sound-file'){const f=await sounds.file(new URL(req.url,origin).searchParams.get('id'));res.writeHead(200,{'Content-Type':f.mime,'X-Content-Type-Options':'nosniff','Cache-Control':'no-store'});res.end(f.bytes);return;}
   if(req.method==='GET'&&path==='/api/state'){runtime.tick();json(res,200,snapshot());return;}
   if(req.method!=='POST'||!req.headers['content-type']?.startsWith('application/json')){json(res,405,{error:'需要 JSON POST'});return;}
   const data=await body(req,path==='/api/sounds'?7100000:100000);
   if(path==='/api/sounds'){json(res,200,await sounds.update(data));return;}
   if(path==='/api/native'){if(!native){json(res,403,{error:'禁止访问'});return;}runtime.nativeSeen=Date.now();runtime.tick();json(res,200,snapshot());return;}
   if(path==='/api/float'){runtime.activate(data.state);runtime.visible=data.visible!==false;if(runtime.visible)await launch();json(res,200,snapshot());return;}
   if(path==='/api/action'){runtime.action(data.type,data.payload);json(res,200,snapshot());return;}
   if(path==='/api/claim'){json(res,200,{claimed:runtime.claim(data.id)});return;}
   json(res,404,{error:'不存在'});return;
  }
  const file=files[path];if(!file){res.writeHead(404);res.end('Not found');return;}
  const type=file.endsWith('.js')?'text/javascript':file.endsWith('.css')?'text/css':'text/html';res.writeHead(200,{'Content-Type':`${type}; charset=utf-8`,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});res.end(await readFile(new URL('dist/'+file,import.meta.url)));
 }catch(e){json(res,400,{error:e.message});}
});
setInterval(()=>runtime.tick(),100).unref();
server.on('error',e=>{console.error(e.code==='EADDRINUSE'?`端口 ${port} 已占用，不会停止其他程序。`:e.message);process.exit(1);});
server.listen(port,'127.0.0.1',()=>console.log(`留刻：http://127.0.0.1:${port}\n网页中点击“开启悬浮计时”。关闭此终端会停止本地服务。`));
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,async()=>{if(child)child.kill();await persist;server.close();process.exit();});
