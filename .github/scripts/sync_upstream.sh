#!/usr/bin/env bash
# 상류(halfaider/SjvaAgent.bundle) main을 현재 브랜치에 병합한다. 푸시는 하지 않는다.
# 새 커밋이 없으면 아무것도 하지 않고, 병합했으면 VERSION을 올려 PLEX MATE가 업데이트를 감지하게 한다.
# 충돌이 version.py 하나뿐이면 포크 쪽 내용을 유지하고, 그 밖의 충돌은 실패시켜 사람이 풀게 한다.
set -euo pipefail

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/halfaider/SjvaAgent.bundle.git}"
VERSION_FILE="Contents/Code/version.py"

git fetch --quiet "$UPSTREAM_URL" main
upstream=$(git rev-parse FETCH_HEAD)

if git merge-base --is-ancestor "$upstream" HEAD; then
    echo "상류에 새 커밋이 없습니다."
    exit 0
fi

upstream_version=$(git show "$upstream:$VERSION_FILE" | sed -n "s/^VERSION = '\(.*\)'.*/\1/p" | head -1)
echo "상류 새 커밋 $(git rev-list --count "HEAD..$upstream")개 (상류 버전 ${upstream_version:-알 수 없음})"

if ! git merge --no-commit --no-ff "$upstream"; then
    conflicts=$(git diff --name-only --diff-filter=U)
    if [ "$conflicts" != "$VERSION_FILE" ]; then
        echo "::error::자동으로 풀 수 없는 충돌입니다. 직접 병합해 주세요: $(echo $conflicts)"
        git merge --abort
        exit 1
    fi
    # 양쪽이 모두 파일 맨 위에 버전 기록을 쓰기 때문에 생기는 충돌이다. 포크 기록을 유지한다
    git checkout --ours -- "$VERSION_FILE"
fi

# 버전 문자열이 달라져야 서버가 새 코드를 받는다. 같은 날 두 번 병합해도 겹치지 않게 실행 번호를 붙인다
new_version="$(date -u +%Y.%m.%d).s${GITHUB_RUN_NUMBER:-0}"
short=$(git rev-parse --short "$upstream")
python3 - "$VERSION_FILE" "$new_version" "${upstream_version:-?}" "$short" <<'PY'
import io, re, sys
path, new_version, upstream_version, short = sys.argv[1:]
text = io.open(path, encoding='utf-8', newline='').read()
nl = '\r\n' if '\r\n' in text else '\n'
text, count = re.subn(r"^VERSION = '.*?'", "VERSION = '%s'" % new_version, text, count=1, flags=re.M)
assert count == 1, 'VERSION 줄을 찾지 못했습니다'
note = '%s%s  - halfaider %s (%s) 병합%s%s' % (new_version, nl, upstream_version, short, nl, nl)
head, sep, tail = text.partition('"""' + nl)
assert sep, '버전 기록 블록을 찾지 못했습니다'
io.open(path, 'w', encoding='utf-8', newline='').write(head + sep + note + tail)
PY
git add "$VERSION_FILE"
git commit --quiet -m "chore(sync): halfaider ${upstream_version:-?} (${short}) 병합, version ${new_version}"
echo "병합 완료: version ${new_version}"
