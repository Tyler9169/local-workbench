export function colorsAt(ratio){const t=Math.max(0,Math.min(1,(.2-ratio)/.15));const mix=(a,b)=>a.map((x,i)=>Math.round(x+(b[i]-x)*t));return {text:mix([255,255,255],[255,83,76]),border:mix([245,156,70],[255,83,76]),t};}
export function clampBounds(bounds,areas){
 let area=areas.find(a=>bounds.x+ bounds.width/2>=a.x&&bounds.x+bounds.width/2<a.x+a.width&&bounds.y+bounds.height/2>=a.y&&bounds.y+bounds.height/2<a.y+a.height);
 if(!area)area=areas.reduce((best,a)=>{const d=Math.hypot(bounds.x-a.x,bounds.y-a.y);return !best||d<best.d?{a,d}:best;},null)?.a;
 if(!area)return bounds;return {...bounds,x:Math.round(Math.max(area.x,Math.min(bounds.x,area.x+area.width-bounds.width))),y:Math.round(Math.max(area.y,Math.min(bounds.y,area.y+area.height-bounds.height)))};
}
