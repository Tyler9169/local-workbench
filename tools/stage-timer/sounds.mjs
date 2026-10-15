import {readFile,writeFile,readdir,mkdir,rename,unlink} from 'node:fs/promises';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
const exec=promisify(execFile),MAX=5*1024*1024;
export async function createSounds(dir){
 const folder=dir+'/sounds';await mkdir(folder,{recursive:true});
 let selected='builtin',custom=null,system=[];
 if(process.platform==='darwin'){
  for(const file of await readdir('/System/Library/Sounds').catch(()=>[])){
   if(!/^[\w-]+\.aiff$/.test(file))continue;
   const name=file.slice(0,-5),id='system-'+name;
   try{await exec('/usr/bin/afconvert',['-f','WAVE','-d','LEI16','/System/Library/Sounds/'+file,folder+'/'+id+'.wav']);system.push({id,name:'系统 · '+name});}catch{}
  }
 }
 try{const saved=JSON.parse(await readFile(folder+'/settings.json','utf8'));selected=saved.selected;custom=saved.custom;}catch{}
 const options=()=>[{id:'builtin',name:'内置 · 三声清铃'},...system,...(custom?[{id:custom.id,name:'上传 · '+custom.name}]:[])];
 if(!options().some(x=>x.id===selected))selected='builtin';
 const snapshot=()=>({selected,options:options(),url:selected==='builtin'?null:'/api/sound-file?id='+encodeURIComponent(selected)});
 async function save(next,upload){await writeFile(folder+'/settings.tmp',JSON.stringify({selected:next,custom:upload}));await rename(folder+'/settings.tmp',folder+'/settings.json');selected=next;custom=upload;}
 let queue=Promise.resolve();
 async function update(data){
  if(data.type==='select'){
   if(!options().some(x=>x.id===data.id))throw Error('请选择有效提示音');
   await save(data.id,custom);
  }else if(data.type==='remove'){
   const old=custom;await save(selected===custom?.id?'builtin':selected,null);if(old)await unlink(folder+'/'+old.id).catch(()=>{});
  }else if(data.type==='upload'){
   if(typeof data.base64!=='string'||data.base64.length>Math.ceil(MAX/3)*4||!/^[A-Za-z0-9+/]*={0,2}$/.test(data.base64))throw Error('音频最大支持 5 MB');
   const bytes=Buffer.from(data.base64,'base64');
   if(!bytes.length||bytes.length>MAX)throw Error('音频最大支持 5 MB');
   const mime=data.mime;
   if(!['audio/mpeg','audio/wav','audio/ogg','audio/mp4','audio/webm'].includes(mime))throw Error('不支持的音频格式');
   const id='custom-'+Date.now()+'-'+Math.random().toString(36).slice(2,8);
   const upload={id,name:String(data.name||'自定义提示音').slice(0,100),mime};
   await writeFile(folder+'/'+id,bytes);await save(id,upload);
  }else throw Error('未知声音设置');
  return snapshot();
 }
 return {snapshot,update(data){const task=queue.then(()=>update(data));queue=task.catch(()=>{});return task;},async file(id){
  if(system.some(x=>x.id===id))return {bytes:await readFile(folder+'/'+id+'.wav'),mime:'audio/wav'};
  if(custom&&id===custom.id)return {bytes:await readFile(folder+'/'+custom.id),mime:custom.mime};
  throw Error('声音文件不存在');
 }};
}
