# 망 — 유선과 Wi-Fi

TARS는 처음에 망이 꺼져 있습니다(`net=off`). 켜는 것은 사람이 합니다. 켜 두면 부팅마다 주소를 받고 망이 없어도 부팅은 기다리지 않습니다.

## 유선

랜선을 꽂고 다음을 칩니다.

```sh
sudo tars-config set net=dhcp
sudo tars-config reload
```

`reload`가 그 자리에서 주소를 받습니다. 다음 부팅부터는 저절로 받습니다.

## Wi-Fi

```sh
sudo tars-config set net=dhcp
sudo tars-config wifi '집 와이파이' --country KR
sudo tars-config reload
```

- 둘째 줄이 비밀번호를 묻습니다. 화면에 보이지 않고 기록에도 남지 않습니다.
- `--country KR`은 5GHz 채널을 엽니다. 빠뜨리면 5GHz 공유기를 찾지 못할 수 있습니다.
- 장소가 여럿이면 둘째 줄을 SSID마다 한 번씩 칩니다. 같은 SSID를 다시 치면 비밀번호만 바뀝니다.
- 지금 적힌 SSID는 `sudo tars-config wifi`(인자 없이)로 봅니다.

## 시계와 시간대

망이 있으면 시계도 맞출 수 있습니다. 시간대는 망과 상관없습니다.

```sh
sudo tars-config set ntp=dhcp timezone=Asia/Seoul
sudo tars-config reload
```

시간대는 다음에 여는 셸부터 보입니다.

## 잘 안 되면

```sh
ip -4 addr                         # 주소를 받았는지 — lo 말고 한 줄이 더 있어야 합니다
ip -4 route                        # default via … 한 줄
ping -c 3 1.1.1.1                  # 밖까지 닿는지 — 이름 풀이 없이 주소로 봅니다
sudo wpa_cli -i wlan0 status       # Wi-Fi: wpa_state=COMPLETED면 붙었습니다
sudo iw reg get                    # country KR이 보여야 합니다
sudo tars-service status dhcpcd    # 주소를 받는 일꾼이 도는지
sudo tars-config check             # 설정 파일에 틀린 줄이 있는지
```

- 무선 칩을 찾지 못하는 기계도 있습니다(오래된 Broadcom 등). `ip link`에 `wlan0`이 없으면 USB 무선 동글이나 유선을 쓰세요.
- 방화벽을 켰다면(`tars-help services`) 나가는 연결은 그대로 되고 들어오는 것만 막힙니다.

다음: `tars-help bluetooth`
