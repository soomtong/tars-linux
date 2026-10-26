# TARS Lean Initrd — Design

Date: 2026-10-26
Status: 끝났다 — LI-M0(실측) · LI-M1(2026-10-26, 루트 게이트 22/22). plan은 `docs/plans/2026-10-26-tars-lean-initrd-li-m0.md` · `-li-m1.md`. 기억은 `docs/decisions/project_lean_initrd.md`.

HANDOFF "다음 후보"의 "terminal 바이너리의 디버그 섹션" 항목에서 시작한다(사용자가 2026-10-26에 골랐다).

> 0.17에서 15.2MB 가운데 `.debug_*`가 12.0MB(`.debug_loc` 5.8MB)이고 `make_initrd.sh:154`가 strip을 안 해 initrd에 그대로
> 실린다(ZU design 실측 9). `strip --strip-debug`(심볼은 남긴다)로 패닉 trace가 그대로 읽히는지 재고, 그렇다면 initrd 4.6MB를
> 되찾는다. init 바이너리도 같이 본다.

## 한 줄 요약

`make_initrd.sh`가 우리가 빌드한 바이너리 다섯(terminal · init · tars-install · tars-service · tars-config)을 initrd에 복사할 때
그 사본만 `strip --strip-debug`한다. `zig-out/bin/`의 원본은 그대로라 호스트에서 `addr2line`으로 주소를 파일:줄로 푼다. 게스트의 패닉
trace는 파일:줄을 잃고 함수 이름은 남는다(Zig 0.17의 symtab fallback) — 이것을 먼저 실제 패닉으로 재고(M0), 그 뒤에 넣는다(M1).

## 배경

### strip을 안 하는 이유는 세 전제였다

TF-M4(2026-08-12)가 strip을 되돌렸고(`4504a7f` → `136129c`), 그 이유가 `project_gate_chain_composition`과 `make_initrd.sh`의
주석에 남아 있다.

1. Zig의 에러 trace는 바이너리 자체의 디버그 정보를 런타임에 읽어 만든다.
2. 그래서 strip하면 게스트 안에서 trace를 되살릴 방법이 원리적으로 사라진다.
3. 호스트에 심볼 사본을 둬도 소용없다.

그리고 같은 기록이 스스로 단서를 붙였다 — 같은 크래시에서 strip 판은 `???:?:?: 0x12716d8 in ???` 두 줄, 심볼 판은 trace 자체가
없었다(원인 미규명). 지키려던 것이 그때도 실제로 동작한 적이 없다. 지금의 선택은 "trace가 잘 나와서"가 아니라 "strip하면 고칠 여지가
없어서"였다.

### 지금은 두 전제가 성립하지 않는다

그때는 Zig 0.14대 · Debug였고 지금은 0.17 · ReleaseSafe다. 착수 전에 확인한 것 2 · 3이 전제 2 · 3을 뒤집는다 — 0.17은 DWARF가
없으면 `.symtab`으로 함수 이름을 찾고, 바이너리가 non-PIE라 게스트가 찍은 주소를 호스트의 원본에 그대로 넣을 수 있다. 남는 것은 전제
1의 비용이다 — 게스트 안에서 바로 파일:줄이 나오는 것. 그것이 지금 실제로 나오는지는 아무도 재지 않았다(TF-M4 뒤로 패닉 trace를 본
기록이 없다).

### 얼마인가

착수 전에 확인한 것 1. terminal 하나가 initrd(gzip)에서 2.9MB, 압축을 푼 rootfs(RAM)에서 11.6MB다. init 계열 넷을 더하면 RAM 쪽은
20MB를 넘는다. 게스트 메모리는 게이트에서 1GB다. initrd 크기는 limine이 BIOS INT13h로 ISO를 읽는 시간에도 걸린다
(`project_gate_chain_composition`의 TF-M4 실측) — 다만 크기가 곧 시간은 아니라는 ZM-M1의 실측도 같은 문서에 있다.

## 착수 전에 확인한 것

2026-10-26, HEAD `d92925c`. 바이너리는 호스트의 `zig-out/bin/`(19:29 ~ 19:30 빌드), 도구는 컨테이너의 `x86_64-linux-gnu-*`다.
컨테이너가 arm64라 그냥 `strip`은 x86_64 ELF를 못 읽는다(`Unable to recognise the format`).

