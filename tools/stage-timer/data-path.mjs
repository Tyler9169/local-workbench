import {mkdir,access,cp,rename,rm,readFile,writeFile} from 'node:fs/promises';
import {homedir} from 'node:os';
import path from 'node:path';
import {validSaved} from './dist/engine.js';
const exists=async p=>access(p).then(()=>true,()=>false);
export async function dataPath({override=process.env.STAGE_TIMER_DATA_DIR,home=homedir(),legacy}={}){
 if(override){await mkdir(override,{recursive:true});return override;}
 const dest=path.join(home,'Library/Application Support/StageTimer');
 if(await exists(dest))return dest;
 await mkdir(path.dirname(dest),{recursive:true});
 const temp=dest+'.migration-'+process.pid;
 try{
  await mkdir(temp);
  if(legacy&&await exists(legacy)){
   if(await exists(path.join(legacy,'runtime.json'))){const saved=JSON.parse(await readFile(path.join(legacy,'runtime.json'),'utf8'));if(!validSaved(saved.state))throw Error('旧任务数据无效，已保留原文件，未建立空任务。');}
   for(const name of ['runtime.json','overlay.json','sounds','electron'])if(await exists(path.join(legacy,name)))await cp(path.join(legacy,name),path.join(temp,name),{recursive:true});
  }
  await writeFile(path.join(temp,'migration.json'),JSON.stringify({schema:1,at:new Date().toISOString(),from:legacy||null}));
  // Never overwrite an existing destination, even if another launcher won the race.
  if(await exists(dest)){await rm(temp,{recursive:true});return dest;}
  await rename(temp,dest);return dest;
 }catch(e){await rm(temp,{recursive:true,force:true});throw e;}
}
