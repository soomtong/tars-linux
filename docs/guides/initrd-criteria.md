# initrd에 넣는 기준

2026-11-05에 사용자와 정했다(TP design의 "터미널 유틸리티" 논의). 그 전에는 글로 쓴 기준 없이 서브프로젝트마다 정했다 — "게이트가
부르니까"(UT), "Homebrew `install.sh`가 부르니까"(PM 결정 3), "라이브러리가 너무 무거우니까"(carryover의 `chafa` 44.6MB 거절, UT의
neovim 보류). TP가 개발 도구 층(디스크의 squashfs, `/usr` 위 overlay)이라는 둘째 자리를 열면서 둘을 가를 말이 필요해졌다.

## 왜 기준이 필요한가

initrd는 부팅마다 RAM에 통째로 풀리고(`rootfstype=ramfs`) 꺼질 때까지 그 자리에 있다. 라이브 USB에도, 개발 도구 층이 없는 부팅에도 있다.
개발 도구 층은 디스크에 있고 page cache로만 읽힌다. 그래서 initrd에 하나를 더하는 것은 "모든 기기의 모든 부팅에서 RAM을 쓴다"는 결정이고,
개발 도구 층에 두는 것은 "설치된 기기에서, 쓸 때만"이다.

## 기준

아래 A · B · C 가운데 하나에 들면 initrd, 아니면 개발 도구 층이다. 크기 기준은 두지 않는다(사용자 결정, 2026-11-05) — 정적 바이너리는
라이브러리를 안 끄는 대신 바이너리 자체가 크고(doge 7.1MB, lsoff 7.2MB), 크기 숫자 하나로는 그 차이가 안 보인다.

| | 조건 | 예 |
|---|---|---|
| A. TARS가 부른다 | init · `tars-install` · `tars-config` · 게이트 판정 · Homebrew와 mise의 설치 스크립트가 부르는 것 | coreutils, curl, tar, sfdisk |
| B. 개발 도구 층 없이도 있어야 한다 | 라이브 USB, 설치 전, 개발 도구 층이 깨진 부팅에서 복구 · 설치 · 망 연결에 쓰는 것 | 셸 셋, vim, ip, lsoff, doge |
| C. 셸의 일상 기본 | 매 셸 세션에서 손이 가는 도구, 셸 연동(rc · 키 바인딩)이 걸린 것 | fzf, ripgrep, fd, bat, eza, jq |

그리고 둘을 함께 본다.

- 같은 일을 하는 도구가 initrd에 이미 있으면 안 넣는다. wget(curl이 있다), procs(ps · top · htop), dust · dua · gdu(du)가
  2026-11-05에 이 이유로 개발 도구 층으로 갔다.
- 새 공용 라이브러리 사슬을 끄는지 본다. 크기 기준은 없지만, 사슬은 그 도구 하나가 아니라 initrd 전체의 의존 그래프를 바꾼다
  (UT의 `libgit2` 15개 11.4MB). 끈다면 그 사실을 결정에 적는다.

개발 도구 층으로 가는 것: 언어 런타임 · 컴파일러, 서버, AI 도구, 큰 TUI(lazygit 등), 그리고 위 셋 어디에도 들지 않는 것.

## 출처

커널과 그 바닥(glibc · 공용 라이브러리)은 Debian trixie에 기댄다 — 보안 갱신과 안정성 때문이다. 개별 유틸리티는 Debian에 기대지
않아도 된다(사용자, 2026-11-05). 공식 바이너리가 있으면 그것을 버전과 sha256으로 고정해 받는다(`devcontainer/Dockerfile`과
`kernel/guest_tools.sh`의 도구 목록 "층 20" — UT 때부터 쓴 목록의 묶음 번호이고, 개발 도구 층과는 다른 말이다). 그래서 UT design 결정 3("조달은 Debian `.deb` 하나로")은 취소됐다(2026-11-05, 사용자 확정) — 처음 둘(lsoff · doge)을
`tools/check.sh` 검사 10b가 게스트에서 쳤고 루트 게이트가 30/30이었다.

판(版)의 차이: initrd의 Debian 도구는 trixie에 고정된 판이고, 개발 도구 층은 최신(LTS가 있으면 최신 LTS)이다. 같은 경로에 둘이 있으면
initrd가 이긴다(TP design 결정 4). 같은 이름이 다른 경로에 있으면 `PATH=/usr/local/bin:/usr/bin:/bin`이 개발 도구 층의 최신판을 앞세운다
(TP design 결정 20) — 설치된 기기에서는 최신판, 라이브 USB와 개발 도구 층이 없는 부팅에서는 trixie 판이 돈다. 그래서 initrd에 넣는
도구도 최신판을 원하면 `util` 묶음에 함께 싣는다.

## 적용 기록

| 날짜 | 무엇 | 판정 |
|---|---|---|
| 2026-11-05 | 사용자의 터미널 유틸리티 목록(TP design "터미널 유틸리티" 표) | initrd에 lsoff · doge(B). 이미 있던 열(bat · duf · eza · fd · fzf · hyperfine · jq · ripgrep · sd · tree)은 C. 나머지는 개발 도구 층. hexyl(B 후보)은 사용자가 개발 도구 층으로 |
