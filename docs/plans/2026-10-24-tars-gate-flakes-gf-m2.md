# GF-M2 — 커널 printk가 자른 `terminal:` 줄을 읽는 쪽이 잇는다

Date: 2026-10-24
Design: `docs/specs/2026-10-24-tars-gate-flakes-design.md` 결정 8
Status: 끝났다(2026-10-24). 루트 게이트 22/22(M1과 함께). 값은 맨 아래 "GF-M2가 실측한 것".

## 누가 무엇을 하나

lead가 직접 넣는다. 함수 하나, 진입 검사 조각 둘, 그리고 8체인 119자리의 기계적 치환.

| 파일 | 무엇을 |
|---|---|
| `gate_lib.sh` | `tlog` 새 함수. `joined_screen_dump`를 `tlog` 위에 다시 쓴다 |
| `check.sh` | `require_screen_dump_joins`에 조각 둘(꼬리에서 잘린 `pointer> at` · 커널 조각의 재출력) |
| copy · pointer · hangul · render · pane · dictation · config · battery의 `check.sh` | `grep -a[E] 'terminal: …' "$LOG"` → `tlog \| grep -a[E] 'terminal: …'` |

## 착수 전에 확정한 것

1. 로그에 남는 자름의 두 모양(GF-M1 게이트의 PD 로그 · AU-M2의 lessons).
   - 꼬리: `terminal: pointer> at … ink=118[   12.315317] random: crng init done\r\n` 다음 줄이 terminal의 `\r\n`(빈 줄). 이은 결과는
     `… ink=118\r\n`.
   - 가운데: `terminal: screen> … | fzf[   7.359211] random: crng init done\r\n-history-widget | …\r\n`. 이은 결과는 자름 없는 줄.
   - 그 사이에 온전한 `tars-init:` 줄이 올 수 있다(AL-M1 뒤로 init의 줄은 안 잘리고 끼어들기만 한다) — 건너뛴다.
2. 뗀 커널 조각(`[   12.315317] random: crng init done`)은 이은 줄 바로 뒤에 제 줄로 낸다. pointer의 `kernel_mice`가
   `input: QEMU QEMU USB Mouse as`를 세는데 그 printk가 terminal 줄을 자른 조각일 수 있다.
3. `joined_screen_dump`의 지금 출력 — `screen>`이 든 줄만, 앞에 붙은 콘솔 조각을 떼고, `\r`은 그대로. `tlog | grep -a 'terminal: screen>' | from_terminal`이
   같은 글자를 낸다. 진입 검사의 조각 넷(clean · printk · printk_init · console)과 `text`(화면 글자로 `tars-init:`이 끝에 있는 줄)가 그것을
   지킨다.
4. 치환 대상은 `grep -a` 또는 `grep -aE` 바로 뒤에 `'terminal: `으로 시작하는 작은따옴표 패턴이 오고 그 뒤가 `"$LOG"`인 자리다. `-q` ·
   `-c`가 든 자리(28)는 바꾸지 않는다. `<<<"$(grep -a 'terminal: screen>' "$LOG")"` 같은 안쪽 치환도 같은 모양이라 함께 바뀐다.
5. 22체인이 전부 `gate_lib.sh`를 source한다 — `tlog`는 어디서든 보인다.

## Task 1: `gate_lib.sh`

`joined_screen_dump` 자리에:

```bash
# 시리얼 로그를 커널 자름을 이어 찍는다(GF-M2 결정 8). …
tlog() {
  perl -ne '
    if (defined $cur) {
      next if /^tars-init: /;                       # 사이에 끼어든 온전한 init 줄
      if (/^(terminal|kms): / || /terminal: screen>/) { print $cur, "\n", $frag; undef $cur; redo }
      $cur .= $_;                                   # 잘린 나머지(빈 줄일 수 있다)
    } elsif (/terminal: / || /^kms: /) { $cur = $_ } else { print; next }
    if ($cur =~ s/(\[ *\d+\.\d+\] [^\r\n]*)\r?\n\z//) { $frag = "$1\n"; next }   # 커널이 꼬리를 잘랐다 — 다음 줄을 기다린다
    print $cur, $frag; undef $cur; $frag = "";
    END { print $cur, "\n", $frag if defined $cur }
  ' "$LOG"
}

joined_screen_dump() {
  tlog | grep -a 'terminal: screen>' | from_terminal
}
```

주석에 적을 것 — 왜 `screen>`만이 아니라 전부인가(GF-M1 게이트의 PD · 여섯 체인), 왜 커널 조각을 다시 내는가(확정 2), 왜 `-q`는
안 거치는가(SIGPIPE).

