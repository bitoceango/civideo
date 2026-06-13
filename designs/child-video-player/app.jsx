const { useState, useEffect, useRef } = React;
const Ic = window.Ic;

// 确定性封面渐变（待家长上传真实封面图前的占位）
function posterStyle(hue, seed = 0) {
  const h2 = (hue + 38) % 360;
  return {
    background: `linear-gradient(150deg,
      oklch(0.48 0.13 ${hue}) 0%,
      oklch(0.34 0.10 ${(hue + h2) / 2}) 55%,
      oklch(0.24 0.06 ${h2}) 100%)`,
  };
}

/* ============================ 库主页 ============================ */
function Poster({ item, big, onPlay }) {
  const { ep, series } = item;
  const idx = series.episodes.indexOf(ep) + 1;
  return (
    <button className={"poster" + (big ? " cont" : "")} onClick={() => onPlay(item)}>
      <div className="art" style={posterStyle(series.hue)}>
        <span className="ep-no">第 {String(idx).padStart(2, "0")} 集</span>
        <span className="art-title">{ep.title}</span>
        <span className="runtime">{fmtRuntime(ep.durationSec)}</span>
        <span className="play-badge"><span><Ic.play width="24" style={{ marginLeft: 3 }} /></span></span>
        {ep.progress > 0 && ep.progress < 1 && (
          <div className="pbar"><i style={{ width: `${ep.progress * 100}%` }} /></div>
        )}
      </div>
      <div className="meta">
        <div className="t">{big ? ep.title : series.title}</div>
        <div className="s">
          {big
            ? `${series.title} · 还剩 ${fmtRuntime(ep.durationSec * (1 - ep.progress))}`
            : series.subtitle}
        </div>
      </div>
    </button>
  );
}

function Library({ onPlay, onParent, remainingMin }) {
  const low = remainingMin <= 10;
  return (
    <div className="scroll">
      <div className="home-head">
        <div className="greet">
          <div className="avatar">娃</div>
          <div>
            <h1>下午好，小朋友</h1>
            <p>今天想学点什么呢？</p>
          </div>
        </div>
        <div className="head-right">
          <span className={"pill time-pill" + (low ? " low" : "")}>
            <span className="dot" />
            今天还可观看 {remainingMin} 分钟
          </span>
          <button className="icon-btn" title="家长" onClick={onParent}><Ic.lock width="20" /></button>
        </div>
      </div>

      <div className="section">
        <div className="section-head"><h2>继续观看</h2></div>
        <div className="row">
          {CONTINUE.map((it) => <Poster key={it.ep.id} item={it} big onPlay={onPlay} />)}
        </div>
      </div>

      {SERIES.map((s) => (
        <div className="section" key={s.key}>
          <div className="section-head">
            <h2>{s.title}</h2>
            <span className="sub">{s.subtitle} · 共 {s.episodes.length} 集</span>
          </div>
          <div className="row">
            {s.episodes.map((ep) => (
              <Poster key={ep.id} item={{ ep, series: s }} onPlay={onPlay} />
            ))}
          </div>
        </div>
      ))}
      <div style={{ height: 70 }} />
    </div>
  );
}

