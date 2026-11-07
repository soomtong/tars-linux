# TARS 첫걸음

설치를 마치고 처음 켰다면 아래 순서대로 하시면 됩니다. 장마다 `tars-help <주제>`로 엽니다.

1. 망을 켭니다 — 유선은 한 줄, Wi-Fi는 세 줄입니다. 기본은 망이 꺼져 있습니다. `tars-help network`
2. 블루투스 키보드 · 마우스를 짝짓습니다. 기본은 꺼져 있습니다. `tars-help bluetooth`
3. 설정이 어디에 남는지, 무엇을 고칠 수 있는지 봅니다. `tars-help config`
4. 바깥에서 붙을 것(ssh)과 방화벽, 부팅 때 뜨는 서비스를 다룹니다. `tars-help services`
5. 깔려 있는 언어 · 편집기 · 도구와 문서 받기입니다. `tars-help devtools`

화면 · 키보드 · 한/영 · 소리 · 밝기 · 받아쓰기는 `tars-help desk`에 있습니다.

## 먼저 알아 둘 것

- 화면의 셸은 사용자 `tars`로 뜹니다. 설정을 바꾸는 명령에는 `sudo`를 붙입니다. 비밀번호는 설치할 때 정한 것입니다.
- 설정은 `tars-config` 하나로 보고 고칩니다. `tars-config`만 치면 지금 설정이, `tars-config help`를 치면 쓰는 법 전부가 나옵니다.
- 고친 설정은 대부분 재부팅 없이 `sudo tars-config reload`로 바로 반영됩니다.
- 주제 목록은 `tars-help --list`로 봅니다.
