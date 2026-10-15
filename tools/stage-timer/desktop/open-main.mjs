import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
const execFileAsync=promisify(execFile);

// Pass the URL as an argument, never interpolate it into executable script text.
export const reuseTabScript = `function run(args) {
  var browser = Application(args[0]);
  if (!browser.running()) return 'missing';
  var wanted = args[1].replace(/\\/$/, '');
  var windows = browser.windows();
  for (var w = 0; w < windows.length; w++) {
    var tabs = windows[w].tabs();
    for (var t = 0; t < tabs.length; t++) {
      var url = tabs[t].url();
      if (url && url.split(/[?#]/)[0].replace(/\\/$/, '') === wanted) {
        if (args[2] === 'safari') windows[w].currentTab = tabs[t];
        else windows[w].activeTabIndex = t + 1;
        windows[w].index = 1;
        browser.activate();
        return 'found';
      }
    }
  }
  return 'missing';
}`;

export async function openMain({origin,app,shell,platform=process.platform,run=execFileAsync}) {
  if (platform === 'darwin') {
    const name = app.getApplicationNameForProtocol(origin);
    const supported = /^(Google Chrome|Microsoft Edge|Brave Browser|Chromium|Safari)$/;
    if (supported.test(name)) {
      // On a denied automation request, fail visibly instead of opening duplicates.
      const {stdout} = await run('/usr/bin/osascript', ['-l','JavaScript','-e',reuseTabScript,name,origin,name==='Safari'?'safari':'chromium'], {timeout:15000,maxBuffer:16384});
      if (stdout.trim() === 'found') return;
      if (stdout.trim() !== 'missing') throw new Error('无法确认主界面是否已打开');
    }
  }
  await shell.openExternal(origin+'/');
}