1. 크기(바이트). 사본에 strip을 해서 쟀다.

   | | 원본 | `--strip-debug` | `strip`(전부) | gzip -9 원본 | gzip -9 strip-debug |
   |---|---|---|---|---|---|
   | terminal | 14,565,904 | 3,006,576 | 2,704,248 | 4,118,871 | 1,176,211 |
   | init | 4,723,400 | 775,696 | 710,576 | 1,251,088 | 290,325 |

   terminal의 섹션은 `.debug_loc` 5,319,497 · `.debug_info` 2,825,630 · `.debug_line` 1,365,374 · `.debug_str` 812,223 ·
   `.debug_ranges` 755,456 · `.debug_pubtypes` 281,014 · `.debug_pubnames` 182,792, 남는 쪽은 `.text` 2,080,478 · `.rodata` 416,528 ·
   `.eh_frame` 100,200 · `.strtab` 168,493 · `.symtab` 134,496. `--strip-debug`와 전부 strip의 차이는 `.symtab` + `.strtab`
   0.3MB다 — 함수 이름을 남기는 값이 싸다. tars-install · tars-service · tars-config는 호스트의 `zig-out`에 없어 재지 않았다(M0).
2. 0.17의 symbolize는 DWARF가 없으면 symtab으로 간다. `lib/std/debug/SelfInfo/Elf.zig:94`의 "When DWARF is unavailable, fall back
   to searching the symtab"과 `ElfFile.searchSymtab`. 줄 모양은 `lib/std/debug.zig`의 `printLineInfo` — `source_location`이 없으면
   `???:?:?`, 이름은 `symbol.name orelse "???"`이므로 strip-debug 판은 `???:?:?: 0x… in <함수 이름> (…)`가 될 것이다. 소스를 읽은
   예측이고 실제 출력은 M0이 본다.
3. 둘 다 non-PIE다. `readelf -h`의 `Type: EXEC`(terminal · init). 주소에서 로드 기준을 뺄 필요가 없어
   `x86_64-linux-gnu-addr2line -f -i -e terminal/zig-out/bin/terminal 0x…`가 그대로 된다. 컨테이너에 `x86_64-linux-gnu-addr2line` ·
   `x86_64-linux-gnu-strip`이 있다(Dockerfile의 `binutils` · `gcc-multilib-x86-64-linux-gnu` 쪽). 새 패키지가 필요 없다.
4. `.eh_frame` · `.eh_frame_hdr`는 `--strip-debug` 뒤에도 남는다. unwind(trace의 주소 목록)는 이것으로 하고 symbolize(주소 → 이름)만
   `.debug_*`를 쓴다. 그래서 주소 목록은 strip 뒤에도 그대로일 것이다 — 이것도 M0이 본다.
5. 자식의 stderr는 `/dev/console`(`init/src/main.zig:315-317`)이라 terminal의 패닉 trace는 시리얼 로그, 곧 게이트 로그에 남는다.
6. 바이너리 크기나 strip 여부를 보는 게이트 검사는 없다(`rg -i 'debug_|strip|readelf -S'`가 check 스크립트에서 아무것도 안 낸다).

## 결정

### 결정 1. `--strip-debug`다. 전부 strip이 아니다

함수 이름(`.symtab`)이 0.3MB에 게스트 로그에서 바로 읽힌다(확인 2). 0.3MB를 더 아끼려고 그 이름을 버리지 않는다.

### 결정 2. 자리는 `make_initrd.sh`의 사본이다. `build.zig`의 `.strip`이 아니다

`zig-out/bin/`의 원본이 호스트의 symbolize 재료다(확인 3). build 옵션으로 strip하면 그 재료가 사라진다 — TF-M4의 전제 3이 그때 참이
된다. 사본만 strip하면 원본 · 호스트 테스트 · `zig build`의 캐시가 그대로다. `copy_lib_deps`는 원본을 읽든 사본을 읽든 `NEEDED`가 같다.

### 결정 3. 대상은 우리가 빌드한 다섯이다

terminal · init · tars-install · tars-service · tars-config. `install_tool`이 싣는 sysroot의 Debian 바이너리는 이미 strip돼 있을
것이고(M0이 한 번 본다), 거기에 손대는 것은 이번 범위가 아니다(비목표 1).

### 결정 4. 호스트에서 푸는 명령은 lessons "범용 명령"에 한 줄이다

스크립트를 만들지 않는다. 게스트 로그의 주소를 `addr2line`에 넣는 한 줄이고, 조건(그 로그를 낸 빌드의 `zig-out`이어야 한다)을 함께
적는다. 쓸 일이 드문 명령에 파일 하나는 과하다.

### 결정 5. M0은 실제 패닉을 두 판으로 본다

원본 판과 strip-debug 판에서 같은 자리의 `@panic`을 일으켜 시리얼에 나온 trace를 나란히 놓는다. 패닉은 저장소 코드를 고치지 않고
`probe/patch.pl`처럼 사본에 주입한다(RS의 방법). terminal 하나로 충분하다 — init 계열도 같은 `std.debug` 경로다. 세 가지를 본다.

