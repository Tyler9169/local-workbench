import {SoundPlayer} from '../dist/sound-player.js';
const noticePlayer=new SoundPlayer();
import {colorsAt} from './visual.js';
const time=document.querySelector('#time'),stage=document.querySelector('#stage'),visual=document.querySelector('#visual'),button=document.querySelector('#lock');
let snapshot=null,hover=false,dragging=false,locked=false,lastPulse=-Infinity,lastStage='',audio,pointerDragging=false;
function format(ms){const s=Math.ceil(ms/1000);return (s>=3600?String(Math.floor(s/3600)).padStart(2,'0')+':':'')+String(Math.floor(s%3600/60)).padStart(2,'0')+':'+String(s%60).padStart(2,'0');}
function stopMotion(){visual.classList.remove('nudge');}
function render(){
 const r=snapshot?.state?.run,active=r&&['running','paused'].includes(r.status);let ratio=1,remaining=0;
 if(active){remaining=r.status==='paused'?r.remaining:Math.max(0,r.endAt-Date.now());ratio=remaining/(r.plan.stages[r.index].minutes*60000);time.textContent=format(remaining);stage.textContent=`${r.plan.stages[r.index].name} · 第${r.index+1}/${r.plan.stages.length}步${r.status==='paused'?' · 已暂停':''}`;}else{time.textContent=r?.status==='finished'?'计划时间结束':r?.status==='ended'?'计时已结束':'--:--';stage.textContent=r?'请收尾并检查成果':'等待开始任务';}
 time.classList.toggle('long',active&&remaining>=3600000);time.classList.toggle('message',!!r&&!active);
 const colors=colorsAt(ratio);document.documentElement.style.setProperty('--number',`rgb(${colors.text.join(',')})`);document.documentElement.style.setProperty('--border',`rgb(${colors.border.join(',')})`);
 const key=r?`${r.startedAt}:${r.index}`:'';if(key!==lastStage){lastStage=key;lastPulse=-Infinity;stopMotion();}
 const allowed=active&&r.status==='running'&&ratio<=.1&&remaining>0&&!hover&&!dragging&&!snapshot?.disconnected;
 if(!allowed)stopMotion();else if(performance.now()-lastPulse>=5000){lastPulse=performance.now();visual.classList.remove('nudge');void visual.offsetWidth;visual.classList.add('nudge');}
 if(snapshot?.disconnected){stage.textContent='本地服务断开 · 请重新启动';stopMotion();}
}
window.overlay.onState(value=>{snapshot=value;locked=value.locked;dragging=value.dragging;hover=value.hover;document.body.classList.toggle('locked',locked);document.body.classList.toggle('dragging',dragging);document.body.classList.toggle('hover',hover);button.textContent=locked?'取消锁定':'锁定';button.setAttribute('aria-label',locked?'取消锁定悬浮窗':'锁定悬浮窗');render();});
const openMain=document.querySelector('#open-main');
openMain.addEventListener('pointerdown',e=>e.stopPropagation());
openMain.onclick=async e=>{e.stopPropagation();openMain.disabled=true;try{const opened=await window.overlay.openMain();openMain.textContent=opened?'打开主界面':'打开失败，重试';}catch{openMain.textContent='打开失败，重试';}finally{openMain.disabled=false;}};
button.addEventListener('pointerdown',e=>e.stopPropagation());button.onclick=async e=>{e.stopPropagation();await window.overlay.lock();};
document.querySelector('#card').addEventListener('pointerdown',e=>{if(e.button!==0||locked||e.target.closest('button'))return;e.preventDefault();pointerDragging=true;stopMotion();window.overlay.dragStart({x:e.screenX,y:e.screenY});e.currentTarget.setPointerCapture(e.pointerId);});
for(const type of ['pointerup','pointercancel','lostpointercapture'])document.addEventListener(type,e=>{if(!pointerDragging)return;if(type==='pointerup')window.overlay.dragMove({x:e.screenX,y:e.screenY});pointerDragging=false;if(frame){cancelAnimationFrame(frame);frame=0;}window.overlay.dragEnd();});
document.addEventListener('mouseenter',()=>{hover=true;stopMotion();window.overlay.hover(true);});
document.addEventListener('mouseleave',()=>{hover=false;window.overlay.hover(false);});
let nextPoint=null,frame=0;document.addEventListener('pointermove',e=>{if(!pointerDragging||locked)return;nextPoint={x:e.screenX,y:e.screenY};if(!frame)frame=requestAnimationFrame(()=>{frame=0;window.overlay.dragMove(nextPoint);});});
visual.addEventListener('animationend',stopMotion);
window.overlay.onNotice(async()=>{try{await noticePlayer.play(snapshot?.sound,'',url=>window.overlay.soundBytes(url));document.body.dataset.audioCount=String(Number(document.body.dataset.audioCount||0)+1);document.body.dataset.audioState=noticePlayer.context.state;}catch{stage.textContent='提示音播放失败 · 请在主界面重新选择并试听';}});
setInterval(render,50);window.overlay.ready();

function reportControls(){window.overlay.controls([...document.querySelectorAll('.hover-action')].map(el=>{const r=el.getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height};}));}
new ResizeObserver(reportControls).observe(document.body);
new ResizeObserver(reportControls).observe(button);
new ResizeObserver(reportControls).observe(openMain);
reportControls();
