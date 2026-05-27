# 클럽 관리 시스템

## 워크플로우

```
사용자 → clubs-create → clubs.status='pending'
                          + club_members에 owner 자동 등록
                          ↓
어드민 → clubs-approve → status='approved' 또는 'rejected'
                          ↓ (approved)
다른 사용자 → clubs-join(action:'request') → club_join_requests.status='pending'
                          ↓
owner/manager → clubs-review-join → 'approved' → club_members에 member 추가
                                    'rejected' → 신청 거절
```

## 역할 체계

| 역할 | 권한 |
|---|---|
| owner | 가입 신청 승인/거절, 클럽 정보 관리 (탈퇴 불가) |
| manager | 가입 신청 승인/거절 |
| member | 일반 멤버 (탈퇴 가능) |

## Edge Functions

### clubs-create
- `POST { sport, name, region?, address?, contact?, website?, description? }`
- 인증: requireUser
- clubs에 status='pending'으로 insert + club_members에 owner 등록

### clubs-join
- `POST { club_id, action: 'request'|'cancel'|'leave', message? }`
- request: 승인된 클럽에만, 이미 멤버면 409
- cancel: pending 신청만 삭제
- leave: owner는 불가 ("Transfer ownership first")

### clubs-review-join
- `POST { request_id, action: 'approve'|'reject' }`
- 인증: owner/manager 또는 admin
- approve → club_members에 member 추가

### clubs-approve
- `POST { club_id, action: 'approve'|'reject', reason? }`
- 인증: requireAdmin
- reject 시 status_reason 저장

### clubs-search
- `GET ?sport=&region=&q=&mine=true`
- 일반: status='approved' 클럽만
- mine=true: serviceClient로 club_members 조회 → 내가 멤버이거나 생성한 클럽 + role 정보 주입

## Flutter UI

- `clubs_screen.dart` — "내 클럽" / "클럽 찾기" 탭 + FAB(클럽 만들기)
- `clubs/club_create_screen.dart` — 클럽 생성 폼 (종목 선택, 관리자 승인 안내)
- `admin_screen.dart` — "클럽 승인" 4번째 탭 (pending 클럽 목록)

## 멤버 수 자동 갱신
club_members의 INSERT/UPDATE/DELETE 시 `update_club_member_count` 트리거가 clubs.member_count를 자동 갱신
