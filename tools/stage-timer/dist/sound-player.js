// The page and desktop overlay share the same decoder and playback behavior.
export class SoundPlayer {
 constructor(){this.context=null;this.source=null;this.cache=new Map();this.sequence=0;}
 async play(setting,origin='',load=null){
  const seq=++this.sequence;
  this.context??=new AudioContext();await this.context.resume();
  if(this.context.state!=='running')throw Error('请点击试听启用声音');
  this.source?.stop();this.source=null;
  if(setting?.url){
   const url=origin+setting.url;
   let buffer=this.cache.get(url);
   if(!buffer){let bytes;if(load){bytes=await load(setting.url);}else{const res=await fetch(url);if(!res.ok)throw Error('音频读取失败');bytes=await res.arrayBuffer();}buffer=await this.context.decodeAudioData(bytes);this.cache.clear();this.cache.set(url,buffer);}
   if(seq!==this.sequence)return;
   const source=this.context.createBufferSource();source.buffer=buffer;source.connect(this.context.destination);this.source=source;source.start();source.stop(this.context.currentTime+Math.min(buffer.duration,30));
  }else{
   const buffer=this.context.createBuffer(1,Math.ceil(this.context.sampleRate*.68),this.context.sampleRate),samples=buffer.getChannelData(0);
   for(let i=0;i<samples.length;i++){const t=i/this.context.sampleRate,step=Math.floor(t/.22),local=t-step*.22;if(step<3&&local<.2)samples[i]=Math.sin(2*Math.PI*[660,880,990][step]*local)*.17*Math.min(1,local/.02)*Math.exp(-local*24);}
   const source=this.context.createBufferSource();source.buffer=buffer;source.connect(this.context.destination);source.start();this.source=source;
  }
 }
}
