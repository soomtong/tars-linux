// 페이지의 움직이는 부분. 내용은 전부 data.js(window.TARS)에서 온다 —
// 새 기능을 더할 때 이 파일은 손대지 않는다.
(() => {
  const D = window.TARS;
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const $ = id => document.getElementById(id);

  // 요소 하나. children은 문자열(텍스트 노드)이나 노드.
  const h = (tag, cls, ...children) => {
    const el = document.createElement(tag);
    if (cls) el.className = cls;
    for (const c of children) if (c != null) el.append(c);
    return el;
  };

  // 작은 표기: `코드` → <code>, [키] → <kbd>. 나머지는 텍스트 그대로.
  // needle이 있으면 텍스트 안의 일치를 <mark>로 감싼다.
  const rich = (s, needle) => {
    const frag = document.createDocumentFragment();
    const text = (t, wrap) => {
      const node = wrap ? document.createElement(wrap) : frag;
      if (!needle) node.append(t);
      else {
        const low = t.toLowerCase(); let i = 0, j;
        while ((j = low.indexOf(needle, i)) >= 0) {
          node.append(t.slice(i, j), h('mark', null, t.slice(j, j + needle.length)));
          i = j + needle.length;
        }
        node.append(t.slice(i));
      }
      if (wrap) frag.append(node);
    };
    let at = 0;
    for (const m of s.matchAll(/`([^`]+)`|\[([^\]]+\]?)\]/g)) {
      if (m.index > at) text(s.slice(at, m.index));
      text(m[1] ?? m[2], m[1] != null ? 'code' : 'kbd');
      at = m.index + m[0].length;
    }
    if (at < s.length) text(s.slice(at));
    return frag;
  };

  // 기준일에서 며칠 안에 끝난 것이 NEW다.
  const day = s => Date.parse(s + 'T00:00:00Z');
  const isNew = since => since && (day(D.asOf) - day(since)) / 864e5 <= D.newWithinDays;

  // ── hero ───────────────────────────────────────────────────────────
  $('asof').textContent = '기준 ' + D.asOf + ' · 마지막으로 끝난 것 ' + D.latest;

  // ── 다운로드 — releases의 맨 끝이 최신이다 ──────────────────────────
  {
    const [date, ver, , iso, sha] = D.releases[D.releases.length - 1];
    // 주소를 U로 뺀다 — 그대로 쓰면 pre 칸(약 64자)을 넘어 잘린다.
    const base = 'github.com/soomtong/tars-linux/releases/download/v' + ver;
    const dl = $('dl');
    dl.href = 'https://github.com/soomtong/tars-linux/releases/tag/v' + ver;
    dl.textContent = 'ISO 받기 · ' + ver;
    $('dlHead').textContent = '받아서 띄우기 — ' + ver + ' (' + date + ')';
    // pre 한 줄: [명령, 주석]. 명령이 비면 주석만 있는 줄이다.
    const pre = (el, lines) => lines.forEach(([cmd, c], k) => {
      if (k) el.append('\n');
      if (cmd) el.append(h('span', 'p', '$'), ' ' + cmd);
      if (c) el.append(h('span', 'c', (cmd ? '  ' : '') + '# ' + c));
    });
    pre($('dlRun'), [
      ['U=' + base],
      ['curl -LO https://$U/' + iso],
      ['curl -LO https://$U/SHA256SUMS'],
      ['shasum -a 256 -c SHA256SUMS', 'sha256 ' + sha.slice(0, 12) + '…'],
      ['qemu-system-x86_64 -m 1024 -cdrom ' + iso],
    ]);
    pre($('dlUsb'), [
      [null, 'macOS — <N>은 diskutil list로 확인한 USB 번호'],
      ['diskutil unmountDisk /dev/disk<N>'],
      ['sudo dd if=' + iso + ' of=/dev/rdisk<N> bs=4m'],
      [null, ''],
      [null, 'USB로 뜬 뒤 내장 디스크에 깔기 (UEFI)'],
      ['tars-install <디스크>'],
    ]);
  }

  {
    const acro = $('acro');
    const words = ['Terminal', 'Architecture for', 'Rendering', '&', 'Shell'];
    const draw = upto => {
      acro.textContent = '';
      let n = 0;
      words.forEach((w, k) => {
        if (n >= upto) return;
        const part = w.slice(0, upto - n);
        if (k) acro.append(' ');
        if (/^[A-Z]/.test(w) && part) acro.append(h('b', null, part[0]), part.slice(1));
        else acro.append(part);
        n += w.length + 1;
      });
      acro.append(h('span', 'caret'));
    };
    const total = words.join(' ').length;
    if (reduce) draw(total);
    else { let i = 0; const tick = () => { draw(++i); if (i < total) setTimeout(tick, 38 + Math.random() * 50); }; setTimeout(tick, 500); }
  }

  // ── 나타나기 · 영상 ─────────────────────────────────────────────────
  const io = new IntersectionObserver(es => es.forEach(e => {
    if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
  }), { threshold: 0.12 });

  const vio = new IntersectionObserver(es => es.forEach(e => {
    const v = e.target;
    if (e.isIntersecting) {
      if (!v.getAttribute('src') && v.dataset.src) v.src = v.dataset.src;
      if (!reduce) v.play().catch(() => {});
    } else v.pause();
  }), { threshold: 0.35 });
  document.querySelectorAll('video').forEach(v => vio.observe(v));

  // ── 부팅 사슬 ──────────────────────────────────────────────────────
  {
    const nodes = [...document.querySelectorAll('#chainNodes .node')];
    const serial = $('serial');
    let running = false;
    const run = () => {
      if (running) return; running = true;
      let k = 0;
      const step = () => {
        if (k >= D.serial.length) {
          setTimeout(() => { nodes.forEach(n => n.classList.remove('lit')); serial.textContent = ''; running = false; run(); }, 4200);
          return;
        }
        const [stage, who, msg] = D.serial[k++];
        nodes.forEach((n, j) => n.classList.toggle('lit', j === stage));
        serial.append(h('div', 'ln', h('b', null, who), msg));
        while (serial.children.length > 6) serial.firstChild.remove();
        setTimeout(step, reduce ? 0 : 620);
      };
      step();
    };
    new IntersectionObserver(es => es.forEach(e => e.isIntersecting && run()), { threshold: 0.3 }).observe($('chainNodes'));
  }

  // ── 숫자 ───────────────────────────────────────────────────────────
  {
    const box = $('stats');
    const stats = [
      [D.stats.commits, '', '커밋 (' + D.stats.since + '부터)'],
      [D.timeline.length, '', '끝낸 서브프로젝트'],
      [D.stats.chains, '체인', 'QEMU 게이트 — milestone마다 전부'],
      [D.stats.zigKLines, 'k줄', 'Zig — init · terminal · tars-config'],
    ];
    for (const [v, unit, label] of stats) {
      const num = h('span', null, '0'); num.dataset.count = v;
      box.append(h('div', 'stat', h('div', 'v', num, unit ? h('small', null, unit) : null), h('div', 'l', label)));
    }
    const sio = new IntersectionObserver(es => es.forEach(e => {
      if (!e.isIntersecting) return;
      sio.unobserve(e.target);
      e.target.querySelectorAll('[data-count]').forEach(el => {
        const to = +el.dataset.count, t0 = performance.now(), dur = reduce ? 1 : 1400;
        const f = t => { const p = Math.min(1, (t - t0) / dur); el.textContent = Math.round(to * (1 - Math.pow(1 - p, 3))); if (p < 1) requestAnimationFrame(f); };
        requestAnimationFrame(f);
      });
    }), { threshold: 0.4 });
    sio.observe(box);
  }

  // ── 작업 내역 ──────────────────────────────────────────────────────
  // 릴리스는 서브프로젝트와 섞어 그린다. 같은 날이면 릴리스가 위다 —
  // 그날 끝난 것까지 담아 찍은 것이기 때문이다.
  {
    const tl = $('tl'), more = $('more');
    const tio = new IntersectionObserver(es => es.forEach(e => e.isIntersecting && e.target.classList.add('in')), { threshold: 0.6 });
    const rows = [
      ...D.timeline.map(([date, name, id, what]) => ({ date, name, id, what })),
      ...D.releases.map(([date, ver, what]) => ({ date, name: 'TARS ' + ver, id: 'v' + ver, what, rel: true })),
    ];
    rows.sort((a, b) => b.date.localeCompare(a.date) || (b.rel ? 1 : 0) - (a.rel ? 1 : 0));
    rows.forEach(({ date, name, id, what, rel }) => {
      const nm = h('div', 'name', name, h('span', 'id', id));
      if (rel) nm.append(h('span', 'new rel', 'RELEASE'));
      else if (isNew(date)) nm.append(h('span', 'new', 'NEW'));
      const it = h('div', 'it' + (rel ? ' rel' : ''), h('div', 'date', date), h('div', null, nm, h('div', 'what', rich(what))));
      tl.append(it); tio.observe(it);
    });
    const label = () => { more.textContent = tl.classList.contains('collapsed') ? '전부 보기 (' + rows.length + ')' : '접기'; };
    more.onclick = () => { tl.classList.toggle('collapsed'); label(); };
    label();
  }

  // ── 전체 기능 ──────────────────────────────────────────────────────
  {
    const list = $('flist'), q = $('fq'), onlyNew = $('fnew'), count = $('fcount');
    const all = D.features.reduce((n, g) => n + g.items.length, 0);
    $('featLead').textContent = '기준 ' + D.asOf + '에 TARS가 할 수 있는 것 전부, ' + D.features.length + '갈래 ' + all +
      '개. 오른쪽 날짜는 그 기능이 끝난 날이고, 기준일에서 ' + D.newWithinDays + '일 안의 것에는 NEW가 붙는다.';
    const draw = () => {
      const needle = q.value.trim().toLowerCase();
      list.textContent = '';
      let shown = 0;
      for (const g of D.features) {
        const rows = g.items.filter(([k, d, since]) =>
          (!onlyNew.checked || isNew(since)) &&
          (!needle || (g.title + ' ' + k + ' ' + d).toLowerCase().includes(needle)));
        if (!rows.length) continue;
        shown += rows.length;
        const tb = h('tbody');
        for (const [k, d, since] of rows) {
          const kc = h('td', 'k', rich(k, needle));
          if (isNew(since)) kc.append(h('span', 'new', 'NEW'));
          tb.append(h('tr', null, kc, h('td', 'd', rich(d, needle)), h('td', 's', since || '')));
        }
        list.append(h('div', 'fgroup',
          h('h3', null, rich(g.title), h('span', 'n', String(rows.length))),
          g.note ? h('p', null, rich(g.note)) : null,
          h('table', 'ftable', tb)));
      }
      count.textContent = shown + ' / ' + all;
    };
    q.addEventListener('input', draw);
    onlyNew.addEventListener('change', draw);
    draw();
  }

  document.querySelectorAll('.reveal').forEach(el => io.observe(el));

  // ── 상태 줄 — 지나가는 절에 따라 바뀐다 ─────────────────────────────
  {
    const lang = $('stLang'), copy = $('stCopy'), sec = $('stSec');
    const secs = [['top', '00'], ['chain', '01'], ['screens', '02'], ['why', '03'], ['log', '04'], ['run', '05'], ['features', '06']];
    const onScroll = () => {
      let cur = '00';
      for (const [id, n] of secs) { const el = $(id); if (el && el.getBoundingClientRect().top < innerHeight * 0.4) cur = n; }
      sec.textContent = cur;
      lang.textContent = cur === '02' ? '한' : 'EN';
      copy.classList.toggle('on', cur === '04');
    };
    addEventListener('scroll', onScroll, { passive: true }); onScroll();
  }
})();
