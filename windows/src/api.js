// 与 Worker 通信 + 本地持久化（localStorage）
const API = {
  get server(){ return localStorage.getItem('cv.server') || '' },
  set server(v){ localStorage.setItem('cv.server', v) },
  get token(){ return localStorage.getItem('cv.token') || '' },
  set token(v){ v ? localStorage.setItem('cv.token', v) : localStorage.removeItem('cv.token') },
  get childName(){ return localStorage.getItem('cv.childName') || '小朋友' },

  // 媒体/封面：HTML <video>/<img> 不能设请求头，用 ?t= query 令牌
  mediaUrl(rel){ return `${this.server}${rel}?t=${encodeURIComponent(this.token)}` },

  authHeaders(){ return this.token ? { 'Authorization': `Bearer ${this.token}` } : {} },

  async activate(server, pin, name){
    const r = await fetch(`${server}/api/activate`, {
      method:'POST', headers:{'content-type':'application/json'},
      body: JSON.stringify({ pin, name })
    });
    if(r.status === 403) throw new Error('密码不正确');
    if(!r.ok) throw new Error('激活失败（'+r.status+'）');
    const j = await r.json();
    this.server = server; this.token = j.token;
    return j;
  },

  async library(){
    const r = await fetch(`${this.server}/api/library`, { headers: this.authHeaders() });
    if(r.status === 401){ this.token=''; throw new Error('unauthorized'); }
    if(!r.ok) throw new Error('网络错误');
    return r.json();
  },

  todayKey(){ const d=new Date(); return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}` },
  minuteOfDay(){ const d=new Date(); return d.getHours()*60+d.getMinutes() },

  async progress(){
    const r = await fetch(`${this.server}/api/progress?day=${this.todayKey()}`, { headers: this.authHeaders() });
    if(r.status === 401){ this.token=''; throw new Error('unauthorized'); }
    if(!r.ok) throw new Error('网络错误');
    return r.json();
  },

  async postProgress(videoId, positionSec, deltaSec){
    try{
      const r = await fetch(`${this.server}/api/progress`, {
        method:'POST', headers:{'content-type':'application/json', ...this.authHeaders()},
        body: JSON.stringify({ videoId, positionSec, day:this.todayKey(), deltaSec:Math.max(0,deltaSec), minuteOfDay:this.minuteOfDay() })
      });
      return r.ok ? r.json() : {};
    }catch(e){ return {}; }
  },

  async saveRules(pin, dailyLimitMin, allowedStart, allowedEnd){
    const r = await fetch(`${this.server}/api/rules`, {
      method:'POST', headers:{'content-type':'application/json', ...this.authHeaders()},
      body: JSON.stringify({ pin, dailyLimitMin, allowedStart, allowedEnd })
    });
    if(r.status === 403) throw new Error('密码不正确');
    if(!r.ok) throw new Error('保存失败');
  },

  logout(){ this.token=''; }
};
