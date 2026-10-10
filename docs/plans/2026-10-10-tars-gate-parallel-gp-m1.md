# GP-M1 — initrd를 한 번에 바꿔치기한다

Date: 2026-10-10
Design: `docs/specs/2026-10-10-tars-gate-parallel-design.md`
Status: 끝났다(2026-10-10). 값은 맨 아래 "GP-M1이 실측한 것".

## 누가 무엇을 하나

편집이 작아 lead가 직접 넣는다.

| 파일 | 무엇을 |
|---|---|
| `kernel/make_initrd.sh` | 같은 디렉터리의 임시 파일(`initrd.cpio.XXXXXX`)에 다 만든 뒤 `mv -f`로 바꿔치기. 실패하면 trap이 임시 파일도 지운다 |
| `tools/check.sh` | 검사 1d — 열어 둔 fd가 다시 만든 뒤에도 옛 파일을 온전히 읽는가 |
| `.gitignore` | `kernel/initrd.cpio.*` |

## 착수 전에 확정한 것 (2026-10-10, 컨테이너에서 실측)

1. `make_initrd.sh` 한 번이 6.07초 · 5.96초다.
2. 두 번 만든 initrd의 바이트가 다르다(sha `32cbebe6…` 대 `d70df219…`, 크기 98,248,516 대 98,248,122). cpio가 매번 새
   `mktemp -d`에 복사된 파일의 mtime · inode 번호를 적기 때문이다. 그래서 design 표의 "내용 해시 stamp로 건너뛰기"는 하지 않는다 —
   산출물을 재현 가능하게 만들거나 입력(sysroot 전체)을 해시해야 하는데, 아끼는 것이 1회 게이트에 2분 남짓(6초 × 22)이라
   게이트 잡음(±3분) 안이다.
3. 병은 실재한다. initrd를 fd 4로 열어 두고 `make_initrd.sh`를 돌리면 그 fd가 새 내용(`c5330b77…`)을 읽고 inode는 184 그대로다.
   `> initrd.cpio`가 같은 파일을 제자리에서 자르고 다시 쓴다. 병렬이면 다른 체인의 QEMU · `gzip -dc | cpio -it` · `make_iso.sh`의
   `cp`가 읽는 중간에 파일이 비워진다.
4. rename은 경로가 가리키는 inode만 바꾼다. 이미 연 fd는 옛 inode를 끝까지 읽는다. 같은 파일시스템이어야 원자적이므로 임시 파일은
   `/tmp`가 아니라 `kernel/` 안에 둔다.
5. `mktemp`는 0600으로 만든다. 지금 `>`로 만든 파일은 umask대로 0644이므로 `mv` 전에 `chmod 644`한다.
6. 검사 1d는 셋을 본다 — (a) 연 fd의 inode ≠ 경로의 inode, (b) 연 fd로 읽은 sha = 열기 전 sha, (c) `initrd.cpio.*`가 안 남았다.
   (b)만 두면 나중에 initrd가 재현 가능해졌을 때 제자리 쓰기도 같은 바이트를 내어 통과한다 — 성공 경로가 둘이 된다
   (`docs/decisions/project_gate_chain_composition.md`). (a)가 원인 하나만 본다.

## Task

1. 편집 셋. `bash -n` 둘.
2. 컨테이너에서 확정 3의 실험을 다시 — fd가 옛 sha를 읽고 inode가 바뀌어야 한다. 권한 0644, 임시 파일이 안 남는지.
3. 음성 확인 — `mv` 대신 `cat "$OUT" > initrd.cpio`로 되돌린 사본에서 검사 1d가 (a)로 빨개지는지. 사본은 커밋하지 않는다.
4. `tools` 체인 단독, 그다음 루트 게이트 1회(약 31분, `skipping make` 21).
5. 결과를 아래 절에 적는다. 사용자 승인 뒤 commit.

## GP-M1이 실측한 것

1. 컨테이너 실험(확정 3을 다시) — 연 fd가 옛 sha `c5330b77…`을 그대로 읽고, 경로의 inode가 184 → 186으로 바뀌었다. 권한 644,
   임시 파일 0.
2. `tools` 체인 단독 초록 — 검사 1d가 `inode 1711 -> 1713`을 찍었다.
3. 음성 확인 — `mv -f "$OUT" initrd.cpio`를 `cat "$OUT" > initrd.cpio`로 바꾼 사본을 `-v …:ro`로 컨테이너의 `make_initrd.sh` 위에만
   덮어 돌렸다. 검사 1d의 (a)가 `rewrote initrd.cpio in place (inode 1713 kept)`로 빨갰고 체인이 `exit=1`이다. 호스트 파일은 안 바뀌었다.
4. 루트 게이트 1회(`RUNS=1` 기본값의 첫 게이트) — 22체인 `PASS: 1/1`, 32분 23초, `skipping make` 21(= 체인 수 − 1), 잘린 줄 0,
   `FAIL` 0. 검사 1d `inode 82545 -> 83748`. 체인 합 1,942초가 바깥 시간과 1초 차이다.
5. tools 체인이 62초 → 68초 — 검사 1d가 initrd를 한 번 더 만드는 몫으로 확정 1의 6초와 같다. 다른 체인은 GP-M0 1회차와 ±5초 안이다
   (CP 198 → 194 · TD 188 → 187 · CM 172 → 172).