- (a) 원본 판에 파일:줄이 나오는가. TF-M4의 "심볼 판은 trace가 없었다"가 지금도인가.
- (b) strip-debug 판이 확인 2의 예측(`in <함수 이름>`)대로인가, 주소 목록이 (a)와 같은가.
- (c) (b)의 주소를 호스트에서 `addr2line`에 넣으면 (a)의 파일:줄이 나오는가.

(a)가 파일:줄을 내고 (b)가 `???`만 낸다면 M1 전에 사용자에게 묻는다 — 그때는 잃는 것이 실제로 있다.

### 결정 6. 게이트 — M0은 프로브만, M1은 루트 게이트

M0은 코드 · 스크립트 0줄이라 게이트를 안 돈다. M1은 initrd의 모든 바이너리가 바뀌므로 루트 게이트 22체인을 돈다(약 10분, HC-M2 실측).
initrd 크기와 prebuild 시간을 M1 전후로 적는다 — 시간이 안 줄어도 실패가 아니다(ZM-M1).

### 결정 7. 주석과 기억은 함께 고친다

`make_initrd.sh`의 "strip은 여전히 안 한다" 주석, `init/build.zig:23-25`의 "strip을 안 쓰기로 한 이유" 주석,
`project_gate_chain_composition`과 `project_gate_latency`의 strip 문단. 옛 판단을 지우지 않고 "LI에서 바뀌었다 — 이유"를 붙인다.

## Milestone

- LI-M0 — 잰다(결정 5). 프로브 판 둘의 trace, 다섯 바이너리의 크기, sysroot 바이너리의 strip 여부. 코드 0줄. 결과가 결정 1 · 3을
  바꾸면 design을 고친다.
- LI-M1 — 넣는다(결정 2 · 3 · 4 · 7). `make_initrd.sh`의 strip, lessons의 한 줄, 주석과 기억. 루트 게이트.

## 위험

1. 원본과 사본이 어긋난다. `addr2line`은 그 로그를 낸 빌드의 `zig-out`이어야 맞다. 다시 빌드하면 주소가 바뀐다. 게이트 로그는 그 회차의
   빌드라 맞고, 실기의 패닉은 그 ISO를 만든 빌드여야 한다 — 공개 버전(ISO)의 trace는 원본을 남겨 두지 않는 한 호스트에서 못 푼다(비목표
   2).
2. 패닉 주입 자리가 trace를 못 낸다. `App.open` 같은 이른 자리는 콘솔 출력 전일 수 있다. plan이 시리얼에 이미 줄을 찍은 뒤의 자리를
   고른다.
3. `x86_64-linux-gnu-strip`의 이름이 컨테이너 이미지에 묶인다. Dockerfile에서 `gcc-multilib-x86-64-linux-gnu`가 빠지면 initrd 빌드가
   멈춘다 — 조용히 건너뛰지 않고 멈추는 것이 맞다(`install_tool`의 원칙).

## 비목표

1. sysroot 바이너리(`install_tool`)와 vim-runtime 같은 다른 initrd 다이어트. HANDOFF 후보에 따로 있다.
2. 공개 버전의 디버그 사본 보관(`.debug` 파일을 release에 붙이기 · build-id). 실기 패닉이 생기면 그때 다시 본다.
3. TF-M4의 "심볼 판은 trace가 없었다"의 원인 규명. M0의 (a)가 지금은 나온다고 하면 끝이고, 안 나오면 이월 숙제에 적는다.
4. 소개 페이지(`gh-pages` `data.js`). 기능이 아닌 내부 작업이다(사용자 결정, 2026-10-25).

## 닫을 때(lead의 몫)

- 이 design의 `Status:`, `docs/guides/completed.md`의 한 행.
- `docs/decisions/project_lean_initrd.md`와 `MEMORY.md` 한 줄, `HANDOFF.md`의 후보에서 이 항목 지우기.
- `measurements.md`에 M0의 크기 · trace 모양을 번호 하나로.

## 관련

- `docs/decisions/project_gate_chain_composition.md` — strip을 안 하기로 한 TF-M4의 문단. 이번에 뒤집는 판단.
- `docs/decisions/project_gate_latency.md` — GL-M3의 ReleaseSafe와 "strip은 안 한다".
- `docs/specs/2026-10-03-tars-zig-upgrade-design.md` 실측 9 — 이번의 출발점.
- `docs/plans/2026-08-12-tars-terminal-foundation-tf-m4.md` 850줄 — `???:?:?: 0x12716d8 in ???`의 원래 기록.
- `probe/patch.pl` — 사본에 주입하는 방법(RS design 결정 2 · 3).
