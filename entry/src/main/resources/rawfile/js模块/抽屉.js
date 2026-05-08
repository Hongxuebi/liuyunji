// 抽屉.js - 会话抽屉和备忘录抽屉的控制
let 当前激活面板 = '对话面板';  // 模块变量
window.当前激活面板 = '对话面板'; // 立即暴露到 window，供其他模块初始化时读取

window.绑定抽屉事件 = function() {
  const 会话抽屉 = document.getElementById('会话抽屉');
  const 备忘录抽屉 = document.getElementById('备忘录抽屉');
  const 遮罩 = document.getElementById('抽屉遮罩');
  const 开关 = document.getElementById('抽屉开关');
  if (!会话抽屉 || !备忘录抽屉 || !遮罩 || !开关) return;
  
  function 打开抽屉() {
    会话抽屉.classList.remove('打开');
    备忘录抽屉.classList.remove('打开');
    遮罩.style.opacity = '';
    if (当前激活面板 === '对话面板') {
      会话抽屉.classList.add('打开');
      会话抽屉.style.transform = '';
    } else if (当前激活面板 === '备忘录面板') {
      备忘录抽屉.classList.add('打开');
      备忘录抽屉.style.transform = '';
    }
    遮罩.classList.add('显示');
  }
  
  function 关闭抽屉() {
    会话抽屉.classList.remove('打开');
    备忘录抽屉.classList.remove('打开');
    遮罩.classList.remove('显示');
    // 重置拖拽状态
    const 当前开口 = 会话抽屉.classList.contains('打开') ? 会话抽屉 : 备忘录抽屉;
    if (当前开口) 当前开口.style.transform = '';
  }
  
  开关.addEventListener('click', 打开抽屉);
  遮罩.addEventListener('click', 关闭抽屉);
  
  // 抽屉拖拽滑动关闭（向右滑动 → 关闭）
  let 拖拽状态 = null;
  
  function 开始拖拽(e) {
    const 触摸 = e.touches[0];
    拖拽状态 = { startX: 触摸.clientX, startY: 触摸.clientY, 已关闭: false };
  }
  
  function 拖拽移动(e) {
    if (!拖拽状态 || 拖拽状态.已关闭) return;
    const 触摸 = e.touches[0];
    const 当前抽屉 = 会话抽屉.classList.contains('打开') ? 会话抽屉 :
                  (备忘录抽屉.classList.contains('打开') ? 备忘录抽屉 : null);
    if (!当前抽屉) return;
    
    const dx = 触摸.clientX - 拖拽状态.startX;
    const dy = 触摸.clientY - 拖拽状态.startY;
    
    // 优先判定水平拖拽（>15px 且 水平>垂直）
    if (Math.abs(dx) < 8 && Math.abs(dy) < 8) return;
    if (Math.abs(dy) > Math.abs(dx) * 1.5) {
      // 垂直滚动，不干扰
      return;
    }
    if (dx < 0) return; // 向左滑忽略
    
    // 应用拖拽位移，限制最大位移为 60%
    const 抽屉宽 = 当前抽屉.offsetWidth;
    const 位移 = Math.min(dx, 抽屉宽 * 0.6);
    当前抽屉.style.transform = `translateX(${位移}px)`;
    当前抽屉.style.transition = 'none';
    遮罩.style.opacity = Math.max(0, 1 - 位移 / 抽屉宽);
  }
  
  function 结束拖拽(e) {
    if (!拖拽状态) return;
    const 当前抽屉 = 会话抽屉.classList.contains('打开') ? 会话抽屉 :
                  (备忘录抽屉.classList.contains('打开') ? 备忘录抽屉 : null);
    if (!当前抽屉) { 拖拽状态 = null; return; }
    
    const 抽屉宽 = 当前抽屉.offsetWidth;
    // 从 transform 解析当前位移
    const 矩阵 = getComputedStyle(当前抽屉).transform;
    const 匹配 = 矩阵.match(/matrix\([^,]+,\s*[^,]+,\s*[^,]+,\s*[^,]+,\s*([^,]+)/);
    const 当前位移 = 匹配 ? Math.max(0, parseFloat(匹配[1]) || 0) : 0;
    
    if (当前位移 > 抽屉宽 * 0.25) {
      // 超过 25% 宽度 → 关闭
      当前抽屉.style.transition = 'transform 0.25s ease, opacity 0.25s ease';
      当前抽屉.style.transform = '';
      // 等 150ms 后直接关闭（保持视觉连贯）
      setTimeout(() => { if (window.关闭抽屉) window.关闭抽屉(); }, 120);
      拖拽状态.已关闭 = true;
    } else {
      // 不足 → 弹回
      当前抽屉.style.transition = 'transform 0.2s ease, opacity 0.2s ease';
      当前抽屉.style.transform = '';
      遮罩.style.opacity = '';
    }
    拖拽状态 = null;
  }
  
  // 在遮罩上绑定触摸事件（遮罩在抽屉上方，不影响抽屉内滚动）
  遮罩.addEventListener('touchstart', 开始拖拽, { passive: true });
  遮罩.addEventListener('touchmove', 拖拽移动, { passive: true });
  遮罩.addEventListener('touchend', 结束拖拽, { passive: true });
  
  window.关闭抽屉 = 关闭抽屉;
  window.打开抽屉 = 打开抽屉;
};

// 供标签页切换时更新当前激活面板
window.设置当前激活面板 = function(面板ID) {
  当前激活面板 = 面板ID;
  window.当前激活面板 = 面板ID; // 同步到 window，供其他模块读取
  console.log('当前激活面板已更新为:', 面板ID);
};