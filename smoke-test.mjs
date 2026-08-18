import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('./frontend/', import.meta.url));
const read = file => readFileSync(join(root, file), 'utf8');
const app = read('app.js');
const html = read('index.html');
const styles = read('styles.css');
const serviceWorker = read('sw.js');
const manifest = JSON.parse(read('manifest.webmanifest'));
const vercelConfig = read('vercel.json');
const failures = [];
const check = (condition, message) => { if (!condition) failures.push(message); };

for (const file of ['index.html', 'app.js', 'styles.css', 'desktop.css', 'sw.js', 'manifest.webmanifest', 'config.example.js']) {
  check(existsSync(join(root, file)), `Missing frontend file: ${file}`);
}

const assetList = serviceWorker.match(/const ASSETS=\[([^\]]+)\]/)?.[1] || '';
const cachedAssets = [...assetList.matchAll(/['"](\/[^'"]+)['"]/g)].map(match => match[1]);
for (const asset of cachedAssets) {
  if (asset === '/') continue;
  check(existsSync(join(root, asset.slice(1))), `Service worker references missing asset: ${asset}`);
}

for (const icon of manifest.icons || []) {
  check(existsSync(join(root, icon.src)), `Manifest references missing icon: ${icon.src}`);
}

const cacheVersion = serviceWorker.match(/austonian-hub-v(\d+)/)?.[1];
const appVersion = html.match(/app\.js\?v=(\d+)/)?.[1];
check(Boolean(cacheVersion) && cacheVersion === appVersion, 'Service-worker and app cache versions differ');
check(html.includes('maximum-scale=1') && html.includes('user-scalable=no'), 'Mobile zoom lock is missing');
check(manifest.display_override?.includes('fullscreen'), 'PWA fullscreen display override is missing');
check(styles.includes('.phone[data-stage="app"]>.bottom-nav{position:fixed!important'), 'Mobile bottom navigation is not fixed to the viewport');
check(styles.includes('padding:calc(env(safe-area-inset-top) + 12px) clamp(16px,4.975vw,20px) calc(100px + env(safe-area-inset-bottom,0px))'), 'Mobile content does not have a single safe-area-aware floating navigation allowance');
check(styles.includes('left:12px!important;right:12px!important;bottom:calc(12px + env(safe-area-inset-bottom,0px))!important'), 'Mobile bottom navigation is not floating above the iOS home indicator');
check(styles.includes('height:76px!important;min-height:76px') && styles.includes('border-radius:24px!important') && styles.includes('padding:10px 4px!important'), 'Mobile bottom navigation does not retain its rounded floating-pill geometry');
check(app.includes('class="id-card figma-id-card"') && styles.includes('aspect-ratio:564/326'), 'Student card does not match the Figma credential proportion');
check(styles.includes('html.install-required .bottom-nav{display:none!important}'), 'Bottom navigation is not hidden by the install gate');
check(app.includes("classList.toggle('install-required',visible)"), 'Install-gate state is not synchronized with the application shell');
check(styles.includes('html.notification-required .bottom-nav{display:none!important}') && app.includes('setNotificationGateVisible'), 'Notification permission flow does not hide mobile navigation');
check(styles.includes('.notification-gate-card{position:relative;z-index:1;width:100%;min-height:100dvh'), 'Notification permission flow is not full-screen on mobile');
check(app.includes('global:{fetch:supabaseFetch}') && app.includes("requestUrl.pathname.startsWith('/auth/v1/')"), 'Supabase Auth does not use the same-origin fetch path');
check(vercelConfig.includes('/supabase-auth/:path*') && vercelConfig.includes('/auth/v1/:path*'), 'Vercel Supabase Auth rewrite is missing');

const actionNames = [...app.matchAll(/data-action="([a-z-]+)"/g)].map(match => match[1]);
const handledActions = new Set(['forgot', 'logout', 'notifications', 'notify', 'details', 'profile', 'language', 'appearance', 'privacy', 'support', 'schedule', 'save', 'like', 'share']);
for (const action of new Set(actionNames)) {
  check(handledActions.has(action), `No smoke-test contract for data-action="${action}"`);
}

for (const required of [
  "data-tab=\"class\"",
  "data-calendar-shift=\"-1\"",
  'data-calendar-day=',
  'data-job-search',
  'data-delete-timetable=',
  'data-delete-content=',
  "supabaseClient.from('timetable')",
  "supabaseClient.from('content_items')",
  "supabaseClient.from('profiles')",
  "supabaseClient.storage.from('avatars')",
  "supabaseClient.rpc('claim_otp_request'",
  "supabaseClient.rpc('set_student_academic_group'",
  "supabaseClient.rpc('bulk_assign_academic_groups'",
  "supabaseClient.rpc('promote_academic_group'",
  "table:'timetable'",
  "table:'content_items'",
  "table:'profiles'",
  "table:'academic_assignments'"
]) check(app.includes(required), `Missing wiring contract: ${required}`);

if (failures.length) {
  console.error(`Smoke test failed (${failures.length})`);
  failures.forEach(failure => console.error(`- ${failure}`));
  process.exit(1);
}

console.log(`Smoke test passed: ${new Set(actionNames).size} UI actions, ${cachedAssets.length - 1} cached routes/assets, Supabase data/RPC/realtime wiring, and PWA metadata.`);
