// 卡片滑动.js - 左滑菜单逻辑
// 2026-05-07 v4: 全 passive + CSS touch-action: pan-y 协作
// 浏览器原生处理竖滚（零延迟），JS 只负责横滑视觉反馈

let 当前滑动卡片 = null;
let 滑动起始X = 0;
let 滑动起始Y = 0; // ★ 新增：记录起始Y，用于早期方向判定
let 当前滑动X = 0;
let 卡片宽度 = 0;
const 操作栏宽度 = 300;
const 滑动阈值 = 30;
const 方向判定阈值 = 8; // ★ 新增：移动8px即可判定方向，低于此值不做判定
let 是否发生了滑动 = false;
let 当前展开的卡片容器 = null;
let 忽略下次点击 = false;
let 已判定为竖滚 = false;
let 滑动保护中 = false; // ★ 滑动结束后 300ms 内阻止 click 误触

function 初始化卡片滑动() {
  const 卡片列表 = document.querySelectorAll('.备忘录卡片滑动容器');
  卡片列表.forEach(容器 => {
    const 卡片 = 容器.querySelector('.备忘录卡片');
    if (!卡片) return;
    
    卡片.removeEventListener('mousedown', 开始滑动);
    卡片.removeEventListener('touchstart', 开始滑动);
    卡片.removeEventListener('touchmove', 触摸移动);
    卡片.removeEventListener('touchend', 触摸结束);
    
    // 全部 passive: true —— CSS touch-action: pan-y 保证浏览器原生处理竖滚
    // JS 不需要 preventDefault，浏览器零等待开始滚动
    卡片.addEventListener('mousedown', 开始滑动);
    卡片.addEventListener('touchstart', 开始滑动, { passive: true });
    卡片.addEventListener('touchmove', 触摸移动, { passive: true });
    卡片.addEventListener('touchend', 触摸结束, { passive: true });
    
    const 操作栏按钮 = 容器.querySelectorAll('.操作栏按钮');
    操作栏按钮.forEach(按钮 => {
      按钮.removeEventListener('click', 操作栏点击处理);
      按钮.addEventListener('click', 操作栏点击处理);
    });
    
    const 复选框 = 容器.querySelector('.多选复选框');
    if (复选框) {
      复选框.removeEventListener('click', 复选框点击处理);
      复选框.addEventListener('click', 复选框点击处理);
    }
  });
  
  document.removeEventListener('click', 全局点击收起);
  document.addEventListener('click', 全局点击收起);
  document.removeEventListener('mousemove', 桌面鼠标移动);
  document.removeEventListener('mouseup', 桌面鼠标结束);
  document.addEventListener('mousemove', 桌面鼠标移动);
  document.addEventListener('mouseup', 桌面鼠标结束);
}

function 复选框点击处理(e) {
  e.stopPropagation();
  const 复选框 = e.currentTarget;
  const 容器 = 复选框.closest('.备忘录卡片滑动容器');
  if (!容器) return;
  const id = parseInt(容器.dataset.id);
  window.多选状态?.切换选中(id);
}

