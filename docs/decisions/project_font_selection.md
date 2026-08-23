# 폰트 선택 기준과 현재 폰트 (2026-08-23)

TARS의 터미널 폰트는 **GNU Unifont 17.0.03**이다. 이 문서는 왜 그것이고,
다시 바꾸게 되면 어디를 고쳐야 하는지를 담는다.

## 후보를 가르는 것은 커버리지가 아니라 안티앨리어싱이다

렌더러가 **문턱값 렌더링**을 쓴다(`coverage > 127`이면 찍고 아니면 안 찍는다,
design 결정 4). 중간값을 섞지 않으므로 **16픽셀에서 안티앨리어싱이 생기는
아웃라인 폰트는 그대로 넣으면 획이 끊기거나 사라진다.**

그래서 후보를 재는 지표는 커버리지가 아니라 **16픽셀로 구웠을 때 잉크 중
중간값의 비율**이다. 표본
`ABCgjq0189가한글놀ㄱㅏㅎㅣ은택─│┌`로 쟀다.

| 폰트 | 크기 | 중간값 비율 | 판정 |
|---|---|---|---|
| **unifont 17.0.03** | 5197KB | **0.0%** | **채택** |
| Hanme 8x4x4 | 441KB | 0.0% | 비트맵이지만 커버리지가 좁다(아래) |
| MonoplexNerd / MonoplexWideNerd | 약 10MB | 92.8% | 탈락 |
| PlemolKRConsole | 9894KB | 92.8% | 탈락 |
| TubakDot | 932KB | 87.7% | 탈락 |
| D2Coding | 8255KB | 81.3% | 탈락 |

**중간값 비율 0%가 곧 비트맵 폰트라는 뜻이다.** 사용자가 데스크톱에서 쓰는
MonoplexNerd도 여기서 걸린다 — 커버리지는 충분하지만 문턱값으로 자르면
`한`·`글`을 읽기 어려워진다. 아웃라인 폰트를 쓰려면 알파 블렌딩이 필요하고,
그것은 design 결정 4를 뒤집으면서 게이트의 픽셀 검사까지 재설계하는 일이다.

## unifont의 성질 (다시 재지 말 것)

```
https://ftp.gnu.org/gnu/unifont/unifont-17.0.03/unifont-17.0.03.otf
26071c5a97533cefdcbc6b0645e7ee279413049079f09f592b26916ca6c21bf5
```

- `unitsPerEm=64`, `ascent=56`, `descent=-8`이라 16픽셀에서 `scale`이 정확히
  **0.25**이고 `ascent_px`가 **14**다. 16x16 격자를 그대로 담은 비트맵이다.
- advance가 라틴 8 · 한글 16으로 지금 격자(`CELL_W=8`, `ROW_HEIGHT=16`)와
  같다. **렌더러 상수를 안 고쳐도 된다.**
- 형식이 CFF(OpenType/PostScript)인데 vendor된 `stb_truetype.h`가 문제없이
  읽는다(`numGlyphs=58911`).
- ASCII 95 · 호환 자모 **51/51** · 조합용 자모 67 · 완성형 11172 · 박스
  드로잉 **128/128** · 한자 20992. 11640자를 구워도 **셀 이탈이 0이다.**
- 라이선스가 SIL OFL 1.1 + GNU GPL v2+(Font Embedding Exception) 이중이라
  재배포에 문제가 없다.
- initrd는 cpio 73.0MB → gzip **16.76MB**다(폰트가 gzip 기준 1.2MB를 더했다).

**여유가 0이다.** `font_test`가 재는 "가장 아래"가 **정확히 16행**이다.
넘지는 않지만 1픽셀도 남지 않는다.

**unifont에는 "폰트에 없는 글자"가 존재하지 않는다.** 미할당 코드포인트에도
글리프가 있고 `.notdef`조차 모양을 가진다(U+FFFF·U+E000·U+1F600·U+10000·
U+2FFFF가 전부 6x11로 같다). 화면에 두부(tofu)가 안 뜨는 대신 `font.zig`의
"폰트에 없는 글자" 경로가 실질적으로 죽은 코드가 됐다.

