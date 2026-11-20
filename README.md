# JAN-9301 Project Room · 로컬 시연판

서버나 Supabase 없이 PC에서 바로 시연하는 버전입니다.

## 실행

1. `index.html`과 `proposal.html`을 같은 폴더에 둡니다.
2. `index.html`을 더블클릭해 Chrome이나 Edge로 엽니다.

인터넷이 없어도 작동합니다. 인터넷이 없으면 글꼴만 기본 글꼴로 바뀝니다.

## 화면 구성

| 메뉴 | 내용 |
|---|---|
| Home | 제안서 · ClassNK 가이드 · 프로젝트 룸 바로가기, 전체 일정 타임라인, 문서 현황 |
| Proposal | 제안서 14개 섹션. 섹션마다 "Review this section →" |
| ClassNK guide | ClassNK 학습 영역(a–j) × 과정 13단계 매트릭스. 칸을 누르면 해당 학습 목표(Object number) 표시 |
| Project room | Overview · Timeline(단계별 일정과 진행률) · Proposal review(양측 승인, 댓글) · Tasks · Decisions · Documents(Proposal · NDA · Contract 파일 업로드) |

## 언어 전환

상단 오른쪽 **EN / 日本語** 버튼으로 메뉴, 버튼, 안내 문구의 언어를 바꿉니다. 선택한 언어는 다음에 열 때도 유지됩니다. 제안서 본문과 섹션, 작업, 결정 사항, ClassNK 학습 항목 같은 데이터 내용은 영어 그대로 표시됩니다.

## JRC와 함께 시연하기

1. 창을 두 개 엽니다. 같은 브라우저에서 `index.html`을 한 번 더 열면 됩니다.
2. 한 창은 상단 **Demo as → JRC**, 다른 창은 **KJ Engineering / EDUROS**를 고릅니다.
3. 한쪽에서 승인하거나 댓글을 달면 다른 창에 바로 반영됩니다.

## 데이터

- 시연 중 바꾼 내용은 이 브라우저에만 저장됩니다. 다른 PC나 다른 브라우저와는 공유되지 않습니다.
- 올린 문서 파일도 이 브라우저 안(IndexedDB)에만 저장됩니다. 파일 하나당 20 MB까지 올릴 수 있습니다.
- 상단 **Reset demo**를 누르면 처음 상태로 돌아가고, 올린 파일도 지워집니다.
- 실제 운영(여러 회사가 각자 PC에서 접속)은 Supabase 버전(`eduros.zip`)을 사용하십시오.

## ClassNK 가이드 출처

JRC Course outline Rev. 0.0, §3.2 "Covering the learning area of the NK standard"
- 학습 영역 10개(a–j)
- 학습 목표 37개 (Object number 1.1–11.1)
- 매핑된 과정 단계: 1–11단계. 12단계(기존 ECDIS 운용)와 13단계(MCQ 시험)는 학습 영역에 직접 매핑되지 않습니다.
