import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {createSounds} from '../sounds.mjs';
test('声音选择、上传、拒绝非法设置和重启恢复',async()=>{
 const dir=await mkdtemp(tmpdir()+'/stage-sounds-');
 try{
  const sounds=await createSounds(dir);assert.equal(sounds.snapshot().selected,'builtin');
  const system=sounds.snapshot().options.find(x=>x.id.startsWith('system-'));
  if(process.platform==='darwin'){assert.ok(system);await sounds.update({type:'select',id:system.id});const file=await sounds.file(system.id);assert.equal(file.bytes.toString('ascii',0,4),'RIFF');}
  await assert.rejects(sounds.update({type:'select',id:'../../other'}));
  await assert.rejects(sounds.update({type:'upload',base64:'abc',mime:'text/html'}));
  const source=system?(await sounds.file(system.id)).bytes:Buffer.from('test');
  const choice=await sounds.update({type:'upload',name:'我的铃声.wav',mime:'audio/wav',base64:source.toString('base64')});
  const restored=await createSounds(dir);assert.equal(restored.snapshot().selected,choice.selected);assert.deepEqual((await restored.file(choice.selected)).bytes,source);
  await restored.update({type:'select',id:'builtin'});assert.equal(restored.snapshot().url,null);
 }finally{await rm(dir,{recursive:true,force:true});}
});