## Task 2: `check.sh` 진입 검사

`require_screen_dump_joins`에 둘을 더한다. `tail_cut` — `printf 'terminal: pointer> at x=679 y=499 buttons=0 wheel=0 shown=1 ink=118[   12.315317] random: crng init done\r\n\r\n'`을
`tlog`로 읽어 `terminal: pointer> at … ink=118\r` 한 줄과 `[   12.315317] random: crng init done` 한 줄이 그 순서로 나온다.
`frag_kept` — 위 `printk` 조각을 `tlog`로 읽어 `random: crng init done` 줄이 하나 있다.

## Task 3: 8체인의 치환

```bash
sd "grep -a(E?) +'terminal: ([^']*)' +\"\\\$LOG\"" 'tlog | grep -a$1 '"'"'terminal: $2'"'" copy/check.sh …
```

치환 뒤 `rg -n "grep -a[E]* +'terminal: [^']*' +\"\\\$LOG\"" */check.sh`가 0줄, `rg -c 'tlog \| grep' */check.sh`의 합이 119.
`bash -n` 여덟, `shellcheck -S warning` 여덟.

## Task 4: 검사와 게이트

1. GF-M1 게이트의 PD 로그로 — `LOG=out/gate-logs/20261024-094856/PD-M4-1/tmp.* bash -c 'source gate_lib.sh; tlog' | grep -a 'pointer> at' | tail -n 1`이
   `… ink=118`로 끝난다. 같은 로그의 `crng init done` 줄 수가 raw와 같다.
2. 진입 검사만 — 루트 `check.sh`는 진입 검사를 prebuild 앞에서 돌리므로 루트 게이트를 띄우면 몇 초 안에 알 수 있다.
3. `make check CHAIN=pointer` — 치환이 가장 많은 체인 하나.
4. 루트 게이트(22체인, 약 10분). M1과 함께 닫는다.

## 끝 조건

- Task 4의 1 · 2, 루트 게이트 22/22.

## 닫을 때(lead의 몫)

design "닫을 때" 절 그대로. lessons의 AU-M2 절("커널 printk가 terminal의 화면 줄을 가운데서 자른다")에 "GF-M2부터 `tlog`가 모든
terminal 줄을 잇고 직접 읽는 자리 119곳이 그것을 거친다"를 덧붙인다.

## GF-M2가 실측한 것

| 항목 | 값 |
|---|---|
| 치환 | 8체인 119곳, `grep -a[E] 'terminal: …' "$LOG"` → `tlog \| grep …`. `-q` · `-c` 61곳은 그대로 |
| 진입 검사 | 조각 넷 + `text` + 새 둘(`tail_cut` · 커널 조각 재출력) 통과 |
| GF-M1 게이트의 PD 로그(985KB)로 | `tlog`의 마지막 at 줄이 `… ink=118`로 끝난다. `crng init done` 1 → 1, `input: QEMU` 2 → 2, 줄 수 1662 → 1662 |
| 새 `joined_screen_dump` 대 옛 것 | GF-M1 게이트의 실제 로그 55개에서 바이트까지 같다 |
| `tlog \| grep \| tail -n 1` 한 번 | 24ms (raw `grep` 8ms, 985KB 로그) |
| `make check CHAIN=pointer` 1판 | 빨강 — 검사 28 `probe_result`가 ''를 읽었다(아래). 고친 뒤 76초 PASS |
| 루트 게이트(M1 · M2를 닫는 판) | 22/22. prebuild 244초 · lanes 289초 · `time: logs 0s`. 트리 144MB · 로그 58 |
| 그 판에서 커널 printk가 자른 terminal 줄 | 로그 8개(CB 1 · CP 부팅 넷 각 1 · IP 1 · TR 1 · UT 1) — 전부 초록 |

pointer의 빨강은 `tlog`가 글자를 바꾼 것이 아니라 읽기가 느려져 드러난 옛 경합이다. `probe_result`가 "결과 행이 보일 때까지 기다린 뒤
마지막 `screen>` 줄"을 읽는데, 기다림이 끝나고 읽기까지 사이에 다음 프레임이 쓰이기 시작하면 마지막 줄은 결과 행이 아직 없는 부분
줄이다. 읽기가 8ms에서 24ms로 늘어 그 창이 넓어졌다. "표지가 든 마지막 `screen>` 줄"을 읽게 고쳤다 — 새 읽기를 쓸 때는 기다린 글자가
든 줄을 읽는다(lessons AU-M2 절 덧붙임).
