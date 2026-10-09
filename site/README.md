# 소개 페이지

https://soomtong.github.io/tars-linux/ — `gh-pages` 브랜치의 정적 파일 그대로다.
빌드 단계도 workflow도 없다(Pages 설정: Deploy from a branch · `gh-pages` · `/`).

## 왜 두 곳으로 나뉘나

- `gh-pages`(고아 브랜치)에는 공개되는 것만 있다 — `index.html` · `style.css` ·
  `app.js` · `data.js` · `media/`. 영상은 우리 빌드를 찍은 산출물이라 main
  히스토리에 넣지 않는다. 다시 찍으면 그 브랜치만 바뀐다.
- main의 `site/`에는 영상을 만드는 소스(`capture.sh`)와 이 문서가 있다.
  `capture.sh`는 main의 `bzImage` · `initrd.cpio`에 기대므로 main에 산다.

작업 사본은 worktree 하나다.

```bash
git worktree add ../tars-linux-pages gh-pages   # 처음 한 번 (없을 때)
```

## 갱신 — 서브프로젝트를 하나 닫았을 때

페이지의 내용은 전부 `gh-pages`의 `data.js` 한 파일이다. `index.html`과
`app.js`는 손대지 않는다.

1. `asOf`를 그날로, `latest`를 닫은 서브프로젝트 이름으로.
2. `timeline`에 `[끝난 날, 이름, 약칭, 한 줄]`을 한 줄 더한다.
3. `features`의 알맞은 갈래에 `[이름, 설명, 끝난 날]`을 더한다. 사용자가
   손으로 닿는 것(키 · `tars.conf` 키 · `/config` 파일 · 명령)마다 한 줄이다.
   새 갈래가 필요하면 `{ title, note, items }`를 하나 더한다.
   끝난 날이 `asOf`에서 `newWithinDays`(7일) 안이면 페이지에 NEW가 붙는다.
4. `stats` — `commits`는 `git rev-list --count main`, `chains`는 `check.sh`의
   `CHAINS` 개수, `zigKLines`는
   `fd -e zig . init terminal tars-config | xargs wc -l | tail -1`을 1000으로.
5. 화면에 보이는 기능이면 영상을 찍는다(아래). 아니면 건너뛴다.
6. 로컬에서 본다: `open ../tars-linux-pages/index.html` (파일로 열어도 된다 —
   `data.js`를 `<script>`로 읽어서 fetch가 없다).
7. `gh-pages`에서 커밋하고 push한다. 1~2분 뒤 반영된다.

## 영상 다시 찍기

```bash
site/capture.sh                 # 다섯 장면 전부(약 2분)
site/capture.sh copy vim        # 고른 장면만
cp out/site/*.mp4 out/site/*.webp ../tars-linux-pages/media/
```

- 이미 빌드된 `kernel/build/arch/x86/boot/bzImage`와 `kernel/initrd.cpio`를
  호스트 QEMU로 띄운다(설정 디스크 없음 — 기본값의 화면이다).
- 키는 monitor(45600)의 `sendkey`, 프레임은 둘째 monitor(45601)의
  `screendump`로 0.1초마다. monitor 하나는 손님을 하나만 받아서 둘로 나눴다.
- 게스트 화면은 1024×640이다(`virtio-gpu-pci,xres,yres`). 셀 크기는 그대로라
  화면이 작을수록 웹에서 글자가 크다.
- 장면은 `scene_<이름>` 함수 하나다. 새 장면은 함수를 더하고 `SCENES` 기본
  목록과 `index.html`의 `.feat` 블록에 하나씩 더한다.
- 한글은 기본 자판(신세벌 PCS)의 키를 `hangul_keys`에 직접 준다. 키 표는
  `terminal/src/hangul.zig`의 `shinCommon`이다.
- TCG라 한 프레임이 2초를 넘기도 한다. 출력을 기다릴 때는 고정 `pause`
  대신 `wait_screen <패턴>`(시리얼 로그의 `screen>` 줄)을 쓴다.
- 판정이 아니다. 각본이 틀리면(없는 경로, 좁은 패널의 btop) 영상이 틀린
  것을 찍는다 — 다 찍고 나서 프레임을 눈으로 본다.
