# UB-M2 — mutation 둘, 루트 게이트, 닫기

> 실행 기록으로 쓴다. 코드는 안 바뀐다.

Goal: M1의 검사가 예측한 자리에서 잡히는지 보고, 22체인 전체가 초록인지 보고, 문서를 닫는다.

---

## Task 1: mutation 둘

작업 트리의 `kernel/.config`만 바꾸고 `make check CHAIN=wifi`를 돌린 뒤 `git checkout
kernel/.config`로 되돌린다. 체인이 시작에 `build.sh`를 부르므로 바뀐 `.config`로 커널을 한 번
다시 빌드한다(약 30초) — 그 뒤 검사 1이 부팅 전에 멈춰야 한다.

1. `CONFIG_MT7601U=y` → `# CONFIG_MT7601U is not set`. 예측: 검사 1의 심볼 루프.
2. `# CONFIG_HID_APPLE is not set` → `CONFIG_HID_APPLE=y`. 예측: 결정 4의 음성 검사.

결과는 design 실측 5.

## Task 2: 루트 게이트

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh > /tmp/gate.log 2>&1; echo "rc=$?"; } > /tmp/gate.time 2>&1
```

22체인 1/1, `FAIL` 0줄, verify 줄 전부 통과여야 한다. 결과는 design 실측 6.

## Task 3: 문서

- design의 `Status:`와 실측 5 · 6
- 기억 `docs/decisions/project_usb_dongles_b.md`(새 파일)와 `MEMORY.md` 한 줄
- `docs/guides/completed.md` 표 끝에 한 행
- `docs/guides/carryover.md` — UW 비목표 1 항목을 UB가 남긴 것(UNTESTED · UNKNOWN · 다른 계열)으로 줄인다
- UW design 비목표 1과 `project_usb_wireless.md` 끝에 UB를 가리키는 표시
- `HANDOFF.md`의 맨 위 절
- 소개 페이지(`gh-pages`)에는 안 넣는다 — 지원 동글이 는 것이지만 실기 판정이 없어 기능으로 내세우지 않는다(UW와 같다)
