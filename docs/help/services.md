# 서비스 · 방화벽 · ssh

## 서비스 보기와 다시 띄우기

TARS의 첫 프로세스(init)가 서비스를 띄우고 지켜봅니다 — 죽으면 다시 띄웁니다. 그 상태를 보고 일을 시키는 명령이 `tars-service`입니다.

```sh
sudo tars-service status               # 전부
sudo tars-service restart dhcpcd       # 하나를 다시 띄웁니다
sudo tars-service stop sshd            # 이번 부팅 동안 멈춥니다
sudo tars-service start sshd
```

`stop`은 이번 부팅까지만입니다. 다음 부팅에는 다시 뜹니다.

## 내 서비스 두기

`/config/services.d/`에 실행 파일을 두면 부팅 때 뜨고, 죽으면 다시 뜹니다.

```sh
sudo mkdir -p /config/services.d
sudo vi /config/services.d/hello       # 첫 줄은 #!/bin/sh
sudo chmod +x /config/services.d/hello
sudo tars-config reload                # 지금 띄웁니다
```

- 첫 줄은 `#!/bin/sh`로 씁니다(`#!/bin/bash`는 뜨지 않습니다).
- 오래 도는 프로그램 하나를 띄우는 것이면 마지막을 `exec 프로그램`으로 끝냅니다.
- 영영 끄려면 그 파일을 지우고 `sudo tars-config reload`를 칩니다.

## 방화벽

기본은 꺼져 있습니다 — 이 기계가 연 포트에 누구나 붙을 수 있습니다. 켜면 들어오는 연결을 막고 연 포트만 받습니다. 나가는 연결은 그대로입니다.

```sh
sudo tars-config set firewall=on
sudo tars-config firewall allow 22         # ssh
sudo tars-config firewall allow 8080       # 웹 서버 등
sudo tars-config reload
sudo nft list ruleset                      # 지금 선 규칙
```

닫으려면 `sudo tars-config firewall deny 8080`을 칩니다.

## ssh로 붙기

다른 컴퓨터에서 이 기계로 붙습니다. 키로만 되고 비밀번호 로그인은 없습니다.

```sh
sudo tars-config ssh-key add 'ssh-ed25519 AAAA… me@laptop'   # 다른 컴퓨터의 ~/.ssh/id_ed25519.pub 한 줄
sudo tars-config ssh on
sudo tars-config reload
ip -4 addr                                                   # 이 기계의 주소
```

다른 컴퓨터에서 `ssh root@<그 주소>`로 붙습니다. 방화벽을 켰다면 22를 엽니다(위). 붙은 셸은 화면의 셸과 같은 설정을 씁니다.
`less`가 "terminal is not fully functional"이라고 하면 `TERM=xterm-256color ssh root@<주소>`로 붙으세요.

다음: `tars-help devtools`
