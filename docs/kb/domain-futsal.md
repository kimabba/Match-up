# 풋살 도메인 지식

## 협회 체계 (futsal_org)

| 코드 | 협회명 |
|---|---|
| kfa | 대한축구협회 |
| kff | 대한풋살연맹 |
| local | 지역 자체 |

## 등급
풋살은 테니스처럼 세분화된 등급 체계가 없음.
`user_sports.grade`에 자유 텍스트로 등록 (예: "일반", "선출" 등).

## tournaments 테이블 풋살 전용 컬럼

| 컬럼 | 설명 |
|---|---|
| entry_fee_unit | 'per_team' \| 'per_person' |
| player_count | 경기 인원 (보통 5) |
| team_count_max | 최대 참가 팀 수 |
| team_count_current | 현재 참가 팀 수 |
| roster_min / roster_max | 로스터 인원 범위 |
| venue_type | 실내/실외 |
| surface_type | 인조잔디/우레탄 등 |
| match_format | 리그/토너먼트/풀리그 |
| host_futsal_orgs | futsal_org[] 배열 |

## 클럽
풋살 클럽도 테니스와 동일한 워크플로우 (clubs.md 참조).
`clubs.sport = 'futsal'`로 구분.

## 크롤러
현재 풋살 전용 크롤러는 crawl_sources에 등록 가능하나 활성 소스 없음.
테니스 크롤러와 같은 crawl-dispatch 파이프라인 사용.
