// ===== 状态 =====
const S = {
  view: 'loading', tab: 'home', sub: null,
  videos: [], audiobooks: [], progress: {}, rules: {dailyLimitMin:null,allowedStart:null,allowedEnd:null},
  todayWatchedSec: 0, weekWatchedSec: 0, loadError: null,
  favorites: JSON.parse(localStorage.getItem('cv.favorites')||'[]'),
};
const root = () => document.getElementById('app');
const esc = s => (s||'').replace(/[&<>"]/g, c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const clock = s => { s=Math.max(0,Math.floor(s||0)); return Math.floor(s/60)+':'+String(s%60).padStart(2,'0') };
const runtime = s => Math.round(s/60)+' 分钟';

// ===== 派生 =====
function groupBy(key){ const order=[],map={};
  for(const v of S.videos){ const k=v[key]||(key==='series'?'未分组':'未分类'); if(!map[k]){order.push(k);map[k]=[]} map[k].push(v); }
  return order.map(k=>({id:k,title:k,videos:map[k]})); }
const seriesGroups = () => groupBy('series');
const categoryGroups = () => groupBy('category');
const continueWatching = () => S.videos.filter(v=>{const p=S.progress[v.id]||0;return p>5&&p<v.durationSec-5});
const favoriteVideos = () => S.videos.filter(v=>S.favorites.includes(v.id));
const isFav = v => S.favorites.includes(v.id);
function toggleFav(v){ const i=S.favorites.indexOf(v.id); if(i>=0)S.favorites.splice(i,1); else S.favorites.push(v.id);
  localStorage.setItem('cv.favorites',JSON.stringify(S.favorites)); }
function epList(v){ const g=seriesGroups().find(g=>g.id===(v.series||'未分组')); return g?g.videos:[v]; }
function epIndex(v){ return epList(v).indexOf(v); }
function nextEp(v){ const l=epList(v),i=l.indexOf(v); return i>=0&&i+1<l.length?l[i+1]:null; }
function prevEp(v){ const l=epList(v),i=l.indexOf(v); return i>0?l[i-1]:null; }
function remainingMin(){ return S.rules.dailyLimitMin==null?null:Math.max(0,S.rules.dailyLimitMin-Math.floor(S.todayWatchedSec/60)); }
function currentBlock(){ const r=S.rules;
  if(r.allowedStart!=null&&r.allowedEnd!=null){const m=API.minuteOfDay();
    const inw=r.allowedStart<=r.allowedEnd?(m>=r.allowedStart&&m<r.allowedEnd):(m>=r.allowedStart||m<r.allowedEnd);
    if(!inw)return 'hours';}
  if(r.dailyLimitMin!=null&&S.todayWatchedSec>=r.dailyLimitMin*60)return 'limit';
  return null; }
// 听书只受「时段」管控（睡前不放），不计入每日观看上限（护眼初衷：鼓励听、少看屏）。
function hoursBlock(){ const r=S.rules;
  if(r.allowedStart!=null&&r.allowedEnd!=null){const m=API.minuteOfDay();
    const inw=r.allowedStart<=r.allowedEnd?(m>=r.allowedStart&&m<r.allowedEnd):(m>=r.allowedStart||m<r.allowedEnd);
    if(!inw)return 'hours';}
  return null; }
function catIcon(n){ n=n||'';
  if(/科学|自然/.test(n))return'🔬'; if(/动物/.test(n))return'🐾'; if(/英语|english/i.test(n))return'🔤';
  if(/数/.test(n))return'🔢'; if(/国学|古诗|语文/.test(n))return'📖'; if(/艺术|画|音乐/.test(n))return'🎨';
  if(/历史/.test(n))return'🏛️'; if(/安全/.test(n))return'🛡️'; return'📚'; }
function catColor(n){ let h=2166136261; for(const c of (n||'')) h=(h^c.charCodeAt(0))*16777619>>>0; return `hsl(${h%360} 50% 55%)`; }

// ===== 数据 =====
async function reload(){
  try{
    const [lib,prog] = await Promise.all([API.library(), API.progress()]);
    S.videos = lib.videos||[]; S.audiobooks = lib.audiobooks||[]; S.progress = prog.progress||{}; S.rules = prog.rules||S.rules;
    S.todayWatchedSec = prog.watchedSec||0; S.weekWatchedSec = prog.weekSec||0; S.loadError=null;
  }catch(e){ if(e.message==='unauthorized'){ S.view='activation'; render(); return; } S.loadError=e.message; }
}

// ===== 渲染 =====
function render(){
  const el = root();
  if(S.view==='loading'){ el.innerHTML=`<div class="center"><div style="color:var(--muted)">加载中…</div></div>`; return; }
  if(S.view==='activation'){ el.innerHTML=activationHTML(); bindActivation(); return; }
  if(S.view==='player'){ return; }
  el.innerHTML = `<div class="tabs">${['home','category','listen','mine'].map(t=>`<button data-tab="${t}" class="${S.tab===t?'on':''}">${({home:'首页',category:'分类',listen:'听书',mine:'我的'})[t]}</button>`).join('')}</div>
    <div class="screen" id="screen">${screenHTML()}</div>`;
  bindMain();
}
function rerenderScreen(){ const s=document.getElementById('screen'); if(s){s.innerHTML=screenHTML(); bindScreen();} }
function screenHTML(){
  if(S.tab==='home') return homeHTML();
  if(S.tab==='category') return S.sub?.type==='series'?seriesDetailHTML(S.sub.name):S.sub?.type==='category'?catDetailHTML(S.sub.id):categoryHTML();
  if(S.tab==='listen') return S.sub?.type==='book'?bookDetailHTML(S.sub.id):listenHTML();
  if(S.tab==='mine') return mineHTML();
  return '';
}

// ===== 激活 =====
function activationHTML(){
  return `<div class="center"><div class="pin-card">
    <div class="lock-ring">🔒</div><h2>激活这台设备</h2><p>由家长输入密码，激活后孩子即可观看</p>
    <span class="lbl" style="text-align:left">服务器地址</span>
    <input class="field" id="srv" placeholder="https://你的-worker-域名" value="${esc(API.server)}">
    <span class="lbl" style="text-align:left">设备名称</span>
    <input class="field" id="dev" value="Windows 电脑">
    <input class="field" id="pin" type="password" placeholder="激活密码（家长给的激活密钥）" style="margin-top:14px">
    <div id="aerr" style="color:#E06B6B;font-size:13px;margin-top:10px"></div>
    <button class="primary" id="actbtn" style="margin-top:16px">激活</button></div></div>`;
}
function bindActivation(){
  document.getElementById('actbtn').onclick = async ()=>{
    const srv=document.getElementById('srv').value.trim().replace(/\/$/,''), pin=document.getElementById('pin').value, dev=document.getElementById('dev').value||'Windows';
    const err=document.getElementById('aerr'); err.textContent='';
    if(!srv||!pin){err.textContent='请填服务器地址和密码';return;}
    try{ await API.activate(srv,pin,dev); S.view='main'; S.tab='home'; render(); await reload(); render(); }
    catch(e){ err.textContent=e.message; }
  };
  document.getElementById('pin').addEventListener('keydown',e=>{if(e.key==='Enter')document.getElementById('actbtn').click()});
}

// ===== 首页 =====
function posterHTML(v,big){
  const idx=epIndex(v), ep=idx>=0?`第 ${String(idx+1).padStart(2,'0')} 集`:'';
  const pos=S.progress[v.id]||0, pct=v.durationSec?Math.min(100,pos/v.durationSec*100):0, showbar=pos>5&&pos<v.durationSec-5;
  return `<button class="poster ${big?'big':''}" data-play="${v.id}">
    <div class="art"><img src="${API.mediaUrl(v.posterUrl)}" onerror="this.replaceWith(Object.assign(document.createElement('div'),{className:'ph'}))">
      ${ep?`<span class="ep">${ep}</span>`:''}<span class="at">${esc(big?v.title:(v.series||v.title))}</span>
      <span class="rt">${runtime(v.durationSec)}</span>${showbar?`<span class="pbar"><i style="width:${pct}%"></i></span>`:''}</div>
    <div class="meta"><div class="t">${esc(big?v.title:(v.series||v.title))}</div>
      <div class="s">${esc(big?(v.series||'')+' · 还剩 '+runtime(Math.max(0,v.durationSec-pos)):v.title)}</div></div></button>`;
}
function rowHTML(title,sub,vids,big,seriesId){
  const preview=vids.slice(0,big?12:10), more=seriesId&&vids.length>4;
  return `<div class="section"><div class="sec-head"><h2>${esc(title)}</h2>${sub?`<span class="sub">${esc(sub)}</span>`:''}
    ${more?`<button class="all" data-series="${esc(seriesId)}">全部 ›</button>`:''}</div>
    <div class="rowscroll">${preview.map(v=>posterHTML(v,big)).join('')}
    ${seriesId&&vids.length>(big?12:10)?`<button class="poster" data-series="${esc(seriesId)}"><div class="art" style="display:grid;place-items:center"><div style="text-align:center;color:var(--muted)"><div style="font-size:26px">▦</div>查看全部<br>${vids.length} 集</div></div></button>`:''}</div></div>`;
}
function homeHTML(){
  const h=new Date().getHours(), part=h<11?'早上好':h<18?'下午好':'晚上好', rem=remainingMin(), cats=categoryGroups(), cw=continueWatching(), fav=favoriteVideos();
  let html=`<div class="home-head"><div class="avatar">${esc(API.childName[0])}</div>
    <div class="greet"><h1>${part}，${esc(API.childName)}</h1><p>今天想学点什么呢？</p></div><div class="spacer"></div>
    ${rem!=null?`<span class="pill time-pill ${rem<=10?'low':''}"><span class="dot"></span>今天还可观看 ${rem} 分钟</span>`:''}
    <button class="icon-btn" id="refresh" style="margin-left:12px">⟳</button></div>`;
  if(S.loadError) html+=`<div style="padding:6px 32px;color:var(--warn)">⚠︎ ${esc(S.loadError)}</div>`;
  if(cats.length) html+=`<div class="kong">${cats.map(g=>`<button class="item" data-cat="${esc(g.id)}"><div class="ic" style="background:${catColor(g.id)}33;color:${catColor(g.id)}">${catIcon(g.id)}</div><div class="nm">${esc(g.id)}</div></button>`).join('')}</div>`;
  if(cw.length) html+=rowHTML('继续观看',null,cw,true,null);
  if(fav.length) html+=rowHTML('我喜欢的',null,fav,false,null);
  for(const g of seriesGroups()) html+=rowHTML(g.id,`共 ${g.videos.length} 集`,g.videos,false,g.id);
  if(!S.videos.length&&!S.loadError) html+=`<div class="empty"><div class="big">🎬</div><div>还没有视频</div><div style="font-size:13px;color:var(--faint)">家长上传后这里就会出现</div></div>`;
  return `<div>${html}<div style="height:30px"></div></div>`;
}

// ===== 分类 =====
function categoryHTML(){ const cats=categoryGroups();
  if(!cats.length) return `<div class="empty"><div class="big">▦</div><div>还没有分类</div></div>`;
  return `<div class="cat-grid">${cats.map(g=>`<button class="cat-card" data-cat="${esc(g.id)}">
    <div class="ic" style="background:${catColor(g.id)}33;color:${catColor(g.id)}">${catIcon(g.id)}</div>
    <div><div class="t">${esc(g.id)}</div><div class="c">${g.videos.length} 个视频</div></div>
    <div class="spacer"></div><div style="color:var(--faint)">›</div></button>`).join('')}</div>`; }
function catDetailHTML(id){ const g=categoryGroups().find(g=>g.id===id); if(!g)return categoryHTML();
  const order=[],map={}; for(const v of g.videos){const k=v.series||'单集';if(!map[k]){order.push(k);map[k]=[]}map[k].push(v)}
  return `<div><div class="back-bar"><button class="icon-btn" data-back>‹</button><h2>${esc(id)}</h2></div>
    ${order.map(k=>rowHTML(k,`共 ${map[k].length} 集`,map[k],false,k)).join('')}<div style="height:30px"></div></div>`; }
function seriesDetailHTML(name){ const g=seriesGroups().find(g=>g.id===name); const vids=g?g.videos:[];
  return `<div><div class="back-bar"><button class="icon-btn" data-back>‹</button><h2>${esc(name)} · 共 ${vids.length} 集</h2></div>
    <div class="grid-wrap">${vids.map(v=>posterHTML(v,false)).join('')}</div></div>`; }

// ===== 听书 =====
function bookById(id){ return S.audiobooks.find(b=>b.id===id); }
function bookGroups(){ const order=[],map={};
  for(const b of S.audiobooks){ const k=b.category||'未分类'; if(!map[k]){order.push(k);map[k]=[]} map[k].push(b); }
  return order.map(k=>({id:k,books:map[k]})); }
function abResume(){ try{return JSON.parse(localStorage.getItem('cv.abResume')||'{}')}catch{return{}} }
function setAbResume(bookId,ci,pos){ const m=abResume(); m[bookId]={ci,pos:Math.floor(pos||0)}; localStorage.setItem('cv.abResume',JSON.stringify(m)); }
function bookResume(b){ const r=abResume()[b.id]; if(!r)return null; const ch=(b.chapters||[])[r.ci]; if(!ch)return null; return {ci:r.ci,pos:r.pos,ch}; }
function continueBooks(){ return S.audiobooks.filter(b=>{const r=bookResume(b);return r&&(r.pos>3||r.ci>0)}); }
function bookCover(b){ return b.coverUrl
  ? `<img src="${API.mediaUrl(b.coverUrl)}" onerror="this.replaceWith(Object.assign(document.createElement('div'),{className:'bk-ph',innerHTML:'📖'}))">`
  : `<div class="bk-ph">📖</div>`; }
function bookCardHTML(b){ const r=bookResume(b), n=(b.chapters||[]).length;
  return `<button class="bookcard" data-book="${esc(b.id)}">
    <div class="bk-art" style="background:${catColor(b.category)}22">${bookCover(b)}<span class="bk-badge">🎧 ${n}章</span>
    ${r?`<span class="bk-cont">继续 第${r.ci+1}章</span>`:''}</div>
    <div class="bk-meta"><div class="t">${esc(b.title)}</div><div class="s">${esc(b.author||'听书')} · ${runtime(b.totalDurationSec||0)}</div></div></button>`; }
function bookRowHTML(title,books){ return `<div class="section"><div class="sec-head"><h2>${esc(title)}</h2></div>
  <div class="rowscroll">${books.map(bookCardHTML).join('')}</div></div>`; }
function listenHTML(){
  if(!S.audiobooks.length) return `<div class="empty"><div class="big">🎧</div><div>还没有听书</div>
    <div style="font-size:13px;color:var(--faint)">家长用 cpv audiobook 上传后这里就会出现</div></div>`;
  let html='<div class="listen-head"><h1>🎧 听书</h1><p>闭上眼睛，用耳朵听故事</p></div>';
  const cb=continueBooks(); if(cb.length) html+=bookRowHTML('继续收听',cb);
  for(const g of bookGroups()) html+=`<div class="section"><div class="sec-head"><h2>${esc(g.id)}</h2><span class="sub">${g.books.length} 本</span></div>
    <div class="book-grid">${g.books.map(bookCardHTML).join('')}</div></div>`;
  return `<div>${html}<div style="height:30px"></div></div>`;
}
function bookDetailHTML(id){ const b=bookById(id); if(!b)return listenHTML();
  const r=bookResume(b), chs=b.chapters||[];
  return `<div><div class="back-bar"><button class="icon-btn" data-back>‹</button><h2>${esc(b.title)}</h2></div>
    <div class="book-hero">
      <div class="bk-art lg" style="background:${catColor(b.category)}22">${bookCover(b)}</div>
      <div class="bk-info"><div class="t">${esc(b.title)}</div><div class="a">${esc(b.author||'听书')}</div>
        <div class="d">${esc(b.category||'')} · ${chs.length} 章 · ${runtime(b.totalDurationSec||0)}</div>
        <div class="row-h" style="gap:10px;margin-top:16px">
          <button class="primary" data-book-play="${esc(b.id)}" style="width:auto;padding:12px 28px">${r?`▶ 继续收听 第${r.ci+1}章`:'▶ 开始收听'}</button>
          <button class="pill" data-book-fav="${esc(b.id)}" style="color:${isFav(b)?'var(--pink)':'var(--muted)'}">${isFav(b)?'♥ 已收藏':'♡ 收藏'}</button></div>
      </div></div>
    <div class="ch-list">${chs.map((c,i)=>`<button class="ch-row" data-chapter="${i}" data-cbook="${esc(b.id)}">
      <span class="ci">${String(i+1).padStart(2,'0')}</span>
      <span class="ct">${esc(c.title||'第 '+(i+1)+' 章')}</span>
      <span class="cd">${c.durationSec?clock(c.durationSec):''}</span>
      ${r&&r.ci===i?'<span class="cnow">▶</span>':''}</button>`).join('')}</div>
    <div style="height:30px"></div></div>`;
}

// ===== 我的 =====
let mineUnlocked=false, minePin='';
const ED={lim:60,limOn:false,hr:false,hs:16,he:20};
function syncED(){ const r=S.rules; ED.limOn=r.dailyLimitMin!=null; ED.lim=r.dailyLimitMin||60; ED.hr=r.allowedStart!=null; ED.hs=Math.floor((r.allowedStart??960)/60); ED.he=Math.floor((r.allowedEnd??1200)/60); }
function mineHTML(){ return mineUnlocked?settingsHTML():pinPadHTML(); }
function pinPadHTML(){ return `<div class="center"><div class="pin-card">
  <div class="lock-ring">🔒</div><h2>家长中心</h2><p>输入家长密码进入管理与设置</p>
  <div class="dots">${[0,1,2,3].map(i=>`<i class="${i<minePin.length?'on':''}"></i>`).join('')}</div>
  <div class="keypad">${[1,2,3,4,5,6,7,8,9].map(n=>`<button data-key="${n}">${n}</button>`).join('')}
  <button class="ghost" data-key="x">清空</button><button data-key="0">0</button><button class="ghost" data-key="d">⌫</button></div></div></div>`; }
function settingsHTML(){ const eye=parseInt(localStorage.getItem('cv.eyeCareMin')||'0');
  return `<div class="settings"><div class="row-h"><h2 style="margin:0">家长设置</h2><div class="spacer"></div><button class="pill" data-mlock>锁定</button></div><div style="height:14px"></div>
  <div class="grp">
    <div class="set-row"><div class="k">每日观看上限<small>看满后进入休息页</small></div>
      <div class="seg"><button data-lim="off" class="${!ED.limOn?'on':''}">关</button><button data-lim="on" class="${ED.limOn?'on':''}">开</button></div></div>
    <div class="set-row" style="${ED.limOn?'':'display:none'}"><div class="k">上限时长</div>
      <div class="stepper"><button data-step="lim-">−</button><span class="val" id="limval">${ED.lim} 分钟</span><button data-step="lim+">+</button></div></div></div>
  <div class="grp">
    <div class="set-row"><div class="k">限制观看时段<small>仅在设定时段内可播放</small></div>
      <div class="seg"><button data-hr="off" class="${!ED.hr?'on':''}">关</button><button data-hr="on" class="${ED.hr?'on':''}">开</button></div></div>
    <div class="set-row" style="${ED.hr?'':'display:none'}"><div class="k">时段</div>
      <div class="row-h" style="gap:8px"><div class="stepper"><button data-step="hs-">−</button><span class="val" id="hsval">${ED.hs}:00</span><button data-step="hs+">+</button></div>
      <span>至</span><div class="stepper"><button data-step="he-">−</button><span class="val" id="heval">${ED.he}:00</span><button data-step="he+">+</button></div></div></div></div>
  <div class="grp"><div class="set-row"><div class="k">护眼提醒<small>连续观看到点提醒休息眼睛</small></div>
    <div class="seg">${[[0,'关'],[20,'20'],[30,'30'],[45,'45']].map(([v,l])=>`<button data-eye="${v}" class="${eye===v?'on':''}">${l}</button>`).join('')}</div></div></div>
  <div class="grp"><div class="set-row"><div class="k">学习报告</div>
    <div style="text-align:right"><div style="font-weight:600">今日 ${Math.floor(S.todayWatchedSec/60)} 分钟</div>
    <div style="font-size:12.5px;color:var(--faint)">本周 ${Math.floor(S.weekWatchedSec/60)} 分钟</div></div></div></div>
  <div id="serr" style="color:#E06B6B;font-size:13px;margin:8px 0"></div>
  <button class="primary" data-save>保存设置</button>
  <button style="width:100%;padding:12px;margin-top:8px;color:#E06B6B" data-logout>注销此设备</button></div>`; }

// ===== 绑定 =====
function bindMain(){
  root().querySelectorAll('[data-tab]').forEach(b=>b.onclick=()=>{ S.tab=b.dataset.tab; S.sub=null; if(S.tab==='mine'){mineUnlocked=false;minePin='';} render(); });
  bindScreen();
}
function bindScreen(){
  const el=document.getElementById('screen'); if(!el)return;
  el.querySelectorAll('[data-play]').forEach(b=>b.onclick=()=>{ const v=S.videos.find(x=>x.id===b.dataset.play); if(v)openPlayer(v); });
  el.querySelectorAll('[data-cat]').forEach(b=>b.onclick=()=>{ S.tab='category'; S.sub={type:'category',id:b.dataset.cat}; render(); });
  el.querySelectorAll('[data-series]').forEach(b=>b.onclick=()=>{ if(S.tab!=='category')S.tab='category'; S.sub={type:'series',name:b.dataset.series}; render(); });
  el.querySelectorAll('[data-back]').forEach(b=>b.onclick=()=>{ S.sub=null; render(); });
  el.querySelectorAll('[data-book]').forEach(b=>b.onclick=()=>{ S.tab='listen'; S.sub={type:'book',id:b.dataset.book}; render(); });
  el.querySelectorAll('[data-chapter]').forEach(b=>b.onclick=()=>{ openAudio(b.dataset.cbook, parseInt(b.dataset.chapter)); });
  el.querySelectorAll('[data-book-play]').forEach(b=>b.onclick=()=>{ const bk=bookById(b.dataset.bookPlay), r=bk&&bookResume(bk); openAudio(b.dataset.bookPlay, r?r.ci:0); });
  el.querySelectorAll('[data-book-fav]').forEach(b=>b.onclick=()=>{ const bk=bookById(b.dataset.bookFav); if(bk){toggleFav(bk);rerenderScreen();bindScreen();} });
  const rf=document.getElementById('refresh'); if(rf)rf.onclick=async()=>{ await reload(); rerenderScreen(); };
  el.querySelectorAll('[data-key]').forEach(b=>b.onclick=()=>{ const k=b.dataset.key;
    if(k==='d')minePin=minePin.slice(0,-1); else if(k==='x')minePin=''; else if(minePin.length<4)minePin+=k;
    if(minePin.length===4){ mineUnlocked=true; syncED(); } rerenderScreen(); bindScreen(); });
  bindSettings(el);
}
function bindSettings(el){
  const save=async()=>{ const serr=el.querySelector('#serr'); if(serr)serr.textContent='';
    try{ await API.saveRules(minePin, ED.limOn?ED.lim:null, ED.hr?ED.hs*60:null, ED.hr?ED.he*60:null);
      S.rules={dailyLimitMin:ED.limOn?ED.lim:null,allowedStart:ED.hr?ED.hs*60:null,allowedEnd:ED.hr?ED.he*60:null}; toast('已保存'); }
    catch(e){ if(serr)serr.textContent=e.message; } };
  const q=s=>el.querySelector(s);
  q('[data-save]')&&(q('[data-save]').onclick=save);
  q('[data-mlock]')&&(q('[data-mlock]').onclick=()=>{mineUnlocked=false;minePin='';rerenderScreen();bindScreen();});
  q('[data-logout]')&&(q('[data-logout]').onclick=()=>{API.logout();S.view='activation';render();});
  el.querySelectorAll('[data-lim]').forEach(b=>b.onclick=()=>{ED.limOn=b.dataset.lim==='on';rerenderScreen();bindScreen();});
  el.querySelectorAll('[data-hr]').forEach(b=>b.onclick=()=>{ED.hr=b.dataset.hr==='on';rerenderScreen();bindScreen();});
  el.querySelectorAll('[data-eye]').forEach(b=>b.onclick=()=>{localStorage.setItem('cv.eyeCareMin',b.dataset.eye);rerenderScreen();bindScreen();});
  el.querySelectorAll('[data-step]').forEach(b=>b.onclick=()=>{ const s=b.dataset.step;
    if(s==='lim-')ED.lim=Math.max(15,ED.lim-15); if(s==='lim+')ED.lim=Math.min(180,ED.lim+15);
    if(s==='hs-')ED.hs=Math.max(0,ED.hs-1); if(s==='hs+')ED.hs=Math.min(23,ED.hs+1);
    if(s==='he-')ED.he=Math.max(1,ED.he-1); if(s==='he+')ED.he=Math.min(24,ED.he+1);
    el.querySelector('#limval')&&(el.querySelector('#limval').textContent=ED.lim+' 分钟');
    el.querySelector('#hsval')&&(el.querySelector('#hsval').textContent=ED.hs+':00');
    el.querySelector('#heval')&&(el.querySelector('#heval').textContent=ED.he+':00'); });
}
function toast(msg){ const t=document.createElement('div'); t.className='toast'; t.textContent=msg; document.body.appendChild(t); setTimeout(()=>t.remove(),1600); }

// ===== 播放器 =====
let P=null;
const SPEEDS=[0.75,1,1.25,1.5];
function openPlayer(v){
  const blk=currentBlock(); if(blk){ showBreak(blk); return; }
  S.view='player'; root().innerHTML='';
  const ov=document.createElement('div'); ov.className='player'; ov.id='player'; document.body.appendChild(ov);
  const video=document.createElement('video'); video.src=API.mediaUrl(v.videoUrl); video.autoplay=true; video.setAttribute('playsinline','');
  ov.appendChild(video);
  const startAt=S.progress[v.id]||0;
  P={v,video,ov,startAt,lastReported:startAt,eyeAccum:0,heartbeat:null,hideTimer:null,scrubbing:false,locked:false,ended:false};
  video.addEventListener('loadedmetadata',()=>{ if(startAt>1)video.currentTime=startAt; renderControls(); });
  video.addEventListener('timeupdate',()=>{ if(!P.scrubbing)updateScrub(); });
  video.addEventListener('progress',()=>{ if(!P.scrubbing)updateScrub(); });
  video.addEventListener('play',()=>{renderControls();poke()});
  video.addEventListener('pause',renderControls);
  video.addEventListener('ended',()=>{ P.ended=true; autoNext(); });
  ov.addEventListener('mousemove',()=>{ if(!P.locked)poke(); });
  ov.addEventListener('pointerdown',()=>{ if(!P.locked)poke(); }); // 触屏点一下显隐控件
  renderControls(); poke();
  P.heartbeat=setInterval(reportTick,10000);
}
function renderControls(){
  if(!P)return; const v=P.v, video=P.video, idx=epIndex(v);
  let ov=document.getElementById('plov'); if(ov)ov.remove();
  ov=document.createElement('div'); ov.className='pl-ov'+(P.locked?'':''); ov.id='plov'; P.ov.appendChild(ov);
  if(P.locked){ ov.innerHTML=`<div class="eyecare" id="lockhint" style="background:rgba(0,0,0,.4);display:${P.showLockHint?'grid':'none'}">
    <div><div class="big">🔒</div><h2>已锁定</h2><p>长按下面的按钮解锁</p>
    <button class="cbtn" id="unlock" style="margin:14px auto 0;background:var(--accent);color:var(--on-accent)">🔓</button></div></div>`;
    ov.onclick=flashLock;
    const u=document.getElementById('unlock'); if(u){ let t; u.onmousedown=()=>{t=setTimeout(()=>{P.locked=false;renderControls();poke()},600)}; u.onmouseup=()=>clearTimeout(t); }
    return;
  }
  const nx=nextEp(v), eye=parseInt(localStorage.getItem('cv.eyeCareMin')||'0');
  ov.innerHTML=`
    <div class="pl-top"><button class="icon-btn" id="back" style="background:rgba(255,255,255,.12);border:0;color:#fff">‹</button>
      <div><div class="t">${esc(v.title)}</div>${v.series?`<div class="s">${esc(v.series)}${idx>=0?' · 第 '+(idx+1)+' 集':''}</div>`:''}</div>
      <div class="spacer"></div>
      <button class="icon-btn" id="lock" style="background:rgba(255,255,255,.12);border:0;color:#fff">🔒</button>
      <button class="icon-btn" id="fav" style="background:rgba(255,255,255,.12);border:0;color:${isFav(v)?'var(--pink)':'#fff'};margin-left:10px">${isFav(v)?'♥':'♡'}</button></div>
    <div class="pl-center">${P.ended?`<button class="cbtn" id="replay">↺</button>`:`
      <button class="cbtn sm" id="b10">⟲</button>
      <button class="cbtn" id="pp">${video.paused?'▶':'⏸'}</button>
      <button class="cbtn sm" id="f10">⟳</button>`}</div>
    <div class="pl-bot">
      <div class="scrub"><span class="tm" id="tcur">0:00</span>
        <div class="track" id="track"><div class="buf" id="buf"></div><div class="fill" id="fill"></div><div class="knob" id="knob"></div></div>
        <span class="tm" id="trem" style="text-align:right">0:00</span></div>
      <div class="pl-tools">
        <select class="tool" id="rate" style="background:#1c1f25">${SPEEDS.map(s=>`<option value="${s}" ${video.playbackRate===s?'selected':''}>${s}×</option>`).join('')}</select>
        <button class="tool" id="mute">${video.muted?'🔇':'🔊'}</button>
        <input class="vol" id="vol" type="range" min="0" max="1" step="0.05" value="${video.volume}">
        <div class="spacer"></div>
        ${epList(v).length>1?`<button class="tool" id="eps">选集</button>`:''}
        ${nx?`<button class="tool" id="next">下一集 ⏭</button>`:''}
      </div></div>`;
  ov.querySelector('#back').onclick=closePlayer;
  ov.querySelector('#fav').onclick=()=>{toggleFav(v);renderControls();poke()};
  ov.querySelector('#lock').onclick=()=>{P.locked=true;P.showLockHint=true;renderControls();flashLock()};
  if(P.ended){ ov.querySelector('#replay').onclick=()=>{video.currentTime=0;video.play();P.ended=false;renderControls()}; }
  else{
    ov.querySelector('#pp').onclick=()=>{video.paused?video.play():video.pause();poke()};
    ov.querySelector('#b10').onclick=()=>{video.currentTime=Math.max(0,video.currentTime-10);poke()};
    ov.querySelector('#f10').onclick=()=>{video.currentTime=Math.min(video.duration||1e9,video.currentTime+10);poke()};
  }
  ov.querySelector('#rate').onchange=e=>{video.playbackRate=parseFloat(e.target.value);poke()};
  ov.querySelector('#mute').onclick=()=>{video.muted=!video.muted;renderControls();poke()};
  ov.querySelector('#vol').oninput=e=>{video.volume=parseFloat(e.target.value);video.muted=false;};
  const track=ov.querySelector('#track');
  const seek=e=>{const r=track.getBoundingClientRect();const x=Math.max(0,Math.min(1,(e.clientX-r.left)/r.width));video.currentTime=x*(video.duration||0);updateScrub();};
  track.onpointerdown=e=>{P.scrubbing=true;seek(e);const mv=ev=>seek(ev);const up=()=>{P.scrubbing=false;document.removeEventListener('pointermove',mv);document.removeEventListener('pointerup',up);poke()};document.addEventListener('pointermove',mv);document.addEventListener('pointerup',up);};
  ov.querySelector('#eps')&&(ov.querySelector('#eps').onclick=showEpisodes);
  ov.querySelector('#next')&&(ov.querySelector('#next').onclick=()=>{if(nx)goTo(nx)});
  updateScrub();
}
function updateScrub(){
  if(!P)return; const v=P.video, d=v.duration||0, c=v.currentTime||0;
  const fill=document.getElementById('fill'); if(!fill)return;
  const pct=d?c/d*100:0; fill.style.width=pct+'%';
  const knob=document.getElementById('knob'); if(knob)knob.style.left=pct+'%';
  const buf=document.getElementById('buf'); if(buf&&v.buffered.length)buf.style.width=Math.min(100,v.buffered.end(v.buffered.length-1)/d*100)+'%';
  const tc=document.getElementById('tcur'); if(tc)tc.textContent=clock(c);
  const tr=document.getElementById('trem'); if(tr)tr.textContent='-'+clock(Math.max(0,d-c));
}
function poke(){ if(!P)return; const ov=document.getElementById('plov'); if(ov)ov.classList.remove('hide');
  clearTimeout(P.hideTimer); P.hideTimer=setTimeout(()=>{ const o=document.getElementById('plov'); if(o&&!P.video.paused&&!P.scrubbing&&!P.locked)o.classList.add('hide'); },2800); }
function flashLock(){ P.showLockHint=true; const lh=document.getElementById('lockhint'); if(lh)lh.style.display='grid';
  clearTimeout(P.lockTimer); P.lockTimer=setTimeout(()=>{const l=document.getElementById('lockhint');if(l)l.style.display='none';P.showLockHint=false;},3000); }
function showEpisodes(){
  const v=P.v, list=epList(v);
  const sh=document.createElement('div'); sh.className='breakov'; sh.style.background='rgba(0,0,0,.85)'; sh.style.zIndex='10';
  sh.innerHTML=`<div style="width:520px;max-height:80vh;overflow:auto;text-align:left">
    <div class="row-h" style="padding:0 4px 12px"><h2 style="margin:0">${esc(v.series||'选集')}</h2><div class="spacer"></div><button class="icon-btn" id="epx">✕</button></div>
    ${list.map((e,i)=>`<button data-ep="${e.id}" style="display:flex;gap:12px;width:100%;padding:8px;border-radius:12px;${e.id===v.id?'background:var(--card)':''};align-items:center;text-align:left">
      <img src="${API.mediaUrl(e.posterUrl)}" style="width:96px;height:60px;object-fit:cover;border-radius:8px" onerror="this.style.visibility='hidden'">
      <div><div style="font-size:12px;color:var(--faint)">第 ${i+1} 集</div><div style="font-weight:600;color:${e.id===v.id?'var(--accent-hi)':'#fff'}">${esc(e.title)}</div></div></button>`).join('')}
  </div>`;
  P.ov.appendChild(sh);
  sh.querySelector('#epx').onclick=()=>sh.remove();
  sh.querySelectorAll('[data-ep]').forEach(b=>b.onclick=()=>{const e=list.find(x=>x.id===b.dataset.ep);sh.remove();if(e&&e.id!==v.id)goTo(e);});
}
async function reportTick(){
  if(!P)return; const pos=Math.floor(P.video.currentTime||0), delta=Math.max(0,pos-P.lastReported), eff=P.video.paused?0:delta;
  P.lastReported=pos;
  const eye=parseInt(localStorage.getItem('cv.eyeCareMin')||'0');
  if(eye>0&&!P.video.paused&&!document.getElementById('eyeov')){ P.eyeAccum+=eff; if(P.eyeAccum>=eye*60)triggerEyeCare(); }
  const res=await API.postProgress(P.v.id,pos,eff);
  S.progress[P.v.id]=pos; if(res.watchedSec!=null)S.todayWatchedSec=res.watchedSec;
  if(res.blocked){ const reason=res.blocked==='outside_allowed_hours'?'hours':'limit'; teardownPlayer(); showBreak(reason); }
}
function triggerEyeCare(){
  P.video.pause();
  const e=document.createElement('div'); e.className='eyecare'; e.id='eyeov'; P.ov.appendChild(e);
  let cd=20;
  const paint=()=>{ e.innerHTML=`<div><div class="big">👀</div><h2>看了一会儿啦，休息下眼睛</h2><p>看看远处，眨眨眼，放松一下～</p>
    ${cd>0?`<div class="cd">${cd}</div>`:`<button class="primary" id="eyego" style="width:auto;padding:12px 26px;margin-top:10px">继续观看</button>`}</div>`;
    if(cd<=0){e.querySelector('#eyego').onclick=()=>{e.remove();P.eyeAccum=0;P.video.play();poke()};} };
  paint(); const t=setInterval(()=>{cd--;if(cd<0){clearInterval(t)}else paint()},1000);
}
function showBreak(reason){
  S.view='player'; root().innerHTML='';
  document.getElementById('player')?.remove();
  const ov=document.createElement('div'); ov.className='player'; ov.id='player'; document.body.appendChild(ov);
  const b=document.createElement('div'); b.className='breakov'; ov.appendChild(b);
  const isH=reason==='hours';
  const startMin=S.rules.allowedStart; const cd=isH&&startMin!=null?`${Math.floor(startMin/60)}:00 可以继续观看`:'明天又有新的观看时间';
  b.innerHTML=`<div><div class="cup">☕️</div><h2>${isH?'现在不是观看时间哦':'今天的观看时间到啦'}</h2>
    <p>${isH?'到了约定的时段就可以继续看啦。':'看了很久啦，让眼睛休息一下吧 👀'}</p><p>不如去做点别的：读本书、出去走走、画幅画。</p>
    <div style="color:var(--warn);font-weight:600;margin-top:12px">${cd}</div>
    <button class="primary" id="bback" style="width:auto;padding:12px 26px;margin-top:24px">返回</button></div>`;
  b.querySelector('#bback').onclick=()=>{ ov.remove(); S.view='main'; render(); };
}
function teardownPlayer(){ if(!P)return; clearInterval(P.heartbeat); clearTimeout(P.hideTimer); P.video.pause(); P.ov.remove(); P=null; }
async function closePlayer(){ if(P)await reportTick(); teardownPlayer(); S.view='main'; render(); }
function autoNext(){ const nx=nextEp(P.v); reportTick(); if(nx)goTo(nx); else renderControls(); }
async function goTo(next){ await reportTick(); teardownPlayer(); openPlayer(next); }

// ===== 听书播放器（音频，无画面） =====
let A=null;
function openAudio(bookId, ci){
  const b=bookById(bookId); if(!b)return; const chs=b.chapters||[];
  if(!(ci>=0&&ci<chs.length))ci=0;
  const blk=hoursBlock(); if(blk){ showBreak(blk); return; }
  S.view='player'; root().innerHTML=''; document.getElementById('player')?.remove();
  const ov=document.createElement('div'); ov.className='player audio'; ov.id='player'; document.body.appendChild(ov);
  const audio=document.createElement('audio'); audio.autoplay=true;
  const r=bookResume(b), startAt=(r&&r.ci===ci)?r.pos:0;
  A={b,ci,audio,ov,startAt,lastReported:startAt,heartbeat:null,scrubbing:false};
  audio.src=API.mediaUrl(chs[ci].audioUrl); ov.appendChild(audio);
  audio.addEventListener('loadedmetadata',()=>{ if(startAt>1&&startAt<audio.duration)audio.currentTime=startAt; renderAudio(); });
  audio.addEventListener('timeupdate',()=>{ if(!A.scrubbing)updateAScrub(); });
  audio.addEventListener('play',renderAudio);
  audio.addEventListener('pause',renderAudio);
  audio.addEventListener('ended',audioEnded);
  renderAudio();
  A.heartbeat=setInterval(reportATick,10000);
}
function curChapter(){ return (A.b.chapters||[])[A.ci]; }
function aPrev(){ return A.ci>0?A.ci-1:null; }
function aNext(){ return A.ci+1<(A.b.chapters||[]).length?A.ci+1:null; }
function renderAudio(){
  if(!A)return; const b=A.b, audio=A.audio, c=curChapter(), n=(b.chapters||[]).length, prev=aPrev(), next=aNext();
  let ov=document.getElementById('aov'); if(ov)ov.remove();
  ov=document.createElement('div'); ov.className='audio-np'; ov.id='aov'; A.ov.appendChild(ov);
  ov.innerHTML=`
    <div class="np-top"><button class="icon-btn" id="aback" style="background:rgba(255,255,255,.12);color:#fff">‹</button>
      <div class="spacer"></div><div class="np-book">${esc(b.title)}</div><div class="spacer"></div>
      <button class="icon-btn" id="afav" style="background:rgba(255,255,255,.12);color:${isFav(b)?'var(--pink)':'#fff'}">${isFav(b)?'♥':'♡'}</button></div>
    <div class="np-cover" style="background:${catColor(b.category)}33">${bookCover(b)}</div>
    <div class="np-title">${esc(c.title||'第 '+(A.ci+1)+' 章')}</div>
    <div class="np-sub">${esc(b.author||'听书')} · 第 ${A.ci+1}/${n} 章</div>
    <div class="np-scrub"><span class="tm" id="atcur">0:00</span>
      <div class="track" id="atrack"><div class="fill" id="afill"></div><div class="knob" id="aknob"></div></div>
      <span class="tm" id="atrem" style="text-align:right">0:00</span></div>
    <div class="np-ctrls">
      <button class="cbtn sm ${prev==null?'dis':''}" id="aprev">⏮</button>
      <button class="cbtn sm" id="ab15">⟲</button>
      <button class="cbtn" id="aplay">${audio.paused?'▶':'⏸'}</button>
      <button class="cbtn sm" id="af15">⟳</button>
      <button class="cbtn sm ${next==null?'dis':''}" id="anext">⏭</button></div>
    <div class="np-tools"><select class="tool" id="arate" style="background:#1c1f25">${SPEEDS.map(s=>`<option value="${s}" ${audio.playbackRate===s?'selected':''}>${s}×</option>`).join('')}</select>
      <button class="tool" id="alist">章节</button></div>`;
  ov.querySelector('#aback').onclick=closeAudio;
  ov.querySelector('#afav').onclick=()=>{toggleFav(b);renderAudio()};
  ov.querySelector('#aplay').onclick=()=>{audio.paused?audio.play():audio.pause()};
  ov.querySelector('#ab15').onclick=()=>{audio.currentTime=Math.max(0,audio.currentTime-15)};
  ov.querySelector('#af15').onclick=()=>{audio.currentTime=Math.min(audio.duration||1e9,audio.currentTime+15)};
  if(prev!=null)ov.querySelector('#aprev').onclick=()=>audioGoTo(prev);
  if(next!=null)ov.querySelector('#anext').onclick=()=>audioGoTo(next);
  ov.querySelector('#arate').onchange=e=>{audio.playbackRate=parseFloat(e.target.value)};
  ov.querySelector('#alist').onclick=showAChapters;
  const track=ov.querySelector('#atrack');
  const seek=e=>{const rc=track.getBoundingClientRect();const x=Math.max(0,Math.min(1,(e.clientX-rc.left)/rc.width));audio.currentTime=x*(audio.duration||0);updateAScrub();};
  track.onpointerdown=e=>{A.scrubbing=true;seek(e);const mv=ev=>seek(ev);const up=()=>{A.scrubbing=false;document.removeEventListener('pointermove',mv);document.removeEventListener('pointerup',up)};document.addEventListener('pointermove',mv);document.addEventListener('pointerup',up);};
  updateAScrub();
}
function updateAScrub(){
  if(!A)return; const a=A.audio, d=a.duration||0, c=a.currentTime||0, pct=d?c/d*100:0;
  const fill=document.getElementById('afill'); if(fill)fill.style.width=pct+'%';
  const knob=document.getElementById('aknob'); if(knob)knob.style.left=pct+'%';
  const tc=document.getElementById('atcur'); if(tc)tc.textContent=clock(c);
  const tr=document.getElementById('atrem'); if(tr)tr.textContent='-'+clock(Math.max(0,d-c));
}
function showAChapters(){
  const b=A.b, chs=b.chapters||[];
  const sh=document.createElement('div'); sh.className='breakov'; sh.style.background='rgba(0,0,0,.88)'; sh.style.zIndex='10';
  sh.innerHTML=`<div style="width:480px;max-height:80vh;overflow:auto;text-align:left">
    <div class="row-h" style="padding:0 4px 12px"><h2 style="margin:0">${esc(b.title)}</h2><div class="spacer"></div><button class="icon-btn" id="acx">✕</button></div>
    ${chs.map((c,i)=>`<button data-ach="${i}" style="display:flex;gap:12px;width:100%;padding:10px;border-radius:12px;${i===A.ci?'background:var(--card)':''};align-items:center;text-align:left">
      <span style="color:var(--faint);min-width:28px">${String(i+1).padStart(2,'0')}</span>
      <span style="flex:1;font-weight:600;color:${i===A.ci?'var(--accent-hi)':'#fff'}">${esc(c.title||'第 '+(i+1)+' 章')}</span>
      <span style="color:var(--faint);font-size:13px">${c.durationSec?clock(c.durationSec):''}</span></button>`).join('')}</div>`;
  A.ov.appendChild(sh);
  sh.querySelector('#acx').onclick=()=>sh.remove();
  sh.querySelectorAll('[data-ach]').forEach(btn=>btn.onclick=()=>{const i=parseInt(btn.dataset.ach);sh.remove();if(i!==A.ci)audioGoTo(i);});
}
function reportATick(){ if(!A)return; const pos=Math.floor(A.audio.currentTime||0); setAbResume(A.b.id,A.ci,pos); A.lastReported=pos; }
function teardownAudio(){ if(!A)return; clearInterval(A.heartbeat); A.audio.pause(); A.ov.remove(); A=null; }
function closeAudio(){ if(A){reportATick();teardownAudio();} S.view='main'; S.tab='listen'; render(); }
function audioGoTo(i){ if(A)reportATick(); const id=A.b.id; teardownAudio(); openAudio(id,i); }
function audioEnded(){ if(!A)return; const n=aNext(); if(n!=null)audioGoTo(n); else { setAbResume(A.b.id,A.ci,0); renderAudio(); } }

// ===== 初始化 =====
(async function init(){
  if(!API.token){ S.view='activation'; render(); return; }
  S.view='main'; S.tab='home'; render();
  await reload(); render();
  setInterval(async()=>{ if(S.view==='main'&&S.tab==='home'&&!S.sub){ await reload(); rerenderScreen(); } },20000);
})();
