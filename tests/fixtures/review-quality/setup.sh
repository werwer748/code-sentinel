#!/bin/bash
# tests/fixtures/review-quality/setup.sh — 리뷰 품질 검증용 임시 Git 저장소를 만든다 (SPEC §17.1).
#
# 사용법: setup.sh <fixture> <dest>
#   <fixture>  backend-api | frontend-web | infra | clean-change (이 디렉터리 아래 base/·change/ 가 있는 이름)
#   <dest>     만들 저장소 경로. 이미 있으면 빈 디렉터리여야 한다(비어 있지 않거나 파일·링크면 거부).
#
# 동작: <dest> 에 저장소를 만들고 base/ 를 main 에 커밋한 뒤, feature 브랜치를 만들어 작업 트리를
#       change/ 로 바꾸고(삭제 포함) 커밋한다. 끝나면 feature 가 체크아웃된 깨끗한 작업 트리가 남는다.
#
# 격리: 사용자 git 설정(~/.gitconfig 등)을 읽지도 바꾸지도 않는다. 이 스크립트의 git 호출에만
#       GIT_CONFIG_GLOBAL=/dev/null, GIT_CONFIG_NOSYSTEM=1 과 -c 옵션(신원, 서명 끔, 훅 끔)을 준다.
#       커밋 시각을 고정해 같은 git 버전이면 커밋 SHA 가 매번 같다.
#
# 종료 코드: 0 성공 · 1 대상 경로 거부 또는 git 실패 · 2 사용법 오류

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd -P)

usage() {
	printf '사용법: %s <fixture> <dest>\n' "$(basename "$0")" >&2
	printf '  fixture: %s\n' "$(cd "$here" && for d in */; do [ -d "$d/base" ] && printf '%s ' "${d%/}"; done)" >&2
	exit 2
}

[ $# -eq 2 ] || usage
name=$1
dest=$2

case $name in
'' | */* | .*) usage ;;
esac
fixture="$here/$name"
if [ ! -d "$fixture/base" ] || [ ! -d "$fixture/change" ]; then
	printf 'setup.sh: 알 수 없는 픽스처: %s\n' "$name" >&2
	usage
fi
[ -n "$dest" ] || usage

if [ -L "$dest" ]; then
	printf 'setup.sh: 대상이 심볼릭 링크라서 거부합니다: %s\n' "$dest" >&2
	exit 1
elif [ -e "$dest" ]; then
	if [ ! -d "$dest" ]; then
		printf 'setup.sh: 대상이 디렉터리가 아니라서 거부합니다: %s\n' "$dest" >&2
		exit 1
	fi
	if [ -n "$(ls -A "$dest")" ]; then
		printf 'setup.sh: 대상 디렉터리가 비어 있지 않아 거부합니다: %s\n' "$dest" >&2
		exit 1
	fi
else
	mkdir -p "$dest"
fi
dest=$(cd -P "$dest" && pwd -P)

case $name in
backend-api)
	msg_base='Initial shop API: products, orders and card payments'
	msg_change='Add wallet payments, invoices and catalog filters

- Store the order currency and include it in order responses
- Reserve stock when an order is created; allow cancelling pending orders
- Retry card charges when the payment gateway times out or returns 5xx
- Wallet balance payments and invoice endpoints
- Product search filters (category, max price) and category listing'
	;;
frontend-web)
	msg_base='Initial storefront: catalog and product pages'
	msg_change='Product page: reviews, deal countdown, stock badge and gallery

- Client-side catalog search on the home page
- Render merchant descriptions as sanitized HTML
- Member price, live stock badge and deal countdown on the product page
- Customer reviews with helpful votes and an add-to-cart button
- Regenerate API types and update the e2e checkout flow'
	;;
infra)
	msg_base='status-api with CI, deploy workflow and Terraform base'
	msg_change='Containerize the API, add docs previews and docs hosting

- Dockerfile for the API server
- Docs preview builds for pull requests
- Publish the docs site to S3 on pushes to main
- Public docs bucket and load balancer security groups
- Prune old releases on the host after a deploy'
	;;
clean-change)
	msg_base='list-utils 1.3.0'
	msg_change='Add paginate helper

Pages through in-memory lists for the admin list endpoints. Out-of-range
pages return an empty page instead of throwing so stale links still render.'
	;;
*)
	msg_base="Base for fixture $name"
	msg_change="Change for fixture $name"
	;;
esac

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME='code-sentinel fixture'
export GIT_AUTHOR_EMAIL='fixture@example.invalid'
export GIT_COMMITTER_NAME='code-sentinel fixture'
export GIT_COMMITTER_EMAIL='fixture@example.invalid'

g() {
	git -C "$dest" \
		-c user.name='code-sentinel fixture' \
		-c user.email='fixture@example.invalid' \
		-c commit.gpgsign=false \
		-c tag.gpgsign=false \
		-c core.hooksPath=/dev/null \
		-c core.autocrlf=false \
		-c core.fileMode=true \
		-c init.defaultBranch=main \
		"$@"
}

g init -q
g symbolic-ref HEAD refs/heads/main

cp -R "$fixture/base/." "$dest/"
g add -A
GIT_AUTHOR_DATE='2026-10-01T09:00:00Z' GIT_COMMITTER_DATE='2026-10-01T09:00:00Z' \
	g commit -q -m "$msg_base"

g checkout -q -b feature
# base 의 추적 파일을 모두 지운 뒤 change/ 를 복사해, change 에 없는 파일은 삭제로 기록되게 한다.
g rm -r -q -- .
cp -R "$fixture/change/." "$dest/"
g add -A
GIT_AUTHOR_DATE='2026-10-02T09:00:00Z' GIT_COMMITTER_DATE='2026-10-02T09:00:00Z' \
	g commit -q -m "$msg_change"

printf 'fixture\t%s\n' "$name"
printf 'repo\t%s\n' "$dest"
printf 'main\t%s\n' "$(g rev-parse main)"
printf 'feature\t%s\n' "$(g rev-parse feature)"
