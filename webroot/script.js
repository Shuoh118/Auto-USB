
(function () {
  'use strict';

  var MOD = '/data/adb/modules/autousb';
  // 每次改前端就 +1：出错时显示在提示里，能确认页面跑的是不是新脚本
  var BUILD = 'b6';
  // 宿主给的 PATH 不一定包含 /system/bin，用绝对路径最稳
  var CTL = '/system/bin/sh ' + MOD + '/bin/autousbctl';

  var PROFILES = [
    { v: 'mtp',   t: 'MTP',      s: '文件传输，传照片和文件' },
    { v: 'ptp',   t: 'PTP',      s: '相机协议，导入照片' },
    { v: 'rndis', t: 'USB 网卡',  s: '把网络共享给电脑' },
    { v: 'midi',  t: 'MIDI',     s: '连接乐器设备' },
    { v: 'none',  t: '仅充电',    s: '不向主机暴露任何功能' }
  ];

  var $ = function (id) { return document.getElementById(id); };

  var state = {
    cfg: {},          // autousbctl state 的 KEY=VALUE
    readonly: false,
    busy: false,
    pending: false,
    fail: '',
    paintKey: '',
    diag: null        // 最近一次 exec 的调用轨迹，读不到状态时显示出来
  };

  var THEME_KEY = 'autousb-theme';

  function systemDark() {
    return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
  }

  var RIPPLE_MS = 480;
  var rippleFinish = null;

  function reduceMotion() {
    return window.matchMedia &&
           window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  }

  function buildClone(nextMode) {
    var clone = document.createElement('div');
    clone.className = 'theme-clone';
    clone.setAttribute('data-theme', nextMode);
    clone.setAttribute('aria-hidden', 'true');

    var header = document.querySelector('header.appbar');
    var main = document.querySelector('main');

    if (header) {
      var h = header.cloneNode(true);
      h.removeAttribute('id');
      stripIds(h);

      var realChip = header.querySelector('.chip');
      var fakeChip = h.querySelector('.chip');
      if (realChip && fakeChip) {
        fakeChip.textContent = realChip.textContent;
        fakeChip.className = realChip.className;
      }
      clone.appendChild(h);
    }
    if (main) {
      var m = main.cloneNode(true);
      m.removeAttribute('id');
      stripIds(m);
      stripMutable(m);
      clone.appendChild(m);
    }
    return clone;
  }

  function stripIds(root) {
    root.removeAttribute && root.removeAttribute('id');
    var all = root.querySelectorAll ? root.querySelectorAll('[id]') : [];
    for (var i = 0; i < all.length; i++) all[i].removeAttribute('id');
  }

  function stripMutable(root) {
    var els = root.querySelectorAll ? root.querySelectorAll('button, input, select') : [];
    for (var i = 0; i < els.length; i++) {
      els[i].setAttribute('tabindex', '-1');
      els[i].removeAttribute('autofocus');
    }
  }

  function rippleTheme(btn, nextMode) {
    if (reduceMotion()) {
      applyTheme(nextMode);
      releaseThemeLock();
      return;
    }

    var r = btn.getBoundingClientRect();
    var cx = r.left + r.width / 2;
    var cy = r.top + r.height / 2;

    var w = window.innerWidth;
    var h = window.innerHeight;
    // 到视口最远角，圆扩这么大才盖得满
    var far = Math.ceil(Math.max(
      Math.hypot(cx, cy),
      Math.hypot(w - cx, cy),
      Math.hypot(cx, h - cy),
      Math.hypot(w - cx, h - cy)
    ));

    // 连点打断上一发，先收尾避免两层叠着
    if (rippleFinish) { rippleFinish(); rippleFinish = null; }

    document.documentElement.classList.remove('theme-switching');

    var el = document.createElement('div');
    el.className = 'theme-ripple';

    el.style.background = nextMode === 'dark' ? '#000000' : '#f7f7f7';

    el.appendChild(buildClone(nextMode));

    // 页面滚到哪，副本就对齐到哪
    var sx = window.pageXOffset || document.documentElement.scrollLeft || 0;
    var sy = window.pageYOffset || document.documentElement.scrollTop || 0;
    var cl = el.firstChild;
    cl.style.transform = 'translate(' + (-sx) + 'px,' + (-sy) + 'px)';
    cl.style.width = document.documentElement.clientWidth + 'px';

    var bodyH = Math.max(
      document.body.scrollHeight,
      document.documentElement.scrollHeight
    );
    cl.style.minHeight = bodyH + 'px';

    var start = 'circle(0px at ' + cx + 'px ' + cy + 'px)';
    el.style.clipPath = start;
    el.style.webkitClipPath = start;
    el.style.setProperty('--ripple-dur', RIPPLE_MS + 'ms');
    document.body.appendChild(el);

    var done = false;
    var finish = function () {
      if (done) return;
      done = true;

      // 隔一帧撤层：同帧翻主题 + 撤层会排出"旧的没了、新的没画"的中间帧
      applyTheme(nextMode);
      requestAnimationFrame(function () {
        el.remove();
        if (rippleFinish === finish) rippleFinish = null;
        releaseThemeLock();
      });
    };
    rippleFinish = finish;

    el.addEventListener('transitionend', finish, { once: true });

    setTimeout(finish, RIPPLE_MS + 180);

    void el.offsetWidth;
    var end = 'circle(' + far + 'px at ' + cx + 'px ' + cy + 'px)';
    el.style.clipPath = end;
    el.style.webkitClipPath = end;
  }

  function applyTheme(mode) {
    var root = document.documentElement;

    // 关掉全局过渡，否则按钮和圆点会慢慢爬色，看起来像闪
    root.classList.add('theme-switching');

    if (mode === 'auto') {
      root.removeAttribute('data-theme');
    } else {
      root.setAttribute('data-theme', mode);
    }

    var dark = mode === 'dark' || (mode === 'auto' && systemDark());
    var m = document.getElementById('tc');
    if (m) m.setAttribute('content', dark ? '#000000' : '#f7f7f7');

    try {
      if (mode === 'auto') localStorage.removeItem(THEME_KEY);
      else localStorage.setItem(THEME_KEY, mode);
    } catch (e) { }
  }

  function releaseThemeLock() {
    requestAnimationFrame(function () {
      requestAnimationFrame(function () {
        requestAnimationFrame(function () {
          document.documentElement.classList.remove('theme-switching');
        });
      });
    });
  }

  function currentTheme() {
    try {
      var v = localStorage.getItem(THEME_KEY);
      if (v === 'light' || v === 'dark') return v;
    } catch (e) { }
    return 'auto';
  }

  function bindTheme() {
    var btn = $('btnTheme');
    if (!btn) return;

    if (!document.documentElement.hasAttribute('data-theme') && currentTheme() !== 'auto') {
      applyTheme(currentTheme());
    }

    btn.addEventListener('click', function () {
      var isDark = document.documentElement.getAttribute('data-theme') === 'dark' ||
        (document.documentElement.getAttribute('data-theme') !== 'light' && systemDark());
      rippleTheme(btn, isDark ? 'light' : 'dark');
    });
  }

  // ---------------------------------------------------------------- WebUI 宿主
  // 方法名各家不统一，逐个探测：
  //   KernelSU / KsuWebUIStandalone -> ksu.exec
  //   APatch                        -> APatch.exec
  //   MMRL / WebUI X                -> mmrl.exec / $webui.exec
  var HOSTS = ['ksu', 'APatch', 'mmrl', '$webui', 'webuix', 'webui', 'kernelsu', 'magisk'];
  var METHODS = ['exec', 'execCommand', 'shell'];

  function findBridge() {
    for (var i = 0; i < HOSTS.length; i++) {
      var h;
      try { h = window[HOSTS[i]]; } catch (e) { h = null; }
      if (!h) continue;
      for (var j = 0; j < METHODS.length; j++) {
        var fn;
        try { fn = h[METHODS[j]]; } catch (e) { fn = null; }
        if (typeof fn === 'function') {
          return { host: h, fn: fn, name: HOSTS[i] + '.' + METHODS[j] };
        }
      }
    }
    return null;
  }

  var _bridge;

  function bridge() {
    if (_bridge === undefined) _bridge = findBridge();
    return _bridge;
  }

  function normReply(r) {
    if (r === null || r === undefined) return null;
    if (typeof r === 'string') {
      // 有的宿主把结果整个 JSON 成字符串返回
      var s = r.replace(/^\s+/, '');
      if (s.charAt(0) === '{') {
        try {
          var j = JSON.parse(s);
          if (j && typeof j === 'object' &&
              ('stdout' in j || 'errno' in j || 'code' in j || 'stderr' in j)) {
            return normReply(j);
          }
        } catch (e) { }
      }
      return { errno: 0, stdout: r, stderr: '' };
    }
    if (typeof r === 'number') return { errno: r, stdout: '', stderr: '' };
    if (typeof r === 'object') {
      var text = typeof r.stdout === 'string' ? r.stdout
               : typeof r.result === 'string' ? r.result
               : typeof r.output === 'string' ? r.output
               : typeof r.out === 'string' ? r.out : '';
      var code = typeof r.errno === 'number' ? r.errno
               : typeof r.code === 'number' ? r.code
               : typeof r.returnCode === 'number' ? r.returnCode : 0;
      return {
        errno: code,
        stdout: text,
        stderr: typeof r.stderr === 'string' ? r.stderr
              : typeof r.error === 'string' ? r.error : ''
      };
    }
    return null;
  }

  // 宿主接口形态各家不一样，按"最不容易踩坑"的顺序逐个试，并把每一次的
  // 结果记进 state.diag，界面上读不到状态时直接把诊断信息显示出来：
  //   1. exec(cmd)                  —— Promise 版（新版 KernelSU / APatch / MMRL）
  //   2. exec(cmd, cb)              —— 回调版（老版 KernelSU）
  //   3. exec(cmd, {cwd, env})      —— 必须带 opts 的 Promise 版
  //   4. exec(cmd, "回调函数名")     —— 只接受全局函数名字符串的实现
  // 绝不能一上来就把函数当第二参数喂给 Promise 版宿主：它会把函数 JSON 掉，
  // native 拿到 undefined 后永远不回调，界面就卡在"读取失败"。
  var cbSeq = 0;

  function exec(cmd) {
    var b = bridge();
    if (!b) return Promise.resolve({ errno: -1, stdout: '', stderr: 'no webui host', nohost: true });

    var trace = [];
    state.diag = { host: b.name, trace: trace, last: '' };

    return new Promise(function (resolve) {
      var done = false;
      var t0 = Date.now();
      var hard = setTimeout(function () {
        finish({ errno: -1, stdout: '', stderr: 'timeout, all attempts failed' });
      }, 12000);

      function finish(r) {
        if (done) return;
        done = true;
        clearTimeout(hard);
        var n = normReply(r);
        if (!n) n = { errno: -1, stdout: '', stderr: 'unexpected host reply' };
        trace.push('result errno=' + n.errno + ' out=' + ((n.stdout || '').length) + 'B ' + (Date.now() - t0) + 'ms');
        resolve(n);
      }

      function note(step, what) {
        var line = step + ' ' + what;
        trace.push(line);
        state.diag.last = line;
        if (trace.length > 8) trace.shift();
      }

      function callback(a, b2, c) {
        if (typeof a === 'string') {
          var s = a.trim();
          if (s.charAt(0) === '{' || s.charAt(0) === '[') {
            try { return finish(JSON.parse(s)); } catch (e) { }
          }
          return finish({ errno: 0, stdout: a, stderr: typeof b2 === 'string' ? b2 : '' });
        }
        if (a && typeof a === 'object') return finish(a);
        finish({ errno: a, stdout: b2, stderr: c });
      }

      // 1
      var r1;
      try { r1 = b.fn.call(b.host, cmd); } catch (e) { note('1', 'threw'); }
      if (r1 && typeof r1.then === 'function') {
        note('1', 'promise');
        r1.then(finish, function () { note('1', 'rejected'); step2(); });
        return;
      }
      if (r1 !== undefined && r1 !== null) { note('1', 'sync'); return finish(r1); }
      note('1', 'void');

      step2();

      // 2
      function step2() {
        if (done) return;
        var r2;
        try { r2 = b.fn.call(b.host, cmd, callback); } catch (e) { note('2', 'threw'); return step3(); }
        if (r2 && typeof r2.then === 'function') {
          note('2', 'promise');
          r2.then(finish, function () { note('2', 'rejected'); step3(); });
          return;
        }
        if (r2 !== undefined && r2 !== null) { note('2', 'sync'); return finish(r2); }
        note('2', 'waiting');
        setTimeout(function () { if (!done) step3(); }, 1500);
      }

      // 3
      function step3() {
        if (done) return;
        var r3;
        try {
          r3 = b.fn.call(b.host, cmd, {
            cwd: '/',
            env: { PATH: '/system/bin:/system/xbin:/sbin' }
          });
        } catch (e) { note('3', 'threw'); return step4(); }
        if (r3 && typeof r3.then === 'function') {
          note('3', 'promise');
          r3.then(finish, function () { note('3', 'rejected'); step4(); });
          return;
        }
        if (r3 !== undefined && r3 !== null) { note('3', 'sync'); return finish(r3); }
        note('3', 'void');
        step4();
      }

      // 4
      function step4() {
        if (done) return;
        var nm = '__ksu_cb_' + (++cbSeq);
        try { window[nm] = callback; } catch (e) { return; }
        var r4;
        try { r4 = b.fn.call(b.host, cmd, nm); } catch (e) { note('4', 'threw'); return; }
        if (r4 && typeof r4.then === 'function') {
          note('4', 'promise');
          r4.then(finish, function () { note('4', 'rejected'); });
          return;
        }
        if (r4 !== undefined && r4 !== null) { note('4', 'sync'); return finish(r4); }
        note('4', 'waiting');
        setTimeout(function () {
          try { delete window[nm]; } catch (e) { }
        }, 15000);
      }
    });
  }

  function out(r) { return ((r && r.stdout) || '').replace(/\s+$/, ''); }

  var toastTimer = null;
  function toast(msg) {
    var el = document.querySelector('.toast');
    if (!el) {
      el = document.createElement('div');
      el.className = 'toast';
      document.body.appendChild(el);
    }
    el.textContent = msg;
    void el.offsetWidth;
    el.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { el.classList.remove('show'); }, 1900);
  }

  function cfg(key, def) {
    var v = state.cfg[key];
    return (v === undefined || v === '') ? def : v;
  }

  function locked() { return cfg('lock', '0') === '1'; }
  function curProfile() { return locked() ? cfg('profile', 'mtp') : cfg('on_connect', 'mtp'); }
  // 组合里可能带 adb（命令行设的），展示和选中都只看数据功能
  function baseProfile(v) {
    var parts = String(v || '').split(',');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i] && parts[i] !== 'adb') return parts[i];
    }
    return 'none';
  }
  function labelOf(v) {
    var b = baseProfile(v);
    var n = b;
    PROFILES.forEach(function (p) { if (p.v === b) n = p.t; });
    return n;
  }

  function parseState(text) {
    var o = {};
    // 兼容两种格式：一行一个 key=value，或者单行 key=value;key=value
    String(text || '').split(/[\r\n;]+/).forEach(function (line) {
      var i = line.indexOf('=');
      if (i <= 0) return;
      o[line.slice(0, i)] = line.slice(i + 1);
    });
    return o;
  }

  function fetchState() {
    return exec(CTL + ' state').then(function (r) {
      var text = out(r);
      var o = parseState(text);
      if (!text || o.enabled === undefined || o.daemon === undefined) {
        state.fail = (r && r.stderr) || text || '模块未响应';
        return false;
      }
      state.fail = '';
      state.cfg = o;
      return true;
    });
  }

  // ---------------------------------------------------------------- 渲染

  function paintEnable() {
    var row = $('rowEnable');
    if (!row) return;
    var en = cfg('enabled', '0') === '1';
    var pid = cfg('daemon', '0');
    var running = !!pid && pid !== '0';
    row.className = 'row switch' + (en ? ' on' : '');
    row.setAttribute('aria-checked', en ? 'true' : 'false');
    $('enableSub').textContent = en
      ? (running ? '已启用，开机自动运行' : '已启用，守护进程没在跑')
      : '已停用，点一下重新启用';
  }

  function paintStatus() {
    var usb = cfg('usb', '');
    var map = { configured: '已连接', powered: '仅供电', 'not attached': '未连接' };
    var el = $('stUsb');
    if (el) {
      el.textContent = map[usb] || (usb || '未知');
      el.className = 'v' + (usb === 'configured' ? ' ok' : '');
    }

    var fn = cfg('functions', '');
    var fe = $('stFunc');
    if (fe) fe.textContent = (fn && fn !== 'none') ? fn : '—';

    var pid = cfg('daemon', '0');
    var running = !!pid && pid !== '0';
    var de = $('stDaemon');
    if (de) {
      de.textContent = running ? '运行中' : '已停止';
      de.className = 'v' + (running ? ' ok' : ' warn');
    }

    var chip = $('chipState');
    var uid = state.cfg.uid;
    var dirOk = cfg('dir', '1') !== '0';
    state.noRoot = (uid !== undefined && uid !== '' && uid !== '0');
    state.noDir = !dirOk;
    if (document.body && document.body.classList) {
      if (state.noRoot || !dirOk) document.body.classList.add('noroot');
      else document.body.classList.remove('noroot');
    }
    if (chip) {
      if (!dirOk) {
        chip.textContent = '未安装';
        chip.className = 'chip warn';
      } else if (state.noRoot) {
        chip.textContent = '需要 Root';
        chip.className = 'chip warn';
      } else if (cfg('enabled', '0') !== '1') {
        chip.textContent = '已停用';
        chip.className = 'chip warn';
      } else if (!running) {
        chip.textContent = '未运行';
        chip.className = 'chip warn';
      } else if (locked()) {
        chip.textContent = labelOf(curProfile());
        chip.className = 'chip on';
      } else {
        chip.textContent = '自动';
        chip.className = 'chip on';
      }
    }

    var hint = $('hintLine');
    if (hint) {
      if (!dirOk) hint.textContent = '模块目录不存在（/data/adb/modules/autousb）：安装完要重启一次才生效';
      else if (state.noRoot) hint.textContent = 'WebUI 当前以 uid=' + uid + ' 运行，没有 root 权限，读不到也改不了模块状态';
      else if (cfg('enabled', '0') !== '1') hint.textContent = '模块已停用，守护进程不会运行，插线不会自动切换';
      else if (!running) hint.textContent = '守护进程没在跑：新装的话重启一次；否则把上面的开关关掉再打开';
      else hint.textContent = '';
      hint.style.display = hint.textContent ? '' : 'none';
    }

    var v = $('verLine');
    if (v) {
      v.textContent = 'autousb ' + cfg('version', '') +
        ' · ' + (locked() ? '锁定 · ' + labelOf(curProfile()) : '自动 · ' + labelOf(curProfile()));
    }
  }

  function makeRow(title, sub, selected) {
    var row = document.createElement('div');
    row.className = 'row radio' + (selected ? ' selected' : '');
    row.setAttribute('role', 'radio');
    row.setAttribute('aria-checked', selected ? 'true' : 'false');

    var main = document.createElement('span');
    main.className = 'row-main';
    var t = document.createElement('span');
    t.className = 'row-title';
    t.textContent = title;
    var s = document.createElement('span');
    s.className = 'row-sub';
    s.textContent = sub;
    main.appendChild(t);
    main.appendChild(s);

    var tick = document.createElement('span');
    tick.className = 'tick';

    row.appendChild(main);
    row.appendChild(tick);
    return row;
  }

  function paint() {
    var host = $('profileList');
    if (!host) return;

    var cur = curProfile();
    var auto = !locked();

    host.innerHTML = '';

    var autoRow = makeRow('自动模式', '插线时套用一次，允许系统改回', auto);
    autoRow.addEventListener('click', function () {
      if (state.readonly || state.busy || auto) return;
      run(CTL + ' auto', '已切到自动模式');
    });
    host.appendChild(autoRow);

    PROFILES.forEach(function (p) {
      var r = makeRow(p.t, p.s, !auto && p.v === baseProfile(cur));
      r.addEventListener('click', function () {
        if (state.readonly || state.busy) return;
        if (!auto && p.v === baseProfile(cur)) return;
        run(CTL + ' lock on ' + p.v, '已锁定 ' + p.t);
      });
      host.appendChild(r);
    });
  }

  function paintAll() {
    paintEnable();
    paintStatus();
    var key = [cfg('lock', ''), cfg('profile', ''), cfg('on_connect', '')].join('|');
    if (key !== state.paintKey) {
      state.paintKey = key;
      paint();
    }
  }

  function paintError() {
    var chip = $('chipState');
    if (chip) { chip.textContent = '读取失败'; chip.className = 'chip warn'; }
    // 不要把上一次的"已停用/已启用"留在界面上
    var row = $('rowEnable');
    if (row) {
      row.className = 'row switch';
      row.setAttribute('aria-checked', 'false');
    }
    var sub = $('enableSub');
    if (sub) sub.textContent = '状态未知（读取失败）';
    var hint = $('hintLine');
    if (hint) {
      var d = state.diag;
      var detail = d ? ('宿主 ' + d.host + ' · ' + (d.trace || []).join(' / ')) : '';
      hint.textContent = '读不到模块状态：' + (state.fail || '未知错误') +
        (detail ? '（' + detail + ' · ' + BUILD + '）' : '') +
        '。请确认模块已安装并在管理器里启用。';
      hint.style.display = '';
    }
    var de = $('stDaemon');
    if (de) { de.textContent = '—'; de.className = 'v'; }
    var v = $('verLine');
    if (v) v.textContent = 'autousb · 状态未知';
  }

  function refresh() {
    return fetchState().then(function (ok) {
      if (!ok) { paintError(); return false; }
      paintAll();
      return true;
    });
  }

  function run(cmd, okMsg) {
    if (state.busy || state.readonly || state.noRoot || state.noDir) return Promise.resolve();
    state.busy = true;
    document.body.classList.add('busy');
    return exec(cmd).then(function (r) {
      var text = out(r);
      if (r.errno !== 0 || /^(ERROR|usage|unknown|invalid|sh:)/.test(text)) {
        toast(text || '执行失败');
      } else if (okMsg) {
        toast(okMsg);
      }
      return refresh();
    }).catch(function (e) {
      toast(String(e));
    }).then(function () {
      state.busy = false;
      document.body.classList.remove('busy');
    });
  }

  function tick() {
    if (state.readonly || state.busy || state.pending) return;
    state.pending = true;
    refresh().then(function () { state.pending = false; },
                   function () { state.pending = false; });
  }

  function readonlyMode() {
    state.readonly = true;
    document.body.classList.add('readonly');
    var chip = $('chipState');
    if (chip) { chip.textContent = '无宿主'; chip.className = 'chip warn'; }
    var hint = $('hintLine');
    if (hint) {
      hint.textContent = '这个页面没有 WebUI 执行接口：请在 KernelSU / APatch / MMRL 里打开模块的 WebUI，直接用浏览器打开只能看、不能改。';
      hint.style.display = '';
    }
    var v = $('verLine');
    if (v) v.textContent = 'autousb · 只读';
    var sub = $('enableSub');
    if (sub) sub.textContent = '需要 WebUI 宿主';
    ['stUsb', 'stFunc', 'stDaemon'].forEach(function (id) {
      var el = $(id);
      if (el) { el.textContent = '—'; el.className = 'v'; }
    });
  }

  function bindEnable() {
    var row = $('rowEnable');
    if (!row) return;
    function toggle() {
      if (state.readonly || state.busy) return;
      var en = cfg('enabled', '0') === '1';
      run(CTL + (en ? ' off' : ' on'), en ? '已停用' : '已启用');
    }
    row.addEventListener('click', toggle);
    row.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); toggle(); }
    });
  }

  function start() {
    refresh().then(function () {
      setInterval(tick, 5000);
    }).catch(function () {
      paintError();
      setInterval(tick, 5000);
    });
  }

  function boot() {
    bindTheme();
    bindEnable();

    if (bridge()) {
      start();
      return;
    }

    // 有的宿主把 JS 接口注入得比脚本执行晚一点，等一下再探一次
    setTimeout(function () {
      _bridge = undefined;
      if (bridge()) {
        state.readonly = false;
        document.body.classList.remove('readonly');
        start();
        return;
      }
      readonlyMode();
    }, 600);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
