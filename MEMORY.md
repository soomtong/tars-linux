# MEMORY

이 저장소에서 세션을 넘어 유지되는 기억의 **색인**이다. 본문은
`docs/decisions/`에 한 파일씩 들어 있다. 새 기억은
`docs/decisions/<name>.md`를 만들고 여기에 **한 줄만** 추가한다 — 본문을 이
파일에 쓰지 않는다. 줄이 길어지면 그것은 본문이 색인으로 새어 나온 것이다.

파일 안의 `[[name]]` 링크는 `docs/decisions/`의 같은 이름 파일을 가리킨다.

현재 진행 상황은 기억이 아니라 `HANDOFF.md`에 있다.

## 협업 방식 (feedback)

- [Commit delegation](docs/decisions/feedback_commit_delegation.md) — 승인된 뒤의 git commit은 Claude가 만든다
- [Execution scope](docs/decisions/feedback_execution_scope.md) — 빌드·QEMU·게이트 명령은 Claude가 직접 실행하고(2026-08-22 변경), 구현 파일 편집만 사용자에게 남긴다
- [Design question load](docs/decisions/feedback_design_question_load.md) — 설계 중 기술 선택지를 계속 묻지 말고 추천안으로 정해 진행한다
- [Push policy](docs/decisions/feedback_push_policy.md) — push는 묻지 말고 필요할 때 하고, 미푸시 커밋 수를 보고하지 않는다
- [Plain Korean](docs/decisions/feedback_plain_korean.md) — 비유적 표현을 일반 어휘 자리에 쓰지 않는다. 평범한 한국어가 어색하면 영어를 섞어도 된다. 조사와 어미를 생략하지 않고 부사·보조사·보조용언을 적극적으로 쓴다. 특히 제목과 첫 문장. **동사 "서다"("계획이 섰다"·"뜻이 선다")가 두 번 걸렸다.**

## 사용자 (user)

- [Learning goal](docs/decisions/user_learning_goal.md) — 목적은 속도가 아니라 이해다

## 프로젝트 (project)

