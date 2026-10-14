'use strict';
const $=s=>document.querySelector(s);
const icons={image:'<rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="8" cy="8" r="1.5"/><path d="m3 16 5-5 5 5 3-3 5 5"/>',shirt:'<path d="m8 3-5 3 2 5 3-1v11h8V10l3 1 2-5-5-3c0 4-8 4-8 0Z"/>',download:'<path d="M12 3v12m-5-5 5 5 5-5M4 16v5h16v-5"/>',audio:'<path d="M4 10v4m4-8v12m4-15v18m4-15v12m4-8v4"/>',layers:'<path d="m12 3 10 5-10 5L2 8l10-5Zm-10 9 10 5 10-5M2 16l10 5 10-5"/>',play:'<rect x="3" y="3" width="18" height="18" rx="5"/><path d="m10 8 6 4-6 4V8Z"/>',chart:'<path d="M4 3v18h17M8 16v-5m5 5V7m5 9V4"/>',terminal:'<rect x="2" y="4" width="20" height="16" rx="3"/><path d="m6 9 3 3-3 3m6 0h5"/>',code:'<path d="m8 5-6 7 6 7m8-14 6 7-6 7m-3-17-2 20"/>',news:'<rect x="4" y="3" width="16" height="18" rx="2"/><path d="M8 7h8M8 11h4m-4 4h8m-8 3h5"/>',spark:'<path d="m12 2 3 7 7 3-7 3-3 7-3-7-7-3 7-3 3-7Z"/>',grid:'<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',home:'<path d="m3 10 9-7 9 7v11h-7v-7h-4v7H3V10Z"/>'};
const svg=name=>`<svg viewBox="0 0 24 24" aria-hidden="true">${icons[name]||icons.grid}</svg>`;
const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let tools=[],category='全部工具',kind='全部形态',favorites=new Set(),favoritesOnly=false,busy=new Set(),detailId=null,toastTimer;
try{const saved=JSON.parse(localStorage.getItem('workbench-favorites')||'[]');if(Array.isArray(saved))favorites=new Set(saved.filter(x=>typeof x==='string'));}catch{}
const categories=[['全部工具','grid'],['日常工具','home'],['影音创作','play'],['开发分析','terminal'],['资讯灵感','spark']];
function toast(message,error=false){clearTimeout(toastTimer);$('#toast').textContent=message;$('#toast').classList.toggle('error',error);$('#toast').hidden=false;toastTimer=setTimeout(()=>$('#toast').hidden=true,error?12000:6500);}
function label(t){if(t.kind==='CLI / MCP')return '查看用法';if(busy.has(t.id))return '正在打开…';if(t.kind==='桌面应用')return '打开应用';if(t.kind==='项目目录')return '打开目录';if(t.kind==='在线网页')return '打开网站';return t.state==='running'?'进入工具':'启动并打开';}
function render(){
 $('.quick').hidden=tools.length===0;
 $('#nav').innerHTML=categories.map(([name,icon])=>`<button class="nav-item ${category===name?'active':''}" data-category="${name}" aria-pressed="${category===name}">${svg(icon)}${name}<small>${name==='全部工具'?tools.length:tools.filter(t=>t.category===name).length}</small></button>`).join('');
 const kinds=['全部形态',...new Set(tools.map(t=>t.kind))];
 $('#filters').innerHTML=kinds.map(k=>`<button class="filter" data-kind="${k}" aria-pressed="${kind===k}">${k}</button>`).join('');
 $('#favorite-filter').setAttribute('aria-pressed',favoritesOnly);$('#favorite-filter').textContent=favoritesOnly?'★ 只看收藏':'☆ 只看收藏';
 const query=$('#search').value.trim().toLocaleLowerCase();
 const visible=tools.filter(t=>(category==='全部工具'||t.category===category)&&(kind==='全部形态'||t.kind===kind)&&(!favoritesOnly||favorites.has(t.id))&&`${t.name} ${t.subtitle} ${t.description} ${t.category}`.toLocaleLowerCase().includes(query));
 $('#section-title').innerHTML=`${esc(category)} <span>${visible.length}</span>`;
 $('#grid').innerHTML=visible.map((t,i)=>`<article class="card"><div class="card-top"><div class="tool-icon tone-${categories.findIndex(c=>c[0]===t.category)-1}">${svg(t.icon)}</div><button class="icon-button star ${favorites.has(t.id)?'selected':''}" data-favorite="${t.id}" aria-pressed="${favorites.has(t.id)}" aria-label="${favorites.has(t.id)?'取消收藏':'收藏'} ${esc(t.name)}">${favorites.has(t.id)?'★':'☆'}</button></div><h3>${esc(t.name)}</h3><p>${esc(t.description)}</p><div class="card-state ${t.state}"><i></i>${esc(t.status)}<span class="kind">${esc(t.kind)}</span></div><div class="card-actions"><button class="launch" data-open="${t.id}" ${busy.has(t.id)||!t.available?'disabled':''}>${label(t)}<span>↗</span></button><button class="detail-button" data-detail="${t.id}" aria-label="${esc(t.name)} 的详情">详情</button></div></article>`).join('');
 $('#empty').hidden=visible.length>0;
 $('#quick-tools').innerHTML=[...tools.filter(t=>favorites.has(t.id)),...tools.filter(t=>!favorites.has(t.id))].slice(0,3).map(t=>t.id).map(id=>{const t=tools.find(t=>t.id===id);return t?`<button class="quick-item" data-open="${id}" ${busy.has(id)||!t.available?'disabled':''}>${svg(t.icon)}<span>${esc(t.name)}<small>${busy.has(id)?'正在打开…':esc(t.kind)}</small></span><span class="arrow">↗</span></button>`:''}).join('');
}
async function refresh(quiet=false){
 if($('#refresh').disabled)return;
 $('#refresh').disabled=true;
 try{const r=await fetch('/api/tools');const data=await r.json();if(!r.ok)throw Error(data.error||'连接未完成');tools=data.tools;render();$('#status-summary').textContent=tools.length?`${tools.filter(t=>t.available).length} 个可用`:'还没有工具，点击「添加工具」创建第一个入口。';$('#checked').textContent=`状态检查于 ${data.checkedAt}`;if(!quiet)toast(data.warning||'已更新本地入口状态。',Boolean(data.warning));}
 catch(e){$('#status-summary').textContent=e.message||'无法连接工作台，请重新运行启动程序。';if(!quiet)toast('连接中断，请重新打开本地工作台。',true);}
 finally{$('#refresh').disabled=false;}
}
function details(id){
 const t=tools.find(t=>t.id===id);if(!t)return;detailId=id;
 $('#detail-content').innerHTML=`<div class="tool-icon">${svg(t.icon)}</div><h2>${esc(t.name)}</h2><div class="detail-status">${esc(t.kind)} · ${esc(t.status)}</div><p>${esc(t.note)}</p><h4>${t.path?'本机位置':'网页地址'}</h4><code class="path-box">${esc(t.path||t.url)}</code><div class="dialog-actions"><button class="primary" data-open="${id}" ${busy.has(id)||!t.available?'disabled':''}>${label(t)}</button><button class="secondary" data-action="folder" data-id="${id}">打开所在目录</button><button class="secondary" data-edit="${id}">编辑入口</button><button class="secondary danger" data-remove="${id}">移除入口</button></div>`;
 if(t.managed){$('#detail-content [data-edit]')?.remove();$('#detail-content [data-remove]')?.remove();}
 if(t.managed&&t.id==='hyperframes')$('#detail-content .dialog-actions').insertAdjacentHTML('beforeend','<button class="secondary" data-action="studio" data-id="hyperframes">进入已有 Studio</button>');
 if(t.prompt)$('#detail-content .path-box').insertAdjacentHTML('afterend',`<p>${esc(t.prompt)}</p>`);
 if(t.extra&&t.url)$('#detail-content [data-action=folder]')?.remove();
 if(!$('#detail').open)$('#detail').showModal();
}
async function perform(id,action='open'){
 const t=id==='workbench'?{}:tools.find(t=>t.id===id);if(!t||busy.has(id))return;
 if(t.kind==='CLI / MCP'&&action==='open'){details(id);return;}
 busy.add(id);render();if($('#detail').open&&detailId===id)details(id);
 try{const r=await fetch('/api/action',{method:'POST',headers:{'Content-Type':'application/json','X-Workbench':'1'},body:JSON.stringify({id,action})});const data=await r.json();if(!r.ok)throw Error(data.error||'操作未完成');toast(data.message);}
 catch(e){toast(e.message||'无法连接本机工作台。',true);}
 finally{busy.delete(id);await refresh(true);if($('#detail').open&&detailId===id)details(id);}
}
document.addEventListener('click',async e=>{
 const b=e.target.closest('button');if(!b)return;
 if(b.dataset.category){category=b.dataset.category;render();document.querySelector(`[data-category="${category}"]`)?.focus();}
 if(b.dataset.kind){kind=b.dataset.kind;render();document.querySelector(`[data-kind="${kind}"]`)?.focus();}
 if(b.dataset.open)perform(b.dataset.open);
 if(b.dataset.detail)details(b.dataset.detail);
 if(b.dataset.action)perform(b.dataset.id,b.dataset.action);
 if(b.dataset.favorite){const id=b.dataset.favorite;favorites.has(id)?favorites.delete(id):favorites.add(id);try{localStorage.setItem('workbench-favorites',JSON.stringify([...favorites]));}catch{toast('当前浏览器无法保存收藏。',true);}render();document.querySelector(`[data-favorite="${id}"]`)?.focus();}
});
$('#search').addEventListener('input',render);$('#refresh').onclick=()=>refresh();$('#favorite-filter').onclick=()=>{favoritesOnly=!favoritesOnly;render();};$('#clear').onclick=()=>{category='全部工具';kind='全部形态';favoritesOnly=false;$('#search').value='';render();};$('#close-detail').onclick=()=>$('#detail').close();
$('#about').onclick=()=>{detailId=null;$('#detail-content').innerHTML='<h2>你的工具，一个入口。</h2><p>应用、网页和项目目录集中管理，原文件保留在原处。</p><p>数据只保存在运行工作台的电脑上。收藏保存在当前浏览器；本地服务链接需要对应服务已经运行。</p><p>关闭网页不会停止工作台。在启动终端按 Ctrl+C 可停止。</p>';$('#detail').showModal();};
function editor(id){
 detailId=null;const t=tools.find(t=>t.id===id)||{id:crypto.randomUUID(),name:'',category:'日常工具',type:'url',target:'',description:''};
 $('#detail-content').innerHTML=`<h2>${id?'编辑入口':'添加你的工具'}</h2><form id="tool-form"><div id="form-error" role="alert" tabindex="-1" hidden></div><label>工具名称<input name="name" required maxlength="40" value="${esc(t.name)}" placeholder="例如：我的笔记"></label><div class="form-row"><label>类型<select name="type">${[['url','网页 / 本地服务链接'],['app','macOS 应用'],['folder','项目目录']].map(([v,l])=>`<option value="${v}" ${t.type===v?'selected':''}>${l}</option>`).join('')}</select></label><label>分类<select name="category">${categories.slice(1).map(([c])=>`<option ${t.category===c?'selected':''}>${c}</option>`).join('')}</select></label></div><label>网址或绝对路径<input name="target" required maxlength="2048" value="${esc(t.target)}" placeholder="https://example.com 或 ~/Documents/MyProject" aria-describedby="target-help"></label><p id="target-help" class="field-help">网页使用 HTTPS 或本机 HTTP 地址，不含查询参数与片段；应用填写 .app 路径。目录支持 ~/。</p><label>一句话说明<textarea name="description" maxlength="200" rows="2">${esc(t.description)}</textarea></label><div class="dialog-actions"><button class="primary" type="submit">保存入口</button><button class="secondary" type="button" id="cancel-edit">取消</button></div></form>`;
 if(!$('#detail').open)$('#detail').showModal();
 $('#cancel-edit').onclick=()=>$('#detail').close();
 $('#tool-form').onsubmit=async e=>{e.preventDefault();const button=e.submitter;button.disabled=true;const body=Object.fromEntries(new FormData(e.target));body.id=t.id;
 try{await mutate('/api/tools',body);$('#detail').close();await refresh(true);toast('入口已保存。');}
 catch(error){const el=$('#form-error');el.textContent=error.message;el.hidden=false;el.focus();}
 finally{button.disabled=false;}};
 $('#tool-form input').focus();
}
async function mutate(path,body){const r=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json','X-Workbench':'1'},body:JSON.stringify(body)});const data=await r.json();if(!r.ok)throw Error(data.error||'保存失败');return data;}
$('#add-tool').onclick=()=>editor();
document.addEventListener('click',async e=>{const b=e.target.closest('button');if(!b)return;if(b.dataset.edit)editor(b.dataset.edit);if(b.dataset.remove){const t=tools.find(t=>t.id===b.dataset.remove);$('#detail-content').innerHTML=`<h2>移除 ${esc(t.name)}？</h2><p>只移除工作台入口，原应用和文件仍会保留。</p><div class="dialog-actions"><button class="primary" id="confirm-remove">移除入口</button><button class="secondary" id="cancel-remove">取消</button></div>`;$('#cancel-remove').onclick=()=>details(t.id);$('#confirm-remove').onclick=async()=>{try{await mutate('/api/delete',{id:t.id});$('#detail').close();await refresh(true);toast('入口已移除。');}catch(error){toast(error.message,true);}};}});
document.addEventListener('keydown',e=>{if(e.key==='/'&&!['INPUT','TEXTAREA'].includes(document.activeElement.tagName)&&!$('#detail').open){e.preventDefault();$('#search').focus();}});
refresh(true);

$('#downloads').onclick=()=>{detailId=null;const base='https://github.com/Tyler9169/local-workbench/releases/download/v2.2.0/';$('#detail-content').innerHTML=`<h2>下载安装包</h2><p>适用于 Apple Silicon Mac。</p><div class="download-list">${[['本地工作台','内置运行环境 · macOS 14+','LocalWorkbench-2.2.0-macOS-arm64.dmg'],['照片置顶','图片悬浮、锁定与缩放 · macOS 12+','PhotoPin-1.0-macOS-arm64.dmg'],['框录','区域截图、录屏与声音开关 · macOS 15+','FrameRecorder-1.1-macOS-arm64.dmg']].map(([name,note,file])=>`<a href="${base+file}" target="_blank" rel="noopener noreferrer"><span><strong>${name}</strong><small>${note}</small></span><span>下载 ↓</span></a>`).join('')}</div><p class="field-help">未签名公证的测试版。首次打开可能需要在系统设置中允许；框录还需要屏幕录制和麦克风授权。</p><p><a href="https://github.com/Tyler9169/local-workbench/releases/tag/v2.2.0" target="_blank" rel="noopener noreferrer">安装说明与校验值 ↗</a></p>`;$('#detail').showModal();};

setInterval(()=>{if(!document.hidden&&!$('#detail').open&&!$('#updates').open&&busy.size===0)refresh(true);},10000);
document.addEventListener('visibilitychange',()=>{if(!document.hidden&&!$('#detail').open&&!$('#updates').open&&busy.size===0)refresh(true);});

let updateTarget=null, updatePoll=null, updateDeadline=0;
const updateActive=new Set(['checking','downloading','verifying','backing_up','installing','restarting']);
function updateView(s){
 $('#update-version').textContent=`当前版本 ${s.current}${s.latest?' · 最新版本 '+s.latest:''}${s.prerelease?'（测试版）':''}`;
 $('#update-message').textContent=s.message;
 $('#retry-update').disabled=updateActive.has(s.phase);
 $('#install-update').hidden=!s.available;
 $('#install-update').disabled=updateActive.has(s.phase);
 $('#install-update').dataset.version=s.latest||'';
 $('#update-release').hidden=!s.releaseUrl;
 if(s.releaseUrl)$('#update-release').href=s.releaseUrl;
}
async function checkUpdate(){
 $('#retry-update').disabled=true;$('#install-update').hidden=true;
 $('#update-message').textContent='正在检查 GitHub 更新…';
 try{updateView(await mutate('/api/update/check',{}));}
 catch(e){$('#update-message').textContent=e.message;$('#retry-update').disabled=false;}
}
$('#check-update').onclick=async()=>{if(!$('#updates').open)$('#updates').showModal();await checkUpdate();};
$('#retry-update').onclick=checkUpdate;
$('#close-updates').onclick=()=>$('#updates').close();
$('#install-update').onclick=async()=>{
 const version=$('#install-update').dataset.version;
 $('#install-update').disabled=true;
 try{
  const s=await mutate('/api/update/install',{version,favorites:[...favorites]});updateView(s);
  updateTarget=version;updateDeadline=Date.now()+180000;clearTimeout(updatePoll);pollUpdate();
 }catch(e){$('#update-message').textContent=e.message;$('#install-update').disabled=false;}
};
async function pollUpdate(){
 try{
  const r=await fetch('/api/update/status');if(!r.ok)throw Error('connection');const s=await r.json();
  if(s.current===updateTarget){$('#update-message').textContent='更新完成，正在载入新版…';location.reload();return;}
  updateView(s);
  if(s.phase==='error'){updateTarget=null;return;}
 }catch{ $('#update-message').textContent='正在重新连接工作台…'; }
 if(Date.now()>updateDeadline){$('#update-message').textContent='连接等待超时。请重新打开工作台；工具和配置仍保存在原处。';$('#retry-update').disabled=false;return;}
 updatePoll=setTimeout(pollUpdate,1000);
}
