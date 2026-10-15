import {sample,validSaved,start,settle,pause,resume,skip,totalLeft} from './dist/engine.js';
// One clock owner shared by the webpage and native overlay.
export class Runtime {
  constructor(saved=null){this.state=saved?.state||null;this.revision=saved?.revision||0;this.event=saved?.event||null;this.claimed=saved?.claimed||0;this.notifications=saved?.notifications||false;this.nativeSeen=0;this.visible=false;this.onChange=()=>{};}
  snapshot(){return {state:this.state,revision:this.revision,event:this.event,nativeActive:Date.now()-this.nativeSeen<2500,visible:this.visible,notifications:this.notifications};}
  disk(){return {...this.snapshot(),claimed:this.claimed};}
  change(){this.revision++;this.onChange();}
  activate(state){if(!this.state){if(!validSaved(state))throw Error('无法读取网页计划');this.state=structuredClone(state);this.change();}this.tick();}
  tick(now=Date.now()){if(this.state?.run&&settle(this.state.run,now).length){this.event={id:(this.event?.id||0)+1,message:this.state.run.notice};this.change();}}
  claim(id){if(!this.event||id!==this.event.id||id<=this.claimed)return false;this.claimed=id;this.onChange();return true;}
  action(type,payload,now=Date.now()){
    if(!this.state)throw Error('桌面计时尚未启用');this.tick(now);const s=this.state,r=s.run;
    switch(type){
      case 'draft': if(s.run)throw Error('请先返回计划');if(!validSaved({version:1,draft:payload,run:null}))throw Error('计划格式错误');s.draft=structuredClone(payload);break;
      case 'start': if(s.run)throw Error('已有计时');s.run=start(s.draft,now);break;
      case 'pause': if(r)pause(r,now);break;
      case 'resume': if(r)resume(r,now);break;
      case 'skip': if(r)skip(r,now);break;
      case 'end': if(r&&['running','paused'].includes(r.status)){r.stoppedProgress=(1-totalLeft(r,now)/(r.plan.total*60000))*100;r.status='ended';r.remaining=0;r.notice='你已结束本次计时。计划已保留，成果是否完成由你判断。';}break;
      case 'edit': if(r&&['running','paused'].includes(r.status))throw Error('请先结束计时');s.run=null;break;
      case 'notifications':this.notifications=payload===true;break;
      default:throw Error('未知操作');
    }this.change();return this.snapshot();
  }
}