- [Boot Foundation restart](docs/decisions/project_boot_foundation_restart.md) — 새 저장소에서 재시작한 이유와 첫 서브프로젝트 범위
- [Zig rewrite intent](docs/decisions/project_zig_rewrite_intent.md) — Rust를 Zig로 옮긴 의도와 결말(2026-08-13 완료, 이제 Rust는 없다)
- [Zig ↔ C UAPI rule](docs/decisions/project_zig_c_uapi_rule.md) — 시스템 콜만 쓰면 libc를 링크하지 않는다; `@cImport`가 되는 것과 안 되는 것; **fortify는 끌 수 있고(GL-M3) 벽은 한 파일이 아니라 glibc를 읽는 블록 전부다**
- [Build host arch](docs/decisions/project_build_host_arch.md) — 호스트는 arm64, 게스트 산출물은 x86_64 크로스; `--platform` 금지
- [Init supervisor](docs/decisions/project_init_supervisor.md) — PID 1은 셸이 되지 않고 자식 둘을 감독한다; 감독 루프의 순서가 backoff를 만든다
- [Power management](docs/decisions/project_power_management.md) — ACPI·종료 경로 셋·시그널 핸들러가 없으면 관측조차 안 되는 성질
- [Device discovery](docs/decisions/project_device_discovery.md) — 입력 장치를 번호가 아니라 성질로 찾는다; AT 키보드도 `KEY_POWER`를 갖고 있다
- [Config persistence](docs/decisions/project_config_persistence.md) — 설정은 `/config/tars.conf` 하나, 파서는 PID 1 한 벌, 영속성은 두 번 부팅으로만 증명된다
- [Guest environment](docs/decisions/project_guest_environment.md) — 게스트에 `PATH`가 없다(외부 명령은 절대 경로); `TERM`은 셸마다 다르고 그 terminfo는 initrd에 직접 넣어야 한다; **로케일도 마찬가지다**(HI-M1) — `libc6`에 로케일 데이터가 없어 `libc-bin`의 `/usr/lib/locale/C.utf8`을 따로 넣어야 하고, **`LANG`만 설정하면 `setlocale`이 조용히 실패해 셸이 한글을 바이트로 읽는다**
- [Input policy](docs/decisions/project_input_policy.md) — evdev 코드를 셸이 아는 바이트로 번역하는 세 단계; 키보드 차이는 맨 앞에서 한 번만 보정하고, 반환은 "바이트열 또는 동작"이라 스크롤 키가 PTY로 안 샌다
- [Terminal rendering](docs/decisions/project_terminal_rendering.md) — 색·오프셋·스크롤은 `vt.zig`에서 확정하고 렌더러는 숫자만 받는다; 스크롤백 한도는 값 둘을 함께 줘야 걸린다, 라이브러리에 대해 짐작하면 틀리는 것 셋, NUL이 `grep`을 막는 성질, 죽은 검사가 남기는 구멍
- [Font selection](docs/decisions/project_font_selection.md) — 후보를 가르는 것은 커버리지가 아니라 16px 중간값 비율이다; 현재 폰트(unifont 17.0.03)의 실측값과 다시 바꿀 때 고칠 자리 열
- [Kernel config](docs/decisions/project_kernel_config.md) — `olddefconfig`가 적어 둔 설정과 빌드하는 설정을 가른다; 게이트 시간의 근원은 부팅이 아니라 커널 빌드다
- [Gate chain composition](docs/decisions/project_gate_chain_composition.md) — 체인을 더하고 빼는 규칙; 게이트는 자기가 안 보는 것을 통과시킨다
- [Boot shell selection](docs/decisions/project_boot_shell_selection.md) — 부팅 셸을 고르고 기억하는 미래 기능(영속 저장소가 선행 조건)
- [Copy mode](docs/decisions/project_copy_mode.md) — 스크롤백 위의 vim modal 선택 모드와 Cmd+V; CM-M2(2026-08-26)로 서브프로젝트가 끝났다. Cmd+V가 키 표 **두 곳**에 있어야 한다는 것, 가지치기가 pin을 무효로 만들지 않는다는 것, bracketed paste를 안 쓴다는 것이 여기 있다
- [Copy navigation](docs/decisions/project_copy_navigation.md) — copy 커서에 얹은 이동 수단 둘; **CN-M0(단어 이동 `w`/`b`)과 CN-M1(검색 `/`·`n`·`N`)이 2026-08-27에 끝나 종료됐다.** 라이브러리의 "단어"에 **공백 덩어리가 포함된다**는 것, `pointFromPin`이 뷰포트 **아래쪽 밖을 안 알려준다**는 것, `Terminal.ScrollViewport`에 `.pin`이 없다는 것, `ScreenSearch`가 우리 선택을 안 건드린다는 것, `Select.next`의 주석과 달리 **코드는 감긴다**는 것, **QEMU `sendkey`의 키 이름이 전부 소문자**라는 것이 여기 있다
- [Copy search feedback](docs/decisions/project_copy_search_feedback.md) — 검색이 사람에게 보이게 만든 층; **CS-M0·CS-M1이 2026-08-28에 끝나 종료됐다.** `matches()`가 준 목록이 **다음 `select()`에서 죽는다**는 것, 매치는 맞바꿈이 아니라 **값을 정하는 층**이어야 한다는 것(선택 안에서 상쇄된다), `pointFromPin`이 뷰포트 **위**의 pin에 대해 목록 끝까지 훑으므로 **좌표 푸는 방향을 뒤집었다**는 것, "못 찾음" 메시지의 글자가 **`find_last`에서 올 수밖에 없다**는 것, **이 게이트에서 처음 재는 값은 TCG 번역 비용을 포함한다**는 것(같은 검색이 첫 번째 62ms · 세 번째 19ms)이 여기 있다
- [Search position](docs/decisions/project_search_position.md) — 검색에서 "지금 몇 번째 매치인가"를 꺼내는 자리와 그 위에 세운 색·번호; **SP-M0(현재 매치를 `#C08000`으로)과 SP-M1(`/needle [3/12]`)로 2026-08-29~30에 종료됐다.** 라이브러리의 `selected.idx`와 `matches()` 슬라이스가 **같은 좌표계**라는 것, 색이 둘이 되면 `break`의 뜻이 "최적화"에서 "목록 순서가 색을 정한다"로 바뀐다는 것, **한 색만 세는 음성 검사는 그 색이 안 쓰이게 되면 아무것도 안 보는 검사가 된다**는 것, 한 줄에 매치 둘을 심으면 판정이 스크롤에 안 딸린다는 것, **상태 플래그를 새로 만들지 않고 CS-M1의 것을 넓혀 켜고 끄는 자리를 한 벌로 뒀다**는 것, `promptText`가 private이라 **번호의 재료는 `vt_test`가 글자는 게이트가 나눠 본다**는 것, 그리고 **검사 15의 102줄이 `n`이 아니라 `/`가 커서 자리의 매치를 건너뛴 것**이었다는 것이 여기 있다
- [Gate latency](docs/decisions/project_gate_latency.md) — 게이트 54분 15초 → 18분 08초(GL-M0·M1) → 22분대(CN·CS의 타이핑) → 19분 11~16초(GL-M2) → **16분 01~11초(GL-M3, 2026-08-29)**; 54분의 8할은 같은 산출물을 24번 빌드하는 비용이었다, "빌드가 최신인가"를 mtime으로 판정하려는 시도는 **두 번 다 실패했고** 내용 해시로 가야 한다, gzip -9는 값을 못 한다, **고정 대기는 관측으로 바꾼다**(그러면 그 뒤의 성능 개선이 게이트 시간으로 흘러든다), **`key>` 줄 수는 키 개수가 아니다**(배칭 — 세려면 바이트 합), **게이트가 부팅하는 바이너리가 곧 제품이라 최적화 기본값은 배포되는 것과 같아야 한다**
- [Render cost](docs/decisions/project_render_cost.md) — 한 프레임의 비용을 구간별로 갈라 잰 결과; **RC-M0(2026-08-30)로 종료됐고 저장소 코드는 한 줄도 안 바뀌었다.** 답이 **`fill`**(프레임 21.3ms 중 18.0ms, 84.7%)이라는 것, **프레임버퍼 쓰기는 픽셀 수에 정비례한다**는 것(91,520px과 1,024,000px이 8.11 대 8.27 ns/px), **`cells()`가 격자 전체를 안 준다**는 것(`ls` 뒤 화면이 7,285셀이 아니라 911셀), 그래서 **`fill`은 여백 담당이 아니라 화면 지우개이고 여백으로 좁히는 처방은 한 픽셀도 못 아낀다**는 것, **`present`의 매 프레임 모드셋은 4%라 급하지 않다**는 것, **시리얼 한 줄이 0.6~8.8ms**라 시간 재는 구간에 `print`를 두면 안 된다는 것, **검산(합 대 total)이 통과해도 잰 것의 뜻이 맞는다는 보장은 없다**는 것, **고정된 일의 비용은 중앙값이 아니라 최소값으로 비교한다**는 것이 여기 있다
- [Target hardware](docs/decisions/project_target_hardware.md) — **TARS는 노트북 사용을 포함한다**(사용자, 2026-08-31); 그래서 실머신 `.config`는 서브프로젝트 하나이지 `ACPI_EC` 한 줄이 아니다 — 지금 `EFI`·`USB_SUPPORT`·`NVMe`·`PCI_MSI`·`DRM_I915`·`THERMAL`이 전부 꺼져 있어 **이 커널은 노트북에서 아예 못 뜬다**; **게이트는 이 방향을 검증할 수 없다**(QEMU에 EC가 없다)
- [Carryover cleanup](docs/decisions/project_carryover_cleanup.md) — 이월 숙제 셋을 없앤 CC-M0(2026-08-31); **게스트에 명령을 넣는 길은 `-serial stdio` + FIFO이고 그 FIFO는 `<>`로 열어야 안 막힌다**는 것, fish에서 `(...)`는 command substitution이라 글로브를 감싸면 안 된다는 것, **`PNP_DEBUG_MESSAGES`를 꺼도 `i8042: PNP:`와 `ttyS0 at I/O` 줄은 그대로 나온다**는 것(그 줄들은 `pnp_dbg`가 아니라 `pr_info`다), **vendor한 것이 쓰이는지는 지우고 빌드해 보는 것으로 증명한다**는 것, **`ACPI_EC`는 실머신으로 갈 때 되켜야 한다**는 것이 여기 있다
- [Hangul input](docs/decisions/project_hangul_input.md) — 한글을 치는 층(HI, 2026-08-31 착수 · **완료 2026-09-01, HI-M0~M3**); **자판 넷의 겹침 구조가 서로 반대라**(두벌식은 초성∩종성 19, 신세벌은 중성∩종성 15) 자판이 `{초성?,중성?,종성?}` **후보**를 주고 조합 상태가 우선순위로 고른다는 것, **"종성 자리가 차 있으면 종성이 중성보다 먼저"**(신세벌 `cc`=ㄲ받침이 유일한 증거), 자판에 딸리는 것은 셋뿐이고(받침 넘기기·연타 된소리·**겹모음을 여는 키인가**) 겹모음·겹받침 표는 넷이 공유한다는 것, **종성만 상태도 호환 자모로 그려진다**(`ㄳ`·`ㄺ`이 `cell_width=16`), **표를 옮겨 적는 실수는 원본이 문서일 때 나고 코드일 때는 안 났다**는 것, `config_test`의 비교 함수가 필드 둘만 보고 있어서 새 검사 여섯이 아무것도 안 볼 뻔한 것, **같은 세션의 게이트 삼중값은 폭이 2.29초**(±3분 잡음은 다른 날 측정의 것)라는 것; 자판 여섯 벌(두벌식·공세벌 3-P3·신세벌 P2·신세벌 PCS·쿼티·드보락, **기본값은 shin_pcs와 qwerty**)과 **조합 중인 글자를 PTY로 안 보내고 커서 자리에 우리가 그린다**는 결정, 자판 맵의 `"k"`가 글자가 아니라 **쿼티에서 k가 있는 물리 자리**의 이름이라 영문 배열과 직교한다는 것, **모아주기를 뺀 근거**(unifont에 첫가끝 글리프가 있어도 U+1103과 U+11AB이 호환 자모와 똑같은 9×9 `x_off=+4`라 포개면 두 글자가 겹칠 뿐이다), **`sendkey lang1`은 QEMU가 이름만 받고 PS/2로 옮기며 조용히 버린다**는 것(`atkbd: Unknown key` 경고조차 없다 — 그래서 한/영 키는 게이트로 검증할 수 없다), **`sendkey <key> <hold_ms>`는 오차 4ms 안이라 tap-vs-hold를 게이트가 볼 수 있다**는 것, evdev 시각이 `ev.time.tv_sec`으로 이미 손에 있다는 것, **"그릴 수 없는 상태는 코드포인트가 없다"와 "오토마타가 그 상태를 안 만든다"는 검사 둘이 짝이어야 한다**는 것(3-순열 107,811단계에서 0번)이, 그리고 HI-M1의 셋 — **확정된 글자는 `Action`이 못 나른다**(조합을 끝내는 키가 자기 몫의 결과를 따로 갖고 union은 하나만 담는다 → `commit_buf`/`takeCommit()`을 두고 `readKeys`가 그 키의 바이트보다 **먼저** 비운다), **커서는 조합 중에 두 칸을 반전해야 한다**(한 칸이면 `drawGlyph`가 16픽셀을 셀 하나의 `fg`로 찍어 글자의 오른쪽 절반이 사라진다), **시리얼 로그가 CRLF라 `sed`의 `([^ ]+)`가 줄 끝 값에서 CR을 삼켜 "똑같아 보이는 값으로 실패"한다**가 여기 있다; 그리고 HI-M3의 넷 — **전환 키가 넷이고 `hangul_toggle`이 고른다**(기본은 넷 다 켜짐, 사용자가 정했다), **`\r\?$`는 grep의 BRE에서 아무 뜻도 없다**(GNU grep은 `-P` 없이 `\r`을 리터럴 `r`로 읽는다 → CRLF 로그의 줄 끝 앵커는 `tr -d '\r'`로), **tap 소비 표시는 modifier switch 앞에 두어야 한다**(Shift·Alt·Meta가 switch 안에서 return한다), **CapsLock은 뗄 때 뒤집는다**(누를 때 뒤집으면 tap을 만들 수 없다), **대문자 잠금의 판단 근거는 키 코드가 아니라 Shift 안 누른 칸의 값**이라 드보락에서도 표가 한 벌이다
