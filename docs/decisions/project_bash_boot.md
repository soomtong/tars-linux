---
name: project_bash_boot
description: 게이트가 bash로 뜨는 부팅을 하나 갖게 된 일(BB-M0~M2, 2026-09-12). config 체인 9차가 shell=bash로 뜨고 로그 여덟 · 화면 넷을 판정한다. power 체인은 전부터 bash로 떴지만 프롬프트까지만 봤다 — 밟는 것과 판정하는 것은 다르다
metadata:
  type: project
---

# 게이트가 bash로 뜨는 부팅을 하나 갖게 된 일 (BB-M0~M2, 2026-09-12)

design: `docs/specs/2026-09-12-tars-bash-boot-design.md`

## 무엇이 섰나

`config` 체인이 부팅 여덟에서 아홉이 됐다. 아홉째만 `shell=bash`로 뜬다 —
1차가 fish이고 2~8차가 zsh다.

⚠ 이 서브프로젝트가 착수할 때 쓴 전제 하나가 틀렸다. "게이트에 bash로 뜨는
부팅이 없다"고 적었는데 `power` 체인의 첫 부팅이 `shell=bash`로 뜬다
(`power/make_disk.sh`가 `mkfs.ext2 -d`로 그 줄을 심는다 — measurements 34). 그 체인이
보는 것은 로그의 `config shell=bash`와 화면의 `screen>.*bash-` 둘이고, 셸 자신의
성질은 하나도 안 본다. 그래서 BB가 세운 것은 "bash로 뜨는 자리"가 아니라 "bash로
뜬 부팅의 판정"이다. `linkDevFd()`를 눕힌 사본으로 `power/check.sh`를 돌리면 화면에
에러 줄이 찍히는데 체인은 통과한다 — `BASH_OK` 대기가 `screen>.*bash-`라 앞줄에
무엇이 있어도 만족되기 때문이다(measurements 27 둘째 문단). 부팅은 있었고 판정이
없었다.

8차 훅의 맨 끝이 `echo shell=bash >> /config/tars.conf` 한 줄을 심는다.
append인 것과 심는 자리가 8차 판정 셋보다 뒤인 것이 둘 다 의도다 — 마지막
줄이 이기므로 `shell_config=on`이 그대로 살고, `history`가 최근 16개만 찍는
창을 밀지 않는다.

9차가 보는 것은 로그 여덟과 화면 넷이다. 로그는 `config shell=bash` ·
콘솔 셸의 실체가 `/usr/bin/bash`인 것 · env의 `HISTFILE`과 `HISTSIZE`,
그리고 부정 넷(`is not executable` · `env SAVEHIST` · `seeded /config/` ·
아무도 안 죽는 것). 화면은 `bash-5.2#` · `/usr/bin` · `bprod1` ·
`bprodwfunction`이다.

## 왜 중첩으로는 안 됐나

BH-M2가 7차 부팅 안에 중첩 bash를 띄워 seed의 한 줄을 판정했지만, 중첩이 볼
수 없는 것이 여섯 있었다 — `resolveShell(.bash)`의 실행 가능 판정 · 히스토리
env의 bash 갈래 · argv로 화면 셸도 bash가 되는 것 · seed bashrc가 production에서
조용한 것 · `PROMPT_COMMAND` 훅 둘이 함께 사는 것 · 콘솔 셸도 bash인 것. 여섯의
설명은 design의 "왜 중첩으로는 안 됐나" 절. 이 여섯이 열린 근거는 BH 자신이다
(`/dev/fd`가 없어 seed의 fzf 훅이 부팅마다 에러 한 줄을 찍는 것을 서브프로젝트
넷이 못 봤다 — measurements 27).

## 다시 조사하지 말 것

1. 인자 하나인 `z`는 DB를 안 본다 — measurements 33. 판정 질의는 인자 둘(`z usr bin`).
2. `declare -F <이름>`의 출력은 이름 그 자체다. 인자 없이 부를 때와 다르다
   (그때는 `declare -f <이름>`). 타이핑한 줄과 글자가 같아서 판정 글자로 못
   쓴다. `echo bprodw$(type -t __fzf_history__)`로 우리가 글자를 만든다.
3. 최상위 bash의 프롬프트도 `bash-5.2#`다(중첩과 같다). 체인의 패턴은
   `bash-[0-9]+\.[0-9]+#`로 느슨하게 뒀다 — 게스트의 bash는
   `guest_tools.sh`가 정하는 Debian 스냅샷에서 오므로 버전이 올라가는 날
   체인이 조용히 깨지는 것을 막는다.
4. 타이핑이 프롬프트를 앞질러도 명령은 온전하다. 앞 명령이 도는 중에 다음
   명령의 첫 글자가 tty에 에코되어 화면에 `cbash-5.2#`가 남지만, 프롬프트가
   그려진 뒤 readline이 그 글자를 다시 그려서 명령은 제대로 실행된다.
   BH-M2가 본 "글자가 쪼개진다"와 다른 현상이고, 판정 글자를 우리가 만드는
   규칙이 이것까지 막는다.
5. `mkfs.ext2 -d`가 조사용 부팅을 하나로 줄인다 — measurements 34(착수 전에
   `*/make_disk.sh`를 전부 읽으라는 것까지).
6. `shift-backslash`가 게스트에 `|`로 닿는다(키맵 43번이 `\`/`|` 쌍이다).
   다만 판정에는 쓰지 않는다 — `screen>` 덤프의 행 구분자가 `|`라서 패턴이
   모호해진다.
7. seed의 순서가 뒤집히면 zoxide가 프롬프트마다 다섯 줄을 찍는다. zoxide에
   자기 훅이 덮인 것을 알아채는 진단이 있다. 그 다섯 줄이 화면 좌표를
   미므로, seed가 아무것도 안 찍는다는 이 저장소의 규칙은 순서가 맞을 때만
   성립한다.

## mutation이 증명한 것

seed bashrc에서 `PROMPT_COMMAND` 줄을 훅 뒤로 옮긴 사본으로 셋을 확인했다.
사본 하나만 마운트하면 `config_test.zig`가 부팅 앞에서 죽이므로 그 검사의
마지막 줄에 `or true`를 넣은 사본을 함께 준다(`docs/guides/dead-ends.md`의
"호스트 검사가 지키는 줄을 뺀 mutation을 마운트 하나로 보기" 항목).

그렇게 하면 판정 1만 빨개지고 2·3은 초록으로 남는다. 히스토리는 남고 `z`만
아무것도 안 배우는 것 — BH가 "증상이 조용하다"고 적어 둔 그 모양이다.
9차의 판정 1이 그것을 잡는 유일한 자리다.

## 관련

- [[project_shell_history]] — seed의 그 한 줄을 넣은 서브프로젝트 둘(SD·BH)
- [[project_measuring_shells]] — 재는 환경과 돌 환경이 다를 때 값이 조용히
  틀리는 것. 이 서브프로젝트가 그 교훈의 결론이다(게스트에서 재라)
- [[project_shell_memory]] — 히스토리 env와 훅 두 벌의 구조
- [[project_gate_chain_composition]] — 게이트는 자기가 안 보는 것을 통과시킨다
