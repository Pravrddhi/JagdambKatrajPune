# Maintenance Flow and Validations

## Purpose
This document describes the current maintenance workflow and validation rules in the app.
It is aligned with the active code paths in the maintenance module and keeps the business validations unchanged.

## Scope
- Maintenance events lifecycle
- Inventory stock request lifecycle
- Maintenance completion lifecycle
- Approval permissions and ownership checks
- `maintenance_id` data linkage

## Key Data Linkage
- Primary ownership and linkage key: `maintenance_id`
- Inventory request payload includes optional `maintenance_id` and `event_id`.
- Completion request payload uses `maintenance_id` and optional `event_id`.
- UI matching for completion and stock usage is resolved using `maintenance_id` as the authoritative key.

## High-Level Flow
1. Admin creates or manages a maintenance event.
2. Participant starts maintenance (creates participant maintenance record).
3. Participant raises stock requests linked to the maintenance record.
4. Approver/admin approves or rejects stock requests.
5. Participant submits maintenance completion request (notes and optional used items).
6. Approver/admin approves or rejects completion request.
7. Admin can close maintenance event.

## Detailed Flow and Validations

### 1. Event Availability and State
- Completion request form cannot open if event is closed.
- Completion request form can open only for the latest active maintenance event.
- If the day is not latest active, submission is blocked with an explanatory message.

### 2. Completion Submission Validations
- If current user already has completion for that day in `pending` or `approved`, new completion is blocked.
- Duplicate prevention is user-scoped, not global for all users.
- Completion submission supports stock usage, but stock usage is optional.

### 3. Stock Request Linkage and Filtering
- Stock requests can be created with:
  - `inventory_item_id`
  - `requested_quantity`
  - `note`
  - optional `maintenance_id`
  - optional `event_id`
- User-facing lists and pending checks are user-scoped using ownership filters.
- Approved stock shown for completion usage is linked by `maintenance_id`.

### 4. Approval and Permission Validations
- Inventory request approval/rejection requires appropriate approver role.
- Completion approval/rejection requires appropriate approver role.
- Approvers are restricted to allowed event/gat scope where applicable.
- Unauthorized approval action is blocked with explicit error/snack message.

### 5. Event Close Behavior
- Admin can close maintenance event via close API.
- After close action, UI reloads event, completion, and maintenance datasets.
- Closed event blocks new completion submissions.

## API Contracts Used

### Inventory Requests
- Fetch: `fetchInventoryRequests(status)`
- Create: `createInventoryRequest(...)`
- Act (approve/reject): `actOnInventoryRequest(...)`

### Completion Requests
- Fetch: `fetchCompletionRequests(...)`
- Create: `createCompletionRequest(maintenanceId, eventId, workNotes, usedItems)`
- Act (approve/reject): completion action endpoint via service layer

### Events
- Close event: `closeMaintenanceEvent(eventId)`

## Validation Matrix

### Completion Submit
- Block when event is closed: Yes
- Block when event is not latest active day: Yes
- Block when same user already has pending completion for day: Yes
- Block when same user already has approved completion for day: Yes
- Require stock-used items: No (optional)

### Approval Actions
- Require approver permission: Yes
- Restrict by assigned scope (event/gat): Yes
- Allow unauthorized users: No

## Notes on Non-Functional Behavior
- Parsing is defensive for API responses (nullable and fallback-safe decoding).
- Status normalization may infer approved state from approval metadata.
- UI refreshes are triggered after create/approve/close actions for consistency.

## Source References
- `lib/services/maintenance_service.dart`
- `lib/models/maintenance_models.dart`
- `lib/screens/dhol_maintenance_screen.dart`
- `lib/screens/home_screen.dart`

## Last Updated
- 2026-06-09
