# UW-M2 — 반사실 하나, 루트 게이트, 닫기

> 실행 기록으로 쓴다. 코드는 안 바뀐다.

Goal: M1의 검사가 예측한 자리에서 잡히는지 보고, 17체인 전체가 초록인지 보고, 문서를 닫는다.

---

## Task 1: 반사실 — `RTW88_8812AU`를 끈다

`scripts/config --disable RTW88_8812AU`로 작업 트리의 `kernel/.config`만 바꾸고 wifi 체인을
돌린다. 예측은 검사 1의 심볼 루프가 부팅 전에 멈추는 것이다. 결과는 design 실측 6. 끝나면
`git checkout kernel/.config`로 되돌린다.

## Task 2: 루트 게이트

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh > /tmp/gate.log 2>&1; echo "rc=$?"; } > /tmp/gate.time 2>&1
```

17체인 3/3, `FAIL` 0줄이어야 한다. 결과는 design 실측 6.

## Task 3: 문서

- design의 `Status:`와 실측 6
- 기억 `docs/decisions/project_usb_wireless.md`와 `MEMORY.md` 한 줄
- `CLAUDE.md`의 완료 표 한 줄
- `docs/guides/lessons.md` 이월 숙제 — 층 A를 빼고 층 B와 `RTL8XXXU`를 남긴다
- WL design 비목표 5에 UW를 가리키는 표시
- `HANDOFF.md`의 맨 위 절
