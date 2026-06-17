// ═══════════════════════════════════════════
// GOOGLE DRIVE MODULE — AUTO-SYNC
// ═══════════════════════════════════════════
const GDRIVE_CLIENT_ID = '482797257764-v9q65p2eqrtdjjjv0kb3ki629099ik76.apps.googleusercontent.com';
const GDRIVE_SCOPES = 'https://www.googleapis.com/auth/drive.file';
const GDRIVE_FILE_NAME = 'logicair-data.json';
let gdriveToken = null;
let gdriveFileId = null;
let gdriveSyncTimeout = null;
let gdriveTokenClient = null;
let gdriveSyncInterval = null;

function gdriveLogin() {
  if(typeof google === 'undefined'){toast('⏳ Google en cours de chargement, réessayez...');return;}
  gdriveTokenClient = google.accounts.oauth2.initTokenClient({
    client_id: GDRIVE_CLIENT_ID,
    scope: GDRIVE_SCOPES,
    callback: async (resp) => {
      if (resp.error){toast('Erreur: '+resp.error);return;}
      gdriveToken = resp.access_token;
      const expiry = Date.now() + ((resp.expires_in || 3600) - 60) * 1000;
      localStorage.setItem('gdrive_token', gdriveToken);
      localStorage.setItem('gdrive_token_expiry', expiry);
      gdriveUpdateUI(true);
      toast('✅ Google Drive connecté!');
      await gdriveLoad();
      gdriveStartAutoSync();
    }
  });
  gdriveTokenClient.requestAccessToken();
}

async function gdriveRefreshToken() {
  return new Promise((resolve) => {
    if(typeof google === 'undefined') { resolve(false); return; }
    if(!gdriveTokenClient) {
      gdriveTokenClient = google.accounts.oauth2.initTokenClient({
        client_id: GDRIVE_CLIENT_ID,
        scope: GDRIVE_SCOPES,
        prompt: '',
        callback: (resp) => {
          if(resp.error) { resolve(false); return; }
          gdriveToken = resp.access_token;
          const expiry = Date.now() + ((resp.expires_in || 3600) - 60) * 1000;
          localStorage.setItem('gdrive_token', gdriveToken);
          localStorage.setItem('gdrive_token_expiry', expiry);
          resolve(true);
        }
      });
    } else {
      gdriveTokenClient.callback = (resp) => {
        if(resp.error) { resolve(false); return; }
        gdriveToken = resp.access_token;
        const expiry = Date.now() + ((resp.expires_in || 3600) - 60) * 1000;
        localStorage.setItem('gdrive_token', gdriveToken);
        localStorage.setItem('gdrive_token_expiry', expiry);
        resolve(true);
      };
    }
    gdriveTokenClient.requestAccessToken({prompt: ''});
  });
}

async function gdriveEnsureToken() {
  const expiry = parseInt(localStorage.getItem('gdrive_token_expiry') || '0');
  if(!gdriveToken || Date.now() > expiry) {
    const ok = await gdriveRefreshToken();
    if(!ok) return false;
  }
  return true;
}

function gdriveLogout() {
  gdriveToken = null;
  gdriveFileId = null;
  localStorage.removeItem('gdrive_token');
  localStorage.removeItem('gdrive_token_expiry');
  if(gdriveSyncInterval) { clearInterval(gdriveSyncInterval); gdriveSyncInterval = null; }
  gdriveUpdateUI(false);
  toast('Google Drive déconnecté');
}

function gdriveUpdateUI(connected) {
  const btn = document.getElementById('gdrive-btn');
  const logout = document.getElementById('gdrive-logout-btn');
  const status = document.getElementById('gdrive-status');
  if(!btn) return;
  if(connected) {
    btn.style.display = 'none';
    logout.style.display = 'inline-block';
    status.textContent = '☁️ Connecté';
  } else {
    btn.style.display = 'inline-block';
    logout.style.display = 'none';
    status.textContent = '';
  }
}

async function gdriveFindFile() {
  const r = await fetch(`https://www.googleapis.com/drive/v3/files?q=name='${GDRIVE_FILE_NAME}' and trashed=false&fields=files(id)`, {
    headers: { Authorization: 'Bearer ' + gdriveToken }
  });
  const d = await r.json();
  return d.files && d.files.length > 0 ? d.files[0].id : null;
}

async function gdriveLoad() {
  if(!gdriveToken) return;
  try {
    document.getElementById('gdrive-status').textContent = '☁️ Chargement...';
    const fileId = await gdriveFindFile();
    if(!fileId) { gdriveSync(); return; }
    gdriveFileId = fileId;
    const r = await fetch(`https://www.googleapis.com/drive/v3/files/${fileId}?alt=media`, {
      headers: { Authorization: 'Bearer ' + gdriveToken }
    });
    const d = await r.json();
    if(d.prod) localStorage.setItem('mro_prod_v2', d.prod);
    if(d.entries) localStorage.setItem('logicair_entries', d.entries);
    if(d.techs) localStorage.setItem('logicair_techs', d.techs);
    if(d.estimes) localStorage.setItem('logicair_estimes', d.estimes);
    if(d.pwd) localStorage.setItem('logicair_pwd', d.pwd);
    if(d.pauses) localStorage.setItem('logicair_pauses', d.pauses);
    if(d.punches) localStorage.setItem('logicair_punches', d.punches);
    document.getElementById('gdrive-status').textContent = '☁️ Connecté ✓';
    if(!sessionStorage.getItem('gdrive_loaded')) {
      sessionStorage.setItem('gdrive_loaded', '1');
      toast('✅ Drive synchronisé!');
      setTimeout(() => location.reload(), 1200);
    } else {
      toast('☁️ Drive OK');
    }
  } catch(e) {
    document.getElementById('gdrive-status').textContent = '☁️ Erreur';
    console.error(e);
  }
}

