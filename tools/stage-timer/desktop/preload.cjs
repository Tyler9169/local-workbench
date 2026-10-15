const {contextBridge,ipcRenderer}=require('electron');
contextBridge.exposeInMainWorld('overlay',{
 onState:callback=>ipcRenderer.on('state',(_,value)=>callback(value)),
 onNotice:callback=>ipcRenderer.on('notice',(_,value)=>callback(value)),
 controls:rects=>ipcRenderer.send('controls',rects),
 ready:()=>ipcRenderer.send('ready'),
 lock:()=>ipcRenderer.invoke('lock'),
 soundBytes:url=>ipcRenderer.invoke('sound-bytes',url),
 openMain:()=>ipcRenderer.invoke('open-main'),
 hover:value=>ipcRenderer.send('hover',value),
 dragStart:point=>ipcRenderer.send('drag-start',point),
 dragMove:point=>ipcRenderer.send('drag-move',point),
 dragEnd:()=>ipcRenderer.send('drag-end'),
});