/* ============================ 播放页 ============================ */
function Player({ item, onBack, onPlay }) {
  const { ep, series } = item;
  const idx = series.episodes.indexOf(ep);
  const nextEp = series.episodes[idx + 1];
  const dur = ep.durationSec;
  const [playing, setPlaying] = useState(true);
  const [t, setT] = useState(Math.floor(dur * (ep.progress || 0)));
  const [speed, setSpeed] = useState(1);
  const [showUI, setShowUI] = useState(true);
  const hideTimer = useRef(null);

  // 模拟播放推进
  useEffect(() => {
    if (!playing) return;
    const id = setInterval(() => setT((x) => Math.min(dur, x + speed)), 1000);
    return () => clearInterval(id);
  }, [playing, speed, dur]);

  // 控件自动隐藏
  const poke = () => {
    setShowUI(true);
    clearTimeout(hideTimer.current);
    hideTimer.current = setTimeout(() => playing && setShowUI(false), 2800);
  };
  useEffect(() => { poke(); return () => clearTimeout(hideTimer.current); }, [playing]);

  const pct = (t / dur) * 100;
  const buffered = Math.min(100, pct + 12);
  const nearEnd = dur - t < 40 && nextEp;
  const seek = (e) => {
    const r = e.currentTarget.getBoundingClientRect();
    setT(Math.round(((e.clientX - r.left) / r.width) * dur));
    poke();
  };

  return (
    <div className="player" onMouseMove={poke} onClick={poke}>
      <div className="video-canvas">
        <div className="holder">
          <div className="big">{series.title.toUpperCase()}</div>
          <div style={{ marginTop: 8, fontSize: 13 }}>视频画面（AVPlayer）</div>
        </div>
      </div>

      <div className={"pl-overlay" + (showUI ? "" : " hidden")}>
        <div className="pl-top">
          <button className="icon-btn" style={{ background: "oklch(1 0 0 / .12)", borderColor: "transparent", color: "#fff" }}
            onClick={(e) => { e.stopPropagation(); onBack(); }}><Ic.back width="22" /></button>
          <div>
            <div className="t">{ep.title}</div>
            <div className="s">{series.title} · 第 {idx + 1} 集</div>
          </div>
        </div>

        <div className="pl-center" onClick={(e) => e.stopPropagation()}>
          <button className="big-btn skip" onClick={() => setT((x) => Math.max(0, x - 10))}><Ic.back10 width="30" /></button>
          <button className="big-btn" onClick={() => setPlaying((p) => !p)}>
            {playing ? <Ic.pause width="38" /> : <Ic.play width="38" style={{ marginLeft: 4 }} />}
          </button>
          <button className="big-btn skip" onClick={() => setT((x) => Math.min(dur, x + 10))}><Ic.fwd10 width="30" /></button>
        </div>

        <div className="pl-bottom" onClick={(e) => e.stopPropagation()}>
          <div className="scrub">
            <span className="time">{fmtClock(t)}</span>
            <div className="track" onClick={seek}>
              <div className="buf" style={{ width: `${buffered}%` }} />
              <div className="fill" style={{ width: `${pct}%` }} />
              <div className="knob" style={{ left: `${pct}%` }} />
            </div>
            <span className="time r">-{fmtClock(dur - t)}</span>
          </div>
          <div className="pl-tools">
            <div className="group">
              {[1, 1.25, 1.5].map((s) => (
                <button key={s} className={"ghost-btn" + (speed === s ? " active" : "")} onClick={() => setSpeed(s)}>
                  {s}×
                </button>
              ))}
            </div>
            <div className="group">
              <button className="ghost-btn"><Ic.volume width="18" /></button>
              {nextEp && (
                <button className="ghost-btn" onClick={() => onPlay({ ep: nextEp, series })}>
                  <Ic.next width="18" /> 下一集
                </button>
              )}
              <button className="ghost-btn"><Ic.expand width="18" /></button>
            </div>
          </div>
        </div>
      </div>

      {nearEnd && (
        <div className="next-card">
          <div className="nthumb" style={posterStyle(series.hue)} />
          <div>
            <div className="lbl">即将播放 · 同系列</div>
            <div className="nt">{nextEp.title}</div>
            <div className="ns">{series.title} · 第 {idx + 2} 集</div>
            <button className="ghost-btn" style={{ marginTop: 8, borderColor: "var(--accent)", color: "var(--accent-bright)" }}
              onClick={() => onPlay({ ep: nextEp, series })}><Ic.play width="14" /> 立即播放</button>
          </div>
        </div>
      )}
    </div>
  );
}

/* ============================ 家长页（PIN + 设置）============================ */
const PARENT_PIN = "1234";
function Parent({ onExit }) {
  const [pin, setPin] = useState("");
  const [err, setErr] = useState(false);
  const [unlocked, setUnlocked] = useState(false);

  const press = (d) => {
    if (pin.length >= 4) return;
    const np = pin + d;
    setPin(np);
    if (np.length === 4) {
      setTimeout(() => {
        if (np === PARENT_PIN) setUnlocked(true);
        else { setErr(true); setTimeout(() => { setErr(false); setPin(""); }, 600); }
      }, 150);
    }
  };

  if (unlocked) return <ParentSettings onExit={onExit} />;

  return (
    <div className="parent">
      <div className="pin-card">
        <div className="lock-ring"><Ic.lock width="30" /></div>
        <h2>家长验证</h2>
        <p>输入密码进入设置（演示密码 1234）</p>
        <div className={"pin-dots" + (err ? " err" : "")}>
          {[0, 1, 2, 3].map((i) => <i key={i} className={i < pin.length ? "on" : ""} />)}
        </div>
        <div className="keypad">
          {[1, 2, 3, 4, 5, 6, 7, 8, 9].map((n) => (
            <button key={n} onClick={() => press(String(n))}>{n}</button>
          ))}
          <button className="ghost" onClick={onExit}>取消</button>
          <button onClick={() => press("0")}>0</button>
          <button className="ghost" onClick={() => setPin((p) => p.slice(0, -1))}>⌫</button>
        </div>
      </div>
    </div>
  );
}

