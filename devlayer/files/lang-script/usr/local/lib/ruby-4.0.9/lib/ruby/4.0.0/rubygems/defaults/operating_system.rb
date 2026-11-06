# TARS 개발 도구 층(TP-M4 plan 결정 E). root가 `gem install`로 깐 gem의 실행 파일은 /usr/local/bin에 선다. gem 자체는 이 ruby의
# 기본 자리(묶음 안, /usr/local의 쓰기 층 덕에 root가 쓸 수 있다)에 놓인다. --user-install은 그대로 홈이다.
module Gem
  def self.default_bindir
    "/usr/local/bin"
  end
end
