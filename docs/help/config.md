# 설정 — 무엇이 남고 어떻게 고치나

## 무엇이 남나

디스크에 설치한 기계는 두 자리가 재부팅을 넘어 남습니다.

- `/config` — 시스템 설정입니다. `tars.conf`(아래), Wi-Fi, ssh 키, 방화벽, 블루투스 짝, 서비스가 여기 있습니다.
- `/home/tars` — 당신의 파일과 셸 설정입니다. `sudo`로 깐 것(`/usr/local`)도 여기 아래에 남습니다.

그 밖(`/etc`, `/tmp`, `/var` 등)에서 고친 것은 재부팅하면 사라집니다. 시스템은 매번 깨끗하게 뜹니다.

## tars-config

`/config/tars.conf`를 보고 고치는 명령입니다. 손으로 편집하지 않아도 됩니다.

```sh
tars-config                               # 지금 설정 — 기본값 그대로인 줄은 # 로 보입니다
tars-config list                          # 모든 키와 기본값, 받는 값
tars-config get shell                     # 값 하나
sudo tars-config set shell=zsh            # 바꾸기. 틀린 값은 그 자리에서 거절됩니다
sudo tars-config reset shell              # 기본값으로
sudo tars-config check                    # 설정 파일에 틀린 줄이 있는지
sudo tars-config reload                   # 고친 것을 지금 반영
```

자주 쓰는 키입니다.

| 키 | 기본 | 뜻 |
|---|---|---|
| `shell` | `fish` | 화면의 셸 — `bash` · `zsh` · `fish` |
| `net` · `ntp` · `timezone` | 꺼짐 · 꺼짐 · `UTC` | `tars-help network` |
| `bluetooth` | `off` | `tars-help bluetooth` |
| `firewall` | `off` | `tars-help services` |
| `keyboard` · `hangul_layout` · `hangul_toggle` | `auto` · `shin_pcs` · 넷 다 | `tars-help desk` |

`reload` 뒤 망 · 방화벽 · 서비스는 바로 바뀌고, 셸과 시간대는 다음에 여는 셸부터 바뀝니다. 화면 쪽 키(자판 · 키보드 · 클립보드 · 배율 · 전체 화면)는
`sudo tars-config reload terminal`로 화면을 다시 띄워야 바뀝니다 — 열린 패널이 모두 닫힙니다.

## sudo 비밀번호

```sh
sudo tars-config passwd
```

## 셸 설정과 별칭

셸 설정 파일은 홈에 있습니다 — `~/.bashrc`, `~/.zshrc`, `~/.config/fish/config.fish`. 처음 켤 때 한 번 깔리고 그 뒤로는 당신의
것입니다(시스템이 다시 덮지 않습니다). 처음부터 들어 있는 별칭은 다음과 같습니다.

| 치는 것 | 하는 일 |
|---|---|
| `ls` · `ll` · `la` | `eza` — 목록 · 긴 목록 · 숨김 포함 |
| `lt` · `ltt` | 고친 때 · 바뀐 때 순으로 긴 목록 |
| `z <조각>` | 자주 간 디렉터리로 갑니다(zoxide) |
| `Ctrl+R` | 쳤던 명령을 찾습니다(fzf). `Ctrl+T`는 파일 |

git의 기본 설정은 `~/.gitconfig`에 있습니다. 이름과 메일은 직접 넣습니다.

```sh
git config --global user.name '이름'
git config --global user.email 'me@example.com'
```

## 셸이 안 뜨면

셸 설정에 넣은 한 줄이 셸을 죽이면, 세 번 죽은 뒤 설정 파일 없이 한 번 더 뜹니다. 그 셸에서 설정 파일을 고치세요.
셸이 멈춰서 아무것도 칠 수 없으면 부팅 메뉴에서 커널 명령 줄 끝에 `tars.noconfig`를 더해 한 번 띄웁니다. 그 부팅은 설정 파일을
읽지 않습니다.

다음: `tars-help services`
