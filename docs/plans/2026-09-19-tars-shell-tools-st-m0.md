# ST-M0 — 별칭을 넣기 전에 그 줄들의 조용함과 eza의 플래그를 잰다

> 이 plan을 실행하는 사람에게: 이 milestone은 제품 코드를 한 줄도 안 고친다.
> 만드는 것은 `/tmp/probe/m0/` 아래의 측정 하네스뿐이고, 저장소에 들어가는
> 것은 design 문서의 실측 절 하나다. TDD 구조가 아니다 — TS-M0 · NW-M0 ·
> IN-M0의 plan과 같은 형식이다.

Goal: ST design의 결정 4(별칭 넷)와 위험 2(씨앗이 찍으면 좌표가 밀린다)를
부팅 한 번으로 닫는다. 그러면 M1이 씨앗을 고칠 때 미지수가 남지 않는다.

Architecture: 호스트에서 후보 줄을 담은 파일 넷을 만들어 `mkfs.ext2 -d`로
설정 디스크에 싣고, 게스트 콘솔 셸에서 그 파일을 셸 셋에 각각 먹여 출력
바이트를 `wc -c`로 센다. 같은 부팅에서 eza의 플래그 넷을 직접 쳐 본다.
타이핑에는 `gate_lib.sh`의 `type_keys`를 그대로 쓴다.

Tech Stack: bash · QEMU 11.1.1(호스트) · e2fsprogs(컨테이너) · 게스트의
`zsh` · `bash` · `fish` · `eza` · `wc`

---

## 무엇을 재는가

| 측정 | 무엇 | 어느 결정·위험 | 판정 |
|---|---|---|---|
| 1 | 후보 별칭 넷을 셸 셋이 각각 몇 바이트 내는가 | 위험 2 | 0바이트 |
| 2 | 같은 조건의 빈 파일 기준선 | 위험 2 | 측정 1과 같은 수 |
| 3 | `eza` · `eza -l --group-directories-first` · `eza -la --group-directories-first` · `eza --tree --level=2`가 도는가 | 결정 4 | 넷 다 0이 아닌 종료 코드 없이 목록을 낸다 |
| 4 | `--icons`의 결론(design 실측 4)이 실제로 빈 칸인가 | 결정 4 | 재지 않는다 — 폰트 cmap이 이미 답했다 |

측정 1과 2를 가르는 이유: 셸이 파일을 읽는 것만으로 내는 바이트가 있다
(zsh는 `-c`에서 stderr 65바이트를 내는 오타를 냈다 — SD 실측 9). 후보 줄의
값은 그 기준선과의 차이다.

비대화형 실행으로 잰다. 후보가 별칭 정의뿐이라 이 조건에서 갈리지 않는다 —
훅이었다면 대화형으로 재야 한다(SD 실측 9가 그 구분을 적고 있다). 이 한계를
design 실측 절에 함께 적는다.

## Task 0 — 후보 파일과 디스크를 만든다

```bash
mkdir -p /tmp/probe/m0/seed /tmp/probe/m0/log
cat > /tmp/probe/m0/seed/cand.fish <<'EOF'
alias ls='eza'
alias ll='eza -l --group-directories-first'
alias la='eza -la --group-directories-first'
alias lt='eza --tree --level=2'
EOF
```

`cand.bash` · `cand.zsh`는 같은 내용+같은 문법이다(셋 다 `alias 이름='본문'`).
`empty.sh`는 빈 파일이다.

```bash
cd /Users/dp/Repository/tars-linux
docker run --rm -v /tmp/probe/m0:/m0 tars-devcontainer bash -c '
  rm -f /m0/config-m0.img
  truncate -s 16M /m0/config-m0.img
  mkfs.ext2 -F -q -m 0 -L tars-config -d /m0/seed /m0/config-m0.img
  debugfs -R "ls -l /" /m0/config-m0.img'
```

`-d`가 파일 넷을 이미지 루트에 넣는다. 게스트는 이 이미지를 `/config`에
붙이므로 `/config/cand.fish`가 된다. init은 없는 씨앗 셋을 함께 깐다 —
그것은 이 측정에 영향이 없다.

Acceptance: `debugfs` 목록에 `cand.fish` · `cand.bash` · `cand.zsh` · `empty.sh`
넷이 보인다.

## Task 1 — 부팅 한 번으로 잰다

`/tmp/probe/m0/boot-m0.sh`: `config/make_disk.sh`가 쓰는 것과 같은 방식으로
부팅하고(`-kernel` · `-initrd` · `-drive file=config-m0.img` ·
`-monitor tcp` · `-serial file:`), 화면에 `terminal: screen>`이 나오면 monitor에
붙어 아래를 차례로 친다. 명령 사이에는 `sleep 2`를 두고, 마지막에 화면 줄을
전부 찍는다.

| # | 치는 것 | 보는 것 |
|---|---|---|
| 1 | `zsh /config/cand.zsh > /tmp/z1` | 다음 줄의 수 |
| 2 | `wc -c /tmp/z1` | 0 |
| 3 | `zsh /config/empty.sh > /tmp/z0` · `wc -c /tmp/z0` | 기준선 |
| 4 | `bash /config/cand.bash > /tmp/b1` · `wc -c /tmp/b1` | 0 |
| 5 | `bash /config/empty.sh > /tmp/b0` · `wc -c /tmp/b0` | 기준선 |
| 6 | `fish /config/cand.fish > /tmp/f1` · `wc -c /tmp/f1` | 0 |
| 7 | `fish /config/empty.sh > /tmp/f0` · `wc -c /tmp/f0` | 기준선 |
| 8 | `eza /config` | 목록 |
| 9 | `eza -l --group-directories-first /config` | 긴 목록 |
| 10 | `eza -la --group-directories-first /config` | 숨김 포함 긴 목록 |
| 11 | `eza --tree --level=2 /config` | 트리 |

`>`는 sendkey 이름이 `shift-dot`이다(config/check.sh의 EDIT_KEYS가 그렇게
친다). 경로의 `-`는 `minus`, `.`는 `dot`, `/`는 `slash`다.

Acceptance: 화면에 `wc -c`의 답이 여섯 나오고, 측정 1의 셋과 측정 2의 셋이
같다. eza 넷은 각각 다른 모양의 목록을 낸다.

## Task 2 — 결과를 design에 적는다

design의 실측 절에 절 하나("실측 7 — 후보 별칭 넷은 셸 셋에서 0바이트다")를
더한다. 수치와 함께 비대화형이라는 한계를 적는다.

측정 1이 0이 아니면 M1을 시작하지 않는다 — 그 줄은 씨앗에 못 들어간다.
그때는 원인을 재는 것이 다음 일이고, 이 plan은 여기서 멈춘다.

## 지우는 것

하네스는 `/tmp/probe/m0/`에 남는다. 저장소에는 아무것도 안 들어간다.