function 操作栏点击处理(e) {
  e.stopPropagation();
  const 按钮 = e.currentTarget;
  const action = 按钮.dataset.action;
  const 容器 = 按钮.closest('.备忘录卡片滑动容器');
  if (!容器) return;
  const id = parseInt(容器.dataset.id);
  switch (action) {
    case 'favorite': window._切换收藏(id); break;
    case 'pin': {
      const 当前备忘录 = window.备忘录管理器?.memos?.find(m => m.id === id) || (window._备忘录数据 || []).find(m => m.id === id);
      当前备忘录?.已置顶 ? window._取消置顶(id) : window._置顶备忘录(id);
      break;
    }
    case 'move': {
      const 待移动备忘录 = (window._备忘录数据源 || []).find(m => m.id === id);
      const 当前文件夹 = 待移动备忘录?.文件夹 || '未分类';
      const 所有文件夹 = window._获取所有文件夹列表 ? window._获取所有文件夹列表().map(f => f.名称) : ['未分类'];
      const 目标文件夹 = prompt(`移动「${待移动备忘录?.标题?.slice(0, 20) || id}」\n\n当前：${当前文件夹}\n\n输入目标文件夹名称：\n\n可用：${所有文件夹.join('、')}`);
      if (!目标文件夹) break;
      if (!所有文件夹.includes(目标文件夹)) { alert(`文件夹「${目标文件夹}」不存在`); break; }
      if (目标文件夹 === 当前文件夹) { alert('已在该文件夹中'); break; }
      window.备忘录管理器.updateMemo(id, { 文件夹: 目标文件夹 }).then(() => { if (window.渲染备忘录列表) window.渲染备忘录列表(); });
      break;
    }
    case 'delete': window._删除备忘录(id); break;
    case 'restore': window._恢复备忘录(id); break;
    case 'permanent-delete': window._永久删除备忘录(id); break;
  }
}

function 全局点击收起(e) {
  if (忽略下次点击) return;
  if (当前展开的卡片容器) {
    if (当前展开的卡片容器.contains(e.target) && e.target.closest('.操作栏按钮')) return;
    收起所有卡片();
  }
}

function 开始滑动(e) {
  const 是触摸 = e.type.includes('touch');
  const 卡片 = e.currentTarget;
  const 容器 = 卡片.closest('.备忘录卡片滑动容器');
  if (容器.classList.contains('展开') && e.type === 'mousedown') return;
  
  是否发生了滑动 = false;
  已判定为竖滚 = false;
  当前滑动卡片 = 卡片;
  容器.classList.add('滑动中');
  
  滑动起始X = 是触摸 ? e.touches[0].clientX : e.clientX;
  滑动起始Y = 是触摸 ? e.touches[0].clientY : e.clientY; // ★ 记录起始Y
  当前滑动X = 0;
  卡片宽度 = 卡片.offsetWidth;
  
  // touchstart 上不做任何阻止
  if (!是触摸) e.stopPropagation();
  
  const 所有容器 = document.querySelectorAll('.备忘录卡片滑动容器');
  所有容器.forEach(other容器 => {
    if (other容器 !== 容器 && 当前展开的卡片容器 === other容器) 收起卡片(other容器);
  });
}

// 触摸移动 — passive: true，不调 preventDefault
// 核心策略：早期判定方向（8px），竖滚立即退出 JS → 浏览器原生滚，横滑才接管视觉反馈
function 触摸移动(e) {
  if (!当前滑动卡片) return;
  // 已判定为竖滚，后续 touchmove 完全不处理，交给浏览器原生滚动
  if (已判定为竖滚) return;
  
  const clientX = e.touches[0].clientX;
  const clientY = e.touches[0].clientY;
  const deltaX = clientX - 滑动起始X;
  const deltaY = clientY - 滑动起始Y;
  
  // ★ 早期方向判定：移动超过阈值时，判断是竖滚还是横滑
  // 一旦判定为竖滚，本函数后续调用直接 return，竖滚完全交给浏览器
  if (Math.abs(deltaX) > 方向判定阈值 || Math.abs(deltaY) > 方向判定阈值) {
    if (Math.abs(deltaY) >= Math.abs(deltaX)) {
      // 竖向位移 ≥ 横向 → 判定为竖滚，立即退出
      已判定为竖滚 = true;
      return;
    }
  }
  
  // ★ 右滑 → 不触发任何操作栏，直接标记竖滚退出
  if (deltaX > 0) {
    已判定为竖滚 = true;
    return;
  }
  
  // 横滑但位移还太小（<30px），等继续滑
  if (Math.abs(deltaX) < 滑动阈值) return;
  
  // 确认是横滑（左滑），开始视觉反馈
  是否发生了滑动 = true;
  当前滑动X = deltaX;
  let translateX = 当前滑动X;
  if (translateX > 0) translateX = 0;
  else if (translateX < -操作栏宽度) translateX = -操作栏宽度;
  当前滑动卡片.style.transform = `translateX(${translateX}px)`;
  const 容器 = 当前滑动卡片.closest('.备忘录卡片滑动容器');
  const 操作栏 = 容器.querySelector('.卡片操作栏');
  if (操作栏) {
    操作栏.style.opacity = String(Math.min(Math.abs(translateX) / 操作栏宽度, 1));
  }
}