### `font_test`의 기대값 표

```
A   6x10  cell_width=8   x_offset=1  y_offset=4     yoff=-10
g   6x11  cell_width=8   x_offset=1  y_offset=5
한  15x14  cell_width=16  x_offset=1  y_offset=2     yoff=-12
가  14x14  cell_width=16  x_offset=2  y_offset=2
é   6x12  cell_width=8   x_offset=1  y_offset=2
```

## 폰트를 또 바꾼다면 — 고칠 자리 열과 함정 셋

**저장 이름에 버전을 넣지 않는다**(`vendor/fonts/unifont.otf`). 경로를 읽는
곳이 다섯이라 이름에 버전을 박으면 올릴 때마다 전부 고쳐야 한다. 버전은
`vendor_fonts.sh` 한 곳에만 있고, 어느 파일인지는 sha256이 보증한다.

```
terminal/vendor_fonts.sh             URL · 파일 이름 · sha256
kernel/make_initrd.sh:94             initrd에 복사
kernel/make_initrd.sh:186            initrd 크기 실측 주석
terminal/src/main.zig                경로 문자열
terminal/src/font_test.zig           경로 + 기대값 표 + 4번 검사 표본
terminal/prepare.sh                  주석
terminal/build.zig:102               확장자가 박힌 주석
terminal/sanity/stb_truetype_main.c  경로 문자열
terminal/src/font.zig                실측 주석 다섯 (코드는 안 바뀐다)
check.sh:10                          폰트 이름이 박힌 주석
```

**함정 1 — 검색에 안 걸리는 자리가 있다.** 위 열 중 셋(`check.sh`,
`build.zig`, `font.zig`)은 이전 폰트의 **이름이 없어서** 이름으로 검색하면
안 나온다.

**함정 2 — 코드는 폰트에 무관한데 주석이 아니다.** `font.zig`는 `ascent_px`를
`stbtt_GetFontVMetrics`에서 읽으므로 폰트를 바꿔도 **코드가 한 줄도 안
바뀌었다.** 그런데 주석이 이전 폰트의 숫자를 사실로 적어 두고 있었다. 고치지
않으면 다음 사람이 틀린 값을 믿는다.

**함정 3 — `font_test`의 4번 검사는 기대값이 아니라 표본이 폰트를 탄다.**
"그릴 것이 없는 글자"를 확인하는 검사인데, 표본이 U+4E00(한자)이었고
unifont에는 한자가 있다. 지금은 표본이 **공백**이다 — 어느 폰트에나 있으면서
그릴 것이 없어서 `font.zig`의 계약을 폰트와 무관하게 확인한다.

## 교체가 싼 이유는 게이트가 상수를 비교하지 않기 때문이다

`render/check.sh`가 `ink>`를 정확한 값과 비교하지 않고 **좌우 절반이 0이
아닌지만** 본다. 그래서 폰트를 바꿔 잉크 개수가 `한` 기준 64에서 50으로
달라졌는데도 게이트 일곱 체인이 3/3으로 그대로 통과했다. 실사용 캐시는
1,784→**1,665바이트**로 오히려 줄었다 — 파일은 12배 크지만 획은 더 가늘다.

## 재지 않은 범위를 근거로 결론을 내리지 말 것

TR-M1은 Hanme의 자모 커버리지 표를 **본문에서 반대로 읽어** "낱자를 못
그린다"고 단정했다. 실제로는 조합용 자모(U+1100~)를 64자 갖고 있어서 우회로가
있었고, 그 우회로를 설계까지 했는데 같은 날 unifont로 바꾸면서 통째로 필요
없어졌다. **표를 만들었다고 표를 읽은 것은 아니다.**

## 관련

- 문턱값 렌더링의 근거: [[project_terminal_rendering]]
- initrd 압축 해제가 부팅에서 차지하는 몫: [[project_kernel_config]]
