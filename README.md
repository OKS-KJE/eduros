# eduros · JAN-9301 Project Room

JRC와 KJ Engineering / EDUROS가 **JAN-9301 JRC ECDIS Type Specific Training** 제안서를 함께 검토하고 프로젝트를 관리하는 페이지입니다.

| 메뉴 | 내용 |
|---|---|
| Home | 제안서 · ClassNK 가이드 · 프로젝트 룸 바로가기, 전체 일정 타임라인, 문서 현황 |
| Proposal | 제안서 14개 섹션. 섹션마다 "Review this section →" |
| ClassNK guide | ClassNK 학습 영역(a–j) × 과정 13단계 매트릭스 |
| Project room | Overview · Timeline · Proposal review · Tasks · Decisions · Documents |

상단 오른쪽 **EN / 日本語** 버튼으로 메뉴와 안내 문구의 언어를 바꿉니다.

## 일정 관리: 시작일 · 완료 예정일 · 완료일

| 대상 | 입력 위치 | 자동 처리 |
|---|---|---|
| 일정 단계(Proof of concept 등 4단계) | Timeline 탭 → Phase schedule 표 | 완료일을 넣으면 타임라인에 ✓ 표시, 상태가 Complete로 바뀜 |
| 작업(Tasks) | 작업 이름을 눌러 편집 | 상태를 Done으로 바꾸면 완료일에 오늘 날짜가 들어감 |
| 결정 사항(Decisions) | 카드의 날짜 칸 | 상태를 Agreed로 바꾸면 완료일에 오늘 날짜가 들어감 |

## 두 가지 실행 방식

`index.html` 맨 위의 `JRC_CONFIG`로 정합니다.

| | 로컬 시연 | Supabase 연결 |
|---|---|---|
| 설정 | `url`, `anonKey`를 비워 둠 (기본값) | Supabase 값 입력 |
| 데이터 | 각 브라우저에만 저장, "Reset demo"로 초기화 | Supabase에 저장, JRC와 실시간 공유 |
| 사용자 | 상단 "Demo as"로 JRC / KJ 선택 | 이메일 로그인, 소속은 멤버 명단에서 결정 |
| 문서 파일 | 브라우저 안(IndexedDB) | Supabase Storage(비공개 버킷) |

## Supabase 연결 순서

1. https://supabase.com 에서 프로젝트를 만듭니다. 리전은 Seoul 또는 Tokyo를 권장합니다.
2. `supabase/setup.sql`의 **6번 항목(members)** 주석을 풀고 참여자 이메일 · 이름 · 소속을 넣습니다.
   - `'jrc'` : JRC 담당자
   - `'kj'` : KJ Engineering / EDUROS 담당자
3. **SQL Editor → New query**에 파일 전체를 붙여 넣고 **Run**을 누릅니다. 이 한 번으로 다음이 모두 만들어집니다. 다시 실행해도 기존 데이터는 유지됩니다.
   - 테이블, 권한 규칙, 실시간 갱신
   - 초기 데이터: 섹션 13개, 작업 17개, 결정 사항 5개, 일정 단계 4개
   - 문서 저장소(`documents` 버킷)
4. **Authentication → Providers → Email**이 켜져 있는지 확인합니다.
5. **Authentication → URL Configuration**에 다음을 넣습니다.
   - Site URL: `https://oks-kje.github.io/eduros/`
   - Redirect URLs: `https://oks-kje.github.io/eduros/**`
6. **Project Settings → API**에서 Project URL과 anon public 키를 복사해 `index.html` 맨 위 `JRC_CONFIG`에 넣고 커밋합니다.

**키 관련 주의**
- `anon public` 키는 공개 저장소에 올려도 됩니다. 데이터 접근은 권한 규칙(RLS)이 막습니다.
- `service_role` 키는 절대 올리지 마십시오.

### 멤버 추가

```sql
insert into public.members (email, name, org)
values ('new.person@company.com', 'New Person', 'jrc')
on conflict (email) do update set name = excluded.name, org = excluded.org;
```

## 권한 규칙 (서버에서 강제)

- **접근:** 멤버 명단에 있는 이메일로 로그인한 사람만 데이터와 문서를 보고 수정할 수 있습니다.
- **섹션 승인:** 소속별로만 가능합니다. JRC는 JRC 칸만, KJ/EDUROS는 KJ 칸만 바꿀 수 있습니다.
- **자동 기록:** 댓글과 문서의 작성자, 소속, 시각은 로그인 정보로 자동 기록됩니다.
- **관리자 전용:** 일정 단계의 이름과 순서, 섹션 제목과 요약은 SQL Editor에서만 바꿀 수 있습니다. 멤버는 날짜만 수정합니다.
- **파일:** 문서 파일은 비공개 저장소에 보관되며, 열 때마다 10분짜리 임시 링크가 만들어집니다.
