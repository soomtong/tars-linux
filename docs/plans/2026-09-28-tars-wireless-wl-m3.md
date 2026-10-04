# WL-M3 — 열일곱번째 체인과 닫기

> 사용자가 2026-09-28에 결정을 전부 위임해서 plan을 먼저 쓰지 않고 실행한 기록으로
> 쓴다. mutation의 사본은 `/tmp/wl/cf1` · `cf2` · `cf3.config` · `cf3.check`이고 저장소에
> 안 들어갔다.

Goal: WL design 결정 7을 체인으로 세우고, mutation으로 검사가 무엇을 잡는지 보이고, 루트
게이트를 돌리고 닫는다.

## 바뀐 것

| 파일 | 무엇 |
|---|---|
| `wifi/check.sh` | 부팅 셋(A 양성 · B 틀린 비밀번호 · C 꺼짐) · 검사 열 |
| `wifi/ap.sh` | 게스트 쪽. 설정 디스크의 `services.d/ap`. AP를 netns에 세우고 사람의 일을 대신 한다 |
| `check.sh` | `CHAINS`에 `WL-M3:./wifi/check.sh` |
| `docs/guides/running-tars.md` | "무선에 붙기" 절 · "안 되는 것" 표의 무선 줄 · 체인 수 |
| `docs/guides/lessons.md` | 실측 62~69 · 핵심 파일 · 이월 숙제 · 기억 목록 |
| `docs/decisions/project_wireless.md` · `MEMORY.md` | 기억 |
| `CLAUDE.md` · `HANDOFF.md` · design `Status:` | 닫기 |

## 확인

- 체인 단독 — 1분 34초, 초록(design 실측 14).
- mutation 셋 — `exec` 없음 → 검사 3, hook 막힘 → 검사 8, 내장 cmdline 비움 → 검사 10.
- 루트 게이트 — design `Status:` 줄에 적었다.