function 触摸结束(e) {
  if (!当前滑动卡片) return;
  结束滑动逻辑();
}

function 桌面鼠标移动(e) {
  if (!当前滑动卡片) return;
  const deltaX = e.clientX - 滑动起始X;
  if (Math.abs(deltaX) < 5) return;
  if (Math.abs(deltaX) > 滑动阈值) 是否发生了滑动 = true;
  // ★ 右滑 → 不触发任何操作栏
  if (deltaX > 0) return;
  当前滑动X = deltaX;
  let translateX = 当前滑动X;
  if (translateX > 0) translateX = 0;
  else if (translateX < -操作栏宽度) translateX = -操作栏宽度;
  当前滑动卡片.style.transform = `translateX(${translateX}px)`;
  const 容器 = 当前滑动卡片.closest('.备忘录卡片滑动容器');
  const 操作栏 = 容器.querySelector('.卡片操作栏');
  if (操作栏) {
    操作栏.style.opacity = String(Math.min(Math.abs(translateX) / 操作栏宽度, 1));
  }
}

function 桌面鼠标结束(e) {
  if (!当前滑动卡片) return;
  结束滑动逻辑();
}

function 结束滑动逻辑() {
  const 容器 = 当前滑动卡片.closest('.备忘录卡片滑动容器');
  容器.classList.remove('滑动中');
  const shouldExpand = Math.abs(当前滑动X) > 操作栏宽度 * 0.3;
  if (shouldExpand) {
    if (当前展开的卡片容器 && 当前展开的卡片容器 !== 容器) 收起卡片(当前展开的卡片容器);
    当前滑动卡片.style.transform = '';
    当前滑动卡片.style.transition = '';
    容器.classList.add('展开');
    const 操作栏 = 容器.querySelector('.卡片操作栏');
    if (操作栏) 操作栏.style.opacity = '1';
    当前展开的卡片容器 = 容器;
    忽略下次点击 = true;
    setTimeout(() => { 忽略下次点击 = false; }, 300);
  } else {
    收起卡片(容器);
  }
  当前滑动卡片 = null;
  滑动起始X = 0;
  滑动起始Y = 0;
  当前滑动X = 0;
  已判定为竖滚 = false;
  // ★ 延迟重置滑动标记，让后续 click 事件仍能检测到"刚发生过滑动"
  if (是否发生了滑动) {
    const 滑动保护 = true;
    setTimeout(() => { 是否发生了滑动 = false; }, 300);
    // 立即置 false 以防影响下一次滑动，但 window 暴露的检测用保护标记
    是否发生了滑动 = false;
    // 用独立标记保护 click
    滑动保护中 = true;
    setTimeout(() => { 滑动保护中 = false; }, 300);
  }
}

function 收起卡片(容器) {
  if (!容器) return;
  const 卡片 = 容器.querySelector('.备忘录卡片');
  if (卡片) {
    卡片.style.transform = '';
    卡片.style.transition = '';
  }
  容器.classList.remove('展开');
  const 操作栏 = 容器.querySelector('.卡片操作栏');
  if (操作栏) 操作栏.style.opacity = '';
  if (当前展开的卡片容器 === 容器) 当前展开的卡片容器 = null;
}

function 收起所有卡片() {
  if (当前展开的卡片容器) 收起卡片(当前展开的卡片容器);
}

window.初始化卡片滑动 = 初始化卡片滑动;
window._是否发生了滑动 = () => 是否发生了滑动 || 滑动保护中;
window._当前展开的卡片 = () => 当前展开的卡片容器;
window._收起所有卡片 = 收起所有卡片;
