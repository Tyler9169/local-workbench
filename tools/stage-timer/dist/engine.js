export const sample = () => ({name:'剪一条视频',total:180,stages:[{name:'找选题',minutes:30},{name:'找素材',minutes:60},{name:'剪辑',minutes:60},{name:'最后调整',minutes:30}]});
export function validation(p){
  if(!p || typeof p.name!=='string'||!p.name.trim())return '请填写任务名称';
  if(!Number.isFinite(p.total)||p.total<=0||p.total>10080)return '预计总时间须大于 0，且不超过 7 天';
  if(!Array.isArray(p.stages)||!p.stages.length)return '请至少添加一个阶段';
  if(p.stages.length>100)return '最多支持 100 个阶段';
  if(p.stages.some(s=>typeof s.name!=='string'||!s.name.trim()||!Number.isFinite(s.minutes)||s.minutes<1/60||s.minutes>10080))return '每个阶段都需要名称，时长至少 1 秒且不超过 7 天';
  const diff = Math.round(p.stages.reduce((n,s)=>n+s.minutes*60000,0))-Math.round(p.total*60000);
  if(diff!==0)return `阶段合计比预计总时间${diff>0?'多':'少'} ${duration(Math.abs(diff))}，请调整后开始`;
  return '';
}
export function duration(ms){const s=Math.round(ms/1000);return [s>=3600?`${Math.floor(s/3600)}小时`:'',s%3600>=60?`${Math.floor(s%3600/60)}分钟`:'',s%60?`${s%60}秒`:''].filter(Boolean).join(' ')||'0秒';}
export function start(plan,now){if(validation(plan))throw Error(validation(plan));return {plan:structuredClone(plan),status:'running',index:0,endAt:now+Math.round(plan.stages[0].minutes*60000),remaining:0,outcomes:[],startedAt:now,notice:''};}
export function settle(r,now){
  if(r.status!=='running')return [];
  const crossed=[];
  while(r.status==='running'&&now>=r.endAt){
    crossed.push(r.plan.stages[r.index].name);r.outcomes[r.index]='done';r.index++;
    if(r.index===r.plan.stages.length){r.status='finished';r.remaining=0;break;}
    r.endAt+=Math.round(r.plan.stages[r.index].minutes*60000);
  }
  if(crossed.length){
    const previous=r.plan.stages[r.index-1];
    r.notice=r.status==='finished'?'计划时间结束，请收尾并检查成果':`${previous.name}的${duration(previous.minutes*60000)}到了！请停止${previous.name}，开始${r.plan.stages[r.index].name}，下一阶段${duration(r.plan.stages[r.index].minutes*60000)}。`;
    if(crossed.length>1)r.notice=`已按真实时间跨过 ${crossed.length} 个阶段（${crossed.join('、')}）。`+(r.status==='finished'?r.notice:`当前：${r.plan.stages[r.index].name}，剩余 ${duration(r.endAt-now)}。`);
  }
  return crossed;
}
export function left(r,now){return r.status==='running'?Math.max(0,r.endAt-now):r.status==='paused'?r.remaining:0;}
export function totalLeft(r,now){return ['running','paused'].includes(r.status)?left(r,now)+r.plan.stages.slice(r.index+1).reduce((n,s)=>n+Math.round(s.minutes*60000),0):0;}
export function pause(r,now){settle(r,now);if(r.status==='running'){r.remaining=left(r,now);r.status='paused';}}
export function resume(r,now){if(r.status==='paused'){r.endAt=now+r.remaining;r.status='running';}}
export function skip(r,now){
  settle(r,now);if(!['running','paused'].includes(r.status))return;
  const paused=r.status==='paused';r.outcomes[r.index]='early';r.index++;
  if(r.index===r.plan.stages.length){r.status='finished';r.remaining=0;r.notice='已提前结束最后阶段，请收尾并检查成果';return;}
  r.remaining=Math.round(r.plan.stages[r.index].minutes*60000);r.endAt=now+r.remaining;
  r.status=paused?'paused':'running';r.notice=`已提前进入「${r.plan.stages[r.index].name}」，保留原定${duration(r.remaining)}${paused?'，当前仍暂停':''}。`;
}
export function validSaved(s){
  if(!s||s.version!==1||!s.draft||!Array.isArray(s.draft.stages)||typeof s.draft.name!=='string'||!Number.isFinite(s.draft.total)||s.draft.stages.some(x=>!x||typeof x.name!=='string'||!Number.isFinite(x.minutes)))return false;
  if(!s.run)return true;
  const r=s.run;return !validation(r.plan)&&['running','paused','finished','ended'].includes(r.status)&&Number.isInteger(r.index)&&r.index>=0&&r.index<=r.plan.stages.length&&(['finished','ended'].includes(r.status)||r.index<r.plan.stages.length)&&Number.isFinite(r.endAt)&&Number.isFinite(r.remaining)&&r.remaining>=0&&Array.isArray(r.outcomes);
}
