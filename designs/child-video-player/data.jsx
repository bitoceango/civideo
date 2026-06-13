// 模拟视频库内容 —— 教育向，贴合 10-12 岁"专注学习"定位
// 每个系列对应后端 manifest.json 里的 series 字段；poster 用确定性渐变占位（待家长上传真实封面）

const SERIES = [
  {
    key: "planet-earth",
    title: "行星地球",
    subtitle: "BBC 自然纪录片",
    hue: 190,
    episodes: [
      { id: "pe01", title: "从极地到赤道", durationSec: 2940, progress: 0.62 },
      { id: "pe02", title: "高山之巅", durationSec: 2880, progress: 0 },
      { id: "pe03", title: "丛林深处", durationSec: 2820, progress: 0 },
      { id: "pe04", title: "深海", durationSec: 3000, progress: 0 },
      { id: "pe05", title: "草原季节", durationSec: 2760, progress: 0 },
      { id: "pe06", title: "洞穴世界", durationSec: 2700, progress: 0 },
    ],
  },
  {
    key: "physics",
    title: "给孩子的物理课",
    subtitle: "看得见的科学原理",
    hue: 28,
    episodes: [
      { id: "ph01", title: "力是什么", durationSec: 1080, progress: 1 },
      { id: "ph02", title: "看不见的电", durationSec: 1140, progress: 0.34 },
      { id: "ph03", title: "光的旅行", durationSec: 1200, progress: 0 },
      { id: "ph04", title: "声音的秘密", durationSec: 1020, progress: 0 },
      { id: "ph05", title: "浮力与沉没", durationSec: 1110, progress: 0 },
    ],
  },
  {
    key: "magic-bus",
    title: "神奇校车",
    subtitle: "英文原声 · 中英字幕",
    hue: 50,
    episodes: [
      { id: "mb01", title: "Inside the Earth", durationSec: 1500, progress: 0 },
      { id: "mb02", title: "Lost in the Solar System", durationSec: 1500, progress: 0 },
      { id: "mb03", title: "Inside the Human Body", durationSec: 1500, progress: 0 },
      { id: "mb04", title: "The Waterworks", durationSec: 1500, progress: 0 },
    ],
  },
  {
    key: "history",
    title: "中国历史故事",
    subtitle: "从远古到近代",
    hue: 8,
    episodes: [
      { id: "hi01", title: "甲骨文的秘密", durationSec: 960, progress: 0 },
      { id: "hi02", title: "丝绸之路", durationSec: 1020, progress: 0 },
      { id: "hi03", title: "都江堰", durationSec: 900, progress: 0 },
      { id: "hi04", title: "郑和下西洋", durationSec: 1080, progress: 0 },
      { id: "hi05", title: "活字印刷", durationSec: 960, progress: 0 },
    ],
  },
  {
    key: "math",
    title: "数学思维启蒙",
    subtitle: "原来数学这么有趣",
    hue: 280,
    episodes: [
      { id: "ma01", title: "无处不在的对称", durationSec: 840, progress: 0 },
      { id: "ma02", title: "斐波那契与自然", durationSec: 900, progress: 0 },
      { id: "ma03", title: "概率是什么", durationSec: 780, progress: 0 },
    ],
  },
];

// 扁平索引：id -> {episode, series}
const VIDEO_INDEX = {};
for (const s of SERIES) {
  for (const ep of s.episodes) VIDEO_INDEX[ep.id] = { ep, series: s };
}

// 继续观看：有进度但未看完的，按系列里取出
const CONTINUE = ["pe01", "ph02"].map((id) => VIDEO_INDEX[id]);

function fmtClock(sec) {
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return `${m}:${String(s).padStart(2, "0")}`;
}
function fmtRuntime(sec) {
  const m = Math.round(sec / 60);
  return `${m} 分钟`;
}

Object.assign(window, { SERIES, VIDEO_INDEX, CONTINUE, fmtClock, fmtRuntime });
