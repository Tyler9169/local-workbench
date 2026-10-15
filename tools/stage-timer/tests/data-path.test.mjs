import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,readFile,access,rm} from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {dataPath} from '../data-path.mjs';
import {sample} from '../dist/engine.js';
test('迁移任务、位置和提示音一次，保留源数据，已存在目标不覆盖',async()=>{
 const home=await mkdtemp(path.join(os.tmpdir(),'timer-migrate-'));
 try{
 const legacy=path.join(home,'old');await mkdir(legacy);await mkdir(path.join(legacy,'sounds'));
 const files={'runtime.json':JSON.stringify({state:{version:1,draft:sample(),run:null}}),'overlay.json':'{"locked":true,"x":210,"y":168}','sounds/settings.json':'{"selected":"custom-proof"}','sounds/custom-proof':'audio-proof'};
 for(const [n,v]of Object.entries(files))await writeFile(path.join(legacy,n),v);
 const dest=await dataPath({home,legacy});
 for(const [n,v]of Object.entries(files)){assert.equal(await readFile(path.join(dest,n),'utf8'),v);assert.equal(await readFile(path.join(legacy,n),'utf8'),v);}
 await writeFile(path.join(dest,'overlay.json'),'new-setting');await dataPath({home,legacy});assert.equal(await readFile(path.join(dest,'overlay.json'),'utf8'),'new-setting');
 }finally{await rm(home,{recursive:true,force:true});}
});
test('损坏迁移不创建空目标，原文件不变',async()=>{
 const home=await mkdtemp(path.join(os.tmpdir(),'timer-invalid-'));
 try{const legacy=path.join(home,'old');await mkdir(legacy);await writeFile(path.join(legacy,'runtime.json'),'broken');await assert.rejects(dataPath({home,legacy}));assert.equal(await readFile(path.join(legacy,'runtime.json'),'utf8'),'broken');await assert.rejects(access(path.join(home,'Library/Application Support/StageTimer')));}finally{await rm(home,{recursive:true,force:true});}
});