async function gdriveSync() {
  if(!gdriveToken) return;
  clearTimeout(gdriveSyncTimeout);
  gdriveSyncTimeout = setTimeout(async () => {
    const ok = await gdriveEnsureToken();
    if(!ok) { console.warn('GDrive: token invalide'); return; }
    try {
      const data = JSON.stringify({
        version: 2,
        date: new Date().toISOString(),
        prod: localStorage.getItem('mro_prod_v2'),
        entries: localStorage.getItem('logicair_entries'),
        techs: localStorage.getItem('logicair_techs'),
        estimes: localStorage.getItem('logicair_estimes'),
        pwd: localStorage.getItem('logicair_pwd'),
        pauses: localStorage.getItem('logicair_pauses'),
        punches: localStorage.getItem('logicair_punches')
      });
      if(!gdriveFileId) gdriveFileId = await gdriveFindFile();
      if(gdriveFileId) {
        await fetch(`https://www.googleapis.com/upload/drive/v3/files/${gdriveFileId}?uploadType=media`, {
          method: 'PATCH',
          headers: { Authorization: 'Bearer ' + gdriveToken, 'Content-Type': 'application/json' },
          body: data
        });
      } else {
        const form = new FormData();
        form.append('metadata', new Blob([JSON.stringify({ name: GDRIVE_FILE_NAME })], { type: 'application/json' }));
        form.append('file', new Blob([data], { type: 'application/json' }));
        const r = await fetch('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id', {
          method: 'POST',
          headers: { Authorization: 'Bearer ' + gdriveToken },
          body: form
        });
        const created = await r.json();
        gdriveFileId = created.id;
      }
      const t = new Date().toLocaleTimeString('fr-CA', { hour: '2-digit', minute: '2-digit' });
      const s = document.getElementById('gdrive-status');
      if(s) s.textContent = '☁️ Sauvegardé ' + t;
    } catch(e) {
      console.error('GDrive sync:', e);
    }
  }, 2000);
}

function gdriveStartAutoSync() {
  if(gdriveSyncInterval) clearInterval(gdriveSyncInterval);
  gdriveSyncInterval = setInterval(async () => {
    if(!gdriveToken) return;
    const s = document.getElementById('gdrive-status');
    if(s) s.textContent = '☁️ Sync auto...';
    await gdriveSync();
  }, 5 * 60 * 1000);
}

window.addEventListener('load', () => {
  const token = localStorage.getItem('gdrive_token');
  const expiry = parseInt(localStorage.getItem('gdrive_token_expiry') || '0');
  if(token && Date.now() < expiry) {
    gdriveToken = token;
    gdriveUpdateUI(true);
    gdriveLoad();
    gdriveStartAutoSync();
  } else if(token) {
    gdriveToken = token;
    gdriveUpdateUI(true);
    setTimeout(async () => {
      const ok = await gdriveEnsureToken();
      if(ok) { gdriveLoad(); gdriveStartAutoSync(); }
      else { gdriveUpdateUI(false); localStorage.removeItem('gdrive_token'); toast('⚠ Drive: reconnectez-vous'); }
    }, 2000);
  }

  const logoDiv = document.querySelector('body > div:first-child');
  if(logoDiv) {
    const brand = document.createElement('span');
    brand.style.cssText = 'font-size:14px;font-weight:800;color:#FFFFFF;letter-spacing:-0.02em;margin-left:2px;';
    brand.innerHTML = 'LOGIC AIR <span style="color:#3A5A7A;font-weight:400;font-size:9px;letter-spacing:0.12em;vertical-align:middle;">AVIONIQUE</span>';
    const img = logoDiv.querySelector('img');
    if(img) img.after(brand);
    const spacer = document.createElement('div');
    spacer.style.flex = '1';
    logoDiv.appendChild(spacer);
    const gdriveStatus = document.getElementById('gdrive-status');
    const gdriveBtn = document.getElementById('gdrive-btn');
    const gdriveLogoutBtn = document.getElementById('gdrive-logout-btn');
    if(gdriveStatus) logoDiv.appendChild(gdriveStatus);
    if(gdriveBtn) logoDiv.appendChild(gdriveBtn);
    if(gdriveLogoutBtn) logoDiv.appendChild(gdriveLogoutBtn);
    const subtitle = logoDiv.querySelector('div');
    if(subtitle) subtitle.style.display = 'none';
  }

  const notice = document.querySelector('.notice');
  if(notice) {
    const span = notice.querySelector('span:first-child');
    if(span) span.style.display = 'none';
    const driveDiv = notice.querySelector('div');
    if(driveDiv) driveDiv.style.display = 'none';
    notice.style.height = '1px';
    notice.style.padding = '0';
    notice.style.overflow = 'hidden';
  }
});
