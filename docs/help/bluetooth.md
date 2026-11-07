# 블루투스 — 키보드와 마우스

처음에는 꺼져 있습니다(`bluetooth=off`). 키보드 · 마우스까지 됩니다. 이어폰 · 스피커 같은 소리 장치는 되지 않습니다.

## 켜고 짝짓기

처음 짝지을 때는 `bluetoothctl`을 칠 키보드(유선 · 내장)가 한 번은 있어야 합니다.

```sh
sudo tars-config set bluetooth=on
sudo tars-config reload
sudo bluetoothctl
```

장치를 짝짓기 모드로 둔 뒤 `bluetoothctl` 안에서 차례로 칩니다.

```
scan on                        # [NEW] Device AA:BB:CC:DD:EE:FF 이름 이 보이면
pair AA:BB:CC:DD:EE:FF
trust AA:BB:CC:DD:EE:FF        # 빠뜨리면 다음에 장치가 다시 붙지 못합니다
connect AA:BB:CC:DD:EE:FF
quit
```

붙는 순간부터 그 키보드로 칠 수 있습니다. 짝지은 것은 재부팅해도 남아서, 장치를 켜면 다시 붙습니다.

## 잘 안 되면

```sh
sudo bluetoothctl list                     # 어댑터가 하나라도 있는지
sudo bluetoothctl show                     # Powered: yes 인지
sudo bluetoothctl info AA:BB:CC:DD:EE:FF   # Paired · Trusted · Connected
sudo tars-service restart bluetoothd       # 블루투스 일꾼을 다시 띄웁니다
sudo dmesg | grep -i bluetooth             # 어댑터가 없으면 커널이 칩을 봤는지
```

- 어댑터가 없으면 그 기계의 블루투스 칩을 TARS가 아직 모르는 것입니다(Broadcom 등). USB 블루투스 동글은 대신 쓸 수 있습니다.
- 키보드 배열(Mac · PC)과 한/영 전환은 `tars-help desk`에 있습니다.

다음: `tars-help config`