function ParentSettings({ onExit }) {
  const [limit, setLimit] = useState(60);
  const [win, setWin] = useState("after-school");
  return (
    <div className="parent" style={{ alignItems: "start" }}>
      <div className="scroll" style={{ width: "100%" }}>
        <div className="settings" style={{ margin: "0 auto" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 22 }}>
            <div>
              <h2>家长设置</h2>
              <p className="lead" style={{ margin: 0 }}>已连接 video.example.com</p>
            </div>
            <button className="pill" onClick={onExit}><Ic.back width="16" /> 返回</button>
          </div>

          <div className="set-group">
            <div className="set-row">
              <div className="k">每日观看上限
                <small>看满后自动进入"休息一下"页面</small>
              </div>
              <div className="stepper">
                <button onClick={() => setLimit((v) => Math.max(15, v - 15))}>−</button>
                <span className="val">{limit} 分钟</span>
                <button onClick={() => setLimit((v) => Math.min(180, v + 15))}>+</button>
              </div>
            </div>
            <div className="set-row">
              <div className="k">允许观看时段
                <small>仅在此时段内可以播放</small>
              </div>
              <div className="seg">
                {[["after-school", "放学后"], ["weekend", "仅周末"], ["custom", "自定义"]].map(([k, l]) => (
                  <button key={k} className={win === k ? "on" : ""} onClick={() => setWin(k)}>{l}</button>
                ))}
              </div>
            </div>
            <div className="set-row">
              <div className="k">自动播放下一集
                <small>仅限同一系列，不跨系列推荐</small>
              </div>
              <div className="seg"><button className="on">开</button><button>关</button></div>
            </div>
          </div>

          <div className="set-group">
            <div className="set-row" style={{ display: "block" }}>
              <div className="k" style={{ marginBottom: 6 }}>已激活的设备</div>
              <div className="device-chip">
                <div className="ds">▣</div>
                <div style={{ flex: 1 }}>
                  <div style={{ fontWeight: 600 }}>客厅 iPad</div>
                  <div style={{ fontSize: 12.5, color: "var(--faint)" }}>今天已观看 28 分钟</div>
                </div>
                <button className="icon-btn" style={{ width: 38, height: 38 }}><Ic.del width="17" /></button>
              </div>
              <div className="device-chip" style={{ borderTop: "1px solid var(--line)" }}>
                <div className="ds">▢</div>
                <div style={{ flex: 1 }}>
                  <div style={{ fontWeight: 600 }}>小朋友的 iPhone</div>
                  <div style={{ fontSize: 12.5, color: "var(--faint)" }}>今天已观看 6 分钟</div>
                </div>
                <button className="icon-btn" style={{ width: 38, height: 38 }}><Ic.del width="17" /></button>
              </div>
            </div>
          </div>

          <button className="primary-btn">＋ 激活一台新设备</button>
          <div style={{ height: 40 }} />
        </div>
      </div>
    </div>
  );
}

/* ============================ 休息一下 ============================ */
function BreakScreen({ reason, onParent }) {
  const isHours = reason === "hours";
  return (
    <div className="breakscr">
      <div className="break-card">
        <div className="cup"><Ic.cup width="46" /></div>
        <h2>{isHours ? "现在不是观看时间哦" : "今天的观看时间到啦"}</h2>
        <p>{isHours ? "到了约定的时段就可以继续看啦。" : "看了很久啦，让眼睛休息一下吧 👀"}</p>
        <p>不如去做点别的：读本书、出去走走、画幅画。</p>
        <div className="countdown">
          {isHours ? "放学后 16:00 可以继续观看" : "明天又有新的观看时间"}
        </div>
        <button className="pinlink" onClick={onParent}><Ic.lock width="14" /> 家长可输入密码解除</button>
      </div>
    </div>
  );
}

/* ============================ 根 ============================ */
function App() {
  const initial = (typeof location !== "undefined" && location.hash.slice(1)) || "library";
  const [screen, setScreenRaw] = useState(["library", "player", "parent", "break"].includes(initial) ? initial : "library");
  const [current, setCurrent] = useState(initial === "player" ? { ep: SERIES[0].episodes[0], series: SERIES[0] } : null);
  const [hue, setHue] = useState(196);
  const [breakReason, setBreakReason] = useState("limit");

  const setScreen = (s) => { setScreenRaw(s); if (typeof location !== "undefined") location.hash = s; };

  useEffect(() => { document.documentElement.style.setProperty("--accent-h", hue); }, [hue]);

  const play = (item) => { setCurrent(item); setScreen("player"); };

  return (
    <div className="stage">
      <div className="ipad">
        <div className="screen">
          {screen === "library" && <Library onPlay={play} onParent={() => setScreen("parent")} remainingMin={32} />}
          {screen === "player" && current && <Player item={current} onBack={() => setScreen("library")} onPlay={play} />}
          {screen === "parent" && <Parent onExit={() => setScreen("library")} />}
          {screen === "break" && <BreakScreen reason={breakReason} onParent={() => setScreen("parent")} />}
        </div>
      </div>

      {/* 原型用：屏幕切换 + 主题色微调 */}
      <div className="switcher">
        {[["library", "库主页"], ["player", "播放页"], ["parent", "家长"], ["break", "休息页"]].map(([k, l]) => (
          <button key={k} className={screen === k ? "on" : ""}
            onClick={() => { if (k === "player" && !current) setCurrent({ ep: SERIES[0].episodes[0], series: SERIES[0] }); setScreen(k); }}>
            {l}
          </button>
        ))}
        {screen === "break" && (
          <>
            <div className="sep" />
            <button className={breakReason === "limit" ? "on" : ""} onClick={() => setBreakReason("limit")}>超时长</button>
            <button className={breakReason === "hours" ? "on" : ""} onClick={() => setBreakReason("hours")}>超时段</button>
          </>
        )}
        <div className="sep" />
        <span className="hue">主题<input type="range" min="20" max="320" value={hue} onChange={(e) => setHue(+e.target.value)} /></span>
      </div>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
