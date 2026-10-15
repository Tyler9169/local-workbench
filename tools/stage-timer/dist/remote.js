// An optional local-service clock. The existing browser-only mode stays available.
export async function api(path,data){const response=await fetch('/api/'+path,data===undefined?{cache:'no-store'}:{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});const value=await response.json();if(!response.ok)throw Error(value.error||'本地服务请求失败');return value;}
