
(function () {
  'use strict';

  var MOD  = '/data/adb/modules/autousb';
  var CTL  = 'sh ' + MOD + '/bin/autousbctl';
  var CONF = MOD + '/config/autousb.conf';

  var PROFILES = [
    { v: 'mtp',   t: 'MTP',      s: '文件传输，传照片和文件' },
    { v: 'ptp',   t: 'PTP',      s: '相机协议，导入照片' },
    { v: 'rndis', t: 'USB 网卡',  s: '把网络共享给电脑' },
    { v: 'midi',  t: 'MIDI',     s: '连接乐器设备' },
    { v: 'none',  t: '仅充电',    s: '不向主机暴露任何功能' }
  ];

  var $ = function (id) { return document.getElementById(id); };
  var state = { cfg: {}, readonly: false, busy: false };

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

      // 隔一帧撤层：同帧翻主题+撤层会排出"旧没了新没画"的中间帧
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

    // 关掉全局过渡，否则按钮/圆点会慢慢爬色，看起来像闪
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
    } catch (e) {  }
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
    } catch (e) {  }
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

  // WebUI 宿主。方法名各家不统一，逐个探测：
  //   KernelSU / KsuWebUIStandalone -> ksu.exec
  //   APatch                        -> APatch.exec
  //   MMRL                          -> mmrl.exec / mmrl.execCommand
  var HOSTS = ['ksu', 'APatch', 'mmrl', 'webui', 'magisk'];
  var METHODS = ['exec', 'execCommand', 'shell'];

  function findBridge() {
    for (var i = 0; i < HOSTS.length; i++) {
      var h = window[HOSTS[i]];
      if (!h) continue;
      for (var j = 0; j < METHODS.length; j++) {
        if (typeof h[METHODS[j]] === 'function') {
          return { host: h, fn: h[METHODS[j]], name: HOSTS[i] + '.' + METHODS[j] };
        }
      }
    }
    return null;
  }

  var _bridge = undefined;   // undefined = 还没探测

  function bridge() {
    if (_bridge === undefined) _bridge = findBridge();
    return _bridge;
  }

  function sh(cmd) {
    var b = bridge();
    if (!b) {
      return Promise.resolve({ errno: -1, stdout: '', stderr: 'no bridge' });
    }
    var call;
    try {
      call = b.fn.call(b.host, cmd, {
        cwd: '/',
        env: { PATH: '/system/bin:/system/xbin:/data/adb/ksu/bin:/data/adb/ap/bin' }
      });
    } catch (e) {
      // 有的宿主第二参数不认对象，退回只传命令
      try { call = b.fn.call(b.host, cmd); }
      catch (e2) { return Promise.resolve({ errno: -1, stdout: '', stderr: String(e2) }); }
    }
    return Promise.resolve(call).then(function (r) {
      if (typeof r === 'string') return { errno: 0, stdout: r, stderr: '' };
      if (r && typeof r.stdout === 'string') return r;
      if (r && typeof r.result === 'string') return { errno: 0, stdout: r.result, stderr: '' };
      return { errno: -1, stdout: '', stderr: 'unexpected bridge reply' };
    }).catch(function (e) {
      return { errno: -1, stdout: '', stderr: String(e) };
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
    toastTimer = setTimeout(function () { el.classList.remove('show'); }, 1600);
  }

  function parseConf(text) {
    var o = {};
    String(text || '').split(/\r?\n/).forEach(function (line) {
      if (!line || line.charAt(0) === '#') return;
      var i = line.indexOf('=');
      if (i < 0) return;
      var k = line.slice(0, i).trim();
      var v = line.slice(i + 1).replace(/\s*#.*$/, '').trim();
      if (k) o[k] = v;
    });
    return o;
  }

  function readConfig() {
    return sh('cat ' + CONF + ' 2>/dev/null').then(function (r) {
      state.cfg = parseConf(out(r));
      return state.cfg;
    });
  }

  function refresh() {
    return readConfig().then(paint).then(tick);
  }

  function currentProfile() {
    if (state.cfg.LOCK_ENABLED === '1') return state.cfg.LOCK_PROFILE || 'mtp';
    return state.cfg.ON_CONNECT || 'mtp';
  }

  function paint() {
    var host = $('profileList');
    var cur = currentProfile();

    host.innerHTML = '';
    PROFILES.forEach(function (p) {
      var row = document.createElement('div');
      row.className = 'row radio' + (p.v === cur ? ' selected' : '');
      row.innerHTML =
        '<span class="row-main">' +
          '<span class="row-title">' + p.t + '</span>' +
          '<span class="row-sub">' + p.s + '</span>' +
        '</span>' +
        '<span class="tick"></span>';

      row.addEventListener('click', function () {
        if (state.readonly || state.busy || p.v === cur) return;
        state.busy = true;

        sh(CTL + ' lock on ' + p.v).then(refresh).then(function () {
          toast('已锁定 ' + p.t);
        }).then(function () { state.busy = false; });
      });

      host.appendChild(row);
    });

    var name = cur;
    PROFILES.forEach(function (q) { if (q.v === cur) name = q.t; });
    $('verLine').textContent = 'autousb · ' + name;
  }

  function tick() {
    return Promise.all([
      sh('cat /sys/class/udc/*/state 2>/dev/null | head -n1'),
      sh('svc usb getFunctions 2>/dev/null'),
      sh('P=$(cat ' + MOD + '/run/daemon.pid 2>/dev/null); ' +
         '[ -n "$P" ] && kill -0 "$P" 2>/dev/null && echo running || echo stopped'),
      sh('test -f ' + MOD + '/disable && echo off || echo on')
    ]).then(function (r) {
      var st = (out(r[0]) || '').trim();
      var map = { configured: '已连接', powered: '仅供电', 'not attached': '未连接' };
      var el = $('stUsb');
      if (el) {
        el.textContent = map[st] || (st || '未知');
        el.className = 'v' + (st === 'configured' ? ' ok' : '');
      }

      var fn = (out(r[1]) || '').trim();
      var fe = $('stFunc');
      if (fe) fe.textContent = (fn && fn !== 'none') ? fn : '—';

      var dm = (out(r[2]) || '').trim();
      var de = $('stDaemon');
      if (de) {
        de.textContent = dm === 'running' ? '运行中' : '已停止';
        de.className = 'v' + (dm === 'running' ? ' ok' : ' warn');
      }

      var chip = $('chipState');
      if (chip) {
        if ((out(r[3]) || '').trim() !== 'on') {
          chip.textContent = '已停用';
          chip.className = 'chip warn';
        } else {
          chip.textContent = currentProfile();
          chip.className = 'chip on';
        }
      }
    });
  }

  function readonlyMode() {
    state.readonly = true;

    var chip = $('chipState');
    if (chip) { chip.textContent = '无宿主'; chip.className = 'chip warn'; }

    Array.prototype.forEach.call(document.querySelectorAll('button'), function (el) {
      if (el.id === 'btnTheme') return;
      el.disabled = true;
    });

    var v = $('verLine');
    if (v) v.textContent = 'autousb · 需要 WebUI 宿主';
  }

  function boot() {
    bindTheme();

    if (!bridge()) {
      readonlyMode();
      tick();
      return;
    }

    readConfig().then(function () {
      paint();
      tick();
      setInterval(tick, 5000);
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
