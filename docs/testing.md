# Testing

This document describes the manual acceptance, failure, recovery, transaction,
run-admission, and concurrency tests performed for the ABAP Cloud OData
Acquisition project.

The goal of the test suite is not only to verify successful OData acquisition,
but also to verify operational behavior when a run fails, is interrupted,
is retried, collides with another run, or encounters a database error.

The tests described here were executed against the same implementation that is
stored in this repository.

---

## Test environment

The project was tested in SAP BTP ABAP Environment / ABAP Cloud using ADT in
Eclipse.

External source:

`https://services.odata.org/V4/Northwind/Northwind.svc/`

Entity set:

`Products`

The public Northwind service required no authentication.

The complete demo snapshot contained 77 products during testing.

Testing used:

- normal execution through `ZCL_NW_RUN`;
- direct execution through `ZCL_NW_TEST_DRIVER`;
- controlled persisted-data preparation through `ZCL_NW_TEST_RUN`;
- ADT debugger breakpoints;
- manual inspection of `ZNW_ACQ_STATE`;
- manual inspection of `ZNW_ACQ_RUN_LOG`;
- controlled database-error injection;
- two independent Eclipse / ADT sessions for the concurrency test.

---

## Test support classes

### `ZCL_NW_TEST_RUN`

Used to prepare or modify persisted test data for controlled scenarios.

Typical examples:

- setting specific source states;
- preparing artificial target differences;
- restoring test preconditions;
- creating controlled database conditions.

The class is kept separate from the acquisition algorithm.

### `ZCL_NW_TEST_DRIVER`

Used to call individual public methods directly without executing the complete
normal orchestration flow.

Typical calls include:

```abap
lo_acquisition->full_load_compare( ).
```

for a normal run,

```abap
lo_acquisition->full_load_compare(
  iv_original_run_id = lv_original_run_id
  iv_retry_count     = 1
).
```

for a retry run, and:

```abap
DATA(lt_candidates) =
  lo_acquisition->reconcile_runs( ).
```

for isolated reconciliation testing.

This separation was important for testing state-machine transitions that the
normal runner would otherwise process automatically.

---

## Test conventions

The following terms are used throughout this document.

### Normal run

A call to `FULL_LOAD_COMPARE` with:

```text
RETRY_COUNT = 0
```

### Retry run

A call to `FULL_LOAD_COMPARE` with:

```text
RETRY_COUNT > 0
```

### RUN A, RUN B, ...

Symbolic names used to describe successive acquisition runs.

Actual runs use UUID-based `RUN_ID` values.

### Source state

The current operational row in:

```text
ZNW_ACQ_STATE
```

### Run history

Historical execution records in:

```text
ZNW_ACQ_RUN_LOG
```

A source-state status and a historical run-log status are related, but they
represent different concepts and are therefore verified separately.

---

## Test matrix

| Area | Scenario | Verified result |
|---|---|---|
| Happy path | Normal acquisition from `DONE` | Allowed, source returns to `DONE` |
| HTTP | HTTP 404 | Controlled `ZCX_NW_HTTP_ERROR`, run becomes `FAILED` |
| HTTP | Connection failure | Controlled HTTP exception with status code `0` |
| Database | Business DB failure | Business LUW rolled back |
| Logging | Final log failure | Successful business commit preserved |
| Recovery | Interrupted `RUNNING` | Reconciled to `STALE` |
| Recovery | Non-authoritative historical `RUNNING` | Reconciled to `UNKNOWN` |
| Retry | `STALE` with retries available | Retry candidate created |
| Retry | Retry limit reached | `RETRY_LIMIT`, no new run |
| Admission | Second normal run while `RUNNING` | Rejected |
| Admission | Normal run from `STALE` | Rejected |
| Admission | Normal run from `RETRY_LIMIT` | Rejected |
| Admission | Retry from invalid states | Rejected |
| Transaction | Initial `RUN_LOG` creation failure | Complete start LUW rolled back |
| Concurrency | Two simultaneous first runs | Only one session acquires source |



---

## Detailed test scenarios

### Negative test #1 — second normal run while source is `RUNNING`

#### Purpose

Verify that a second normal acquisition cannot start while another run already
owns the same source.

#### Preconditions

```text
ZNW_ACQ_STATE
  STATUS        = RUNNING
  ACTIVE_RUN_ID = <RUN A>

ZNW_ACQ_RUN_LOG
  RUN A -> RUNNING
```

The stale timeout was temporarily increased during this test so that the first
run would not be reclassified as `STALE` before the second attempt.

#### Procedure

1. Start RUN A.
2. Pause RUN A after the start transaction has committed and before the OData
   request is executed.
3. Start a second normal `FULL_LOAD_COMPARE`.
4. Observe the admission result.

The second run attempts a conditional update that only accepts `DONE` or
`FAILED`.

Because the current source state is `RUNNING`, the acquisition is rejected.

#### Verified result

```text
STATE.STATUS        = RUNNING
STATE.ACTIVE_RUN_ID = <RUN A>

RUN_LOG
  RUN A -> RUNNING
  RUN B -> no record
```

The second execution raises `ZCX_NW_RUN_ACTIVE`.

It does not reach `GET_PRODUCTS`.

---

### Negative test #2 — normal run from `STALE`

#### Purpose

Verify that a stale acquisition may only continue through the retry path and
cannot be replaced by a new normal run.

#### Preconditions

The active run is first reconciled into:

```text
ZNW_ACQ_STATE
  STATUS        = STALE
  ACTIVE_RUN_ID = <RUN B>

ZNW_ACQ_RUN_LOG
  RUN B -> STALE
```

`ACTIVE_RUN_ID` intentionally continues to reference the stale run.

#### Procedure

1. Execute `RECONCILE_RUNS` directly through `ZCL_NW_TEST_DRIVER`.
2. Confirm that one retry candidate is returned.
3. Do not execute the retry.
4. Invoke a normal `FULL_LOAD_COMPARE` directly.

#### Verified result

```text
STATE.STATUS        = STALE
STATE.ACTIVE_RUN_ID = <RUN B>

RUN_LOG
  RUN B -> STALE
  no new run created
```

The normal run is rejected before the external source is called.

This verifies that `STALE` is reserved for retry admission.

---

### Negative test #3 — normal run from `RETRY_LIMIT`

#### Purpose

Verify that a new normal acquisition cannot bypass the automatic retry limit.

#### Preconditions

A retry chain is driven to the configured maximum retry count.

After reconciliation of the final stale retry:

```text
ZNW_ACQ_STATE
  STATUS        = RETRY_LIMIT
  ACTIVE_RUN_ID = initial
```

The historical retry-chain records remain in `ZNW_ACQ_RUN_LOG`.

#### Procedure

Invoke a normal:

```abap
lo_acquisition->full_load_compare( ).
```

without retry parameters.

#### Verified result

The run is rejected with:

```text
Run not allowed for NORTHWIND_PRODUCTS.
Current state: RETRY_LIMIT.
Requested mode: NORMAL.
```

The following conditions were verified:

```text
STATE remains RETRY_LIMIT
ACTIVE_RUN_ID remains initial
no new RUN_LOG record is created
GET_PRODUCTS is not executed
```

This test also exposed an earlier diagnostic defect: the rejected run initially
reported a newly generated but non-persisted `RUN_ID` as the active run.

The admission failure path was corrected to re-read the persisted source state
before constructing the exception.

After the fix, no false active-run ID is reported.

---

### Negative test #4 — retry from invalid states

#### Purpose

Verify that retry execution is admitted only from `STALE`.

The retry admission path uses a conditional update requiring:

```text
STATE.STATUS = STALE
```

#### Tested states

Retry execution was tested from:

```text
RETRY_LIMIT
DONE
FAILED
RUNNING
```

All four states must reject the retry.

#### Procedure

For each state:

1. prepare the corresponding `ZNW_ACQ_STATE`;
2. invoke `FULL_LOAD_COMPARE` with `RETRY_COUNT > 0`;
3. verify that the acquisition does not proceed.

Example retry invocation:

```abap
lo_acquisition->full_load_compare(
  iv_original_run_id = lv_original_run_id
  iv_retry_count     = 1
).
```

#### Verified result

For each invalid state:

```text
STATE remains unchanged
no new RUN_LOG record is created
GET_PRODUCTS is not executed
```

The diagnostic path reports `ZCX_NW_RUN_NOT_ALLOWED`.

For example, retry from `DONE` produces:

```text
Run not allowed for NORTHWIND_PRODUCTS.
Current state: DONE.
Requested mode: RETRY.
```

The complete admission behavior verified by tests is therefore:

| Current source state | Normal run | Retry run |
|---|---:|---:|
| No state row | Allowed | Rejected |
| `DONE` | Allowed | Rejected |
| `FAILED` | Allowed | Rejected |
| `STALE` | Rejected | Allowed |
| `RUNNING` | Rejected | Rejected |
| `RETRY_LIMIT` | Rejected | Rejected |


---

### Negative test #5 — atomic start-transaction rollback

#### Purpose

Verify that source acquisition and creation of the initial `RUN_LOG` record
form one atomic transaction.

The system must never persist:

```text
STATE.STATUS        = RUNNING
STATE.ACTIVE_RUN_ID = <new RUN_ID>
```

without a corresponding initial `RUN_LOG` record.

#### Preconditions

The source is in a state from which a normal run is allowed, for example:

```text
ZNW_ACQ_STATE
  STATUS        = DONE
  ACTIVE_RUN_ID = initial
```

At least one historical `RUN_ID` already exists in `ZNW_ACQ_RUN_LOG`.

#### Procedure

1. Start a normal `FULL_LOAD_COMPARE`.
2. Allow the admission logic to acquire the source.
3. Stop in the debugger immediately before:

```abap
INSERT znw_acq_run_log FROM @ls_run_log.
```

4. Replace `ls_run_log-run_id` in the debugger with an already existing
   `RUN_ID`.
5. Execute the `INSERT`.

This deliberately creates a duplicate-key condition for the initial run-log
record.

#### Initial result — defect detected

Before the transaction-handling fix, the duplicate insert returned:

```text
SY-SUBRC = 4
```

but the code was still about to execute:

```abap
COMMIT WORK AND WAIT.
```

The source had already been changed to `RUNNING` in the same LUW.

The resulting risk was therefore:

```text
STATE -> RUNNING
RUN_LOG insert -> failed
COMMIT
```

which could persist an active source without a corresponding run-log record.

#### Fix

The initial `RUN_LOG` creation was placed inside a protected database
transaction.

Failure of the insert now causes:

```text
ROLLBACK WORK
```

followed by a controlled:

```text
ZCX_NW_DB_ERROR
```

A non-zero `SY-SUBRC` from the initial insert is handled explicitly in
addition to `CX_SY_OPEN_SQL_DB`.

#### Repeated test — verified result

The same duplicate-key scenario was executed again.

Observed diagnostic output:

```text
Database Error: Initial RUN_LOG record could not be created
```

The database state after the failed run was:

```text
ZNW_ACQ_STATE
  STATUS        = DONE
  ACTIVE_RUN_ID = initial

ZNW_ACQ_RUN_LOG
  no new record
```

The previous source state was restored by rollback.

This verifies that the start transaction is atomic:

```text
Acquire STATE
+
Create initial RUN_LOG
+
COMMIT

or

ROLLBACK everything
```

---

### Negative test #6 — concurrent first-run acquisition

#### Purpose

Verify the one-active-run invariant under a real race condition when no
`ZNW_ACQ_STATE` row exists yet.

This scenario is important because a first run cannot rely on updating an
already existing state row. Two sessions may attempt to create the same source
state concurrently.

#### Test environment

Two independent Eclipse / ADT sessions were connected to the same ABAP Cloud
backend.

```text
Session A
  Eclipse instance A
  workspace A
  ABAP Cloud Project -> same backend

Session B
  Eclipse instance B
  workspace B
  ABAP Cloud Project -> same backend
```

The separate Eclipse workspaces provided two independent execution sessions
and database transactions.

#### Preconditions

The state row for the source was removed:

```text
ZNW_ACQ_STATE
  NORTHWIND_PRODUCTS -> no row
```

Historical `RUN_LOG` records were left unchanged.

Both sessions used a normal:

```abap
lo_acquisition->full_load_compare( ).
```

#### Procedure

##### Session A

Session A was started in the debugger.

Execution was paused after successful:

```abap
INSERT znw_acq_state FROM @ls_state.
```

but before creation of the initial `RUN_LOG` and before `COMMIT`.

At this point:

```text
lv_acquired = abap_true
```

and Session A held an uncommitted database lock for the newly inserted source
state.

##### Session B

While Session A remained paused, the same normal acquisition was started from
Session B.

Session B did not complete. It waited for the database lock held by Session A.

This confirmed that the two executions were competing for the same source
state in separate database transactions.

##### Session A resumes

Session A was then allowed to execute:

```text
create initial RUN_LOG
COMMIT
```

After the commit, Session A was stopped again before the external OData call.

The persisted state was now:

```text
ZNW_ACQ_STATE
  STATUS        = RUNNING
  ACTIVE_RUN_ID = <RUN A>
```

and:

```text
ZNW_ACQ_RUN_LOG
  RUN A -> RUNNING
```

##### Session B resumes

The commit released the database lock.

Session B resumed automatically, observed that the source was already owned by
RUN A, and was rejected by the admission logic.

Diagnostic output:

```text
Acquisition is already running for NORTHWIND_PRODUCTS.
Active run ID: <RUN A>
```

The reported `ACTIVE_RUN_ID` matched the value persisted in
`ZNW_ACQ_STATE`.

#### Verified result

After both sessions completed their admission processing:

```text
ZNW_ACQ_STATE
  one row
  STATUS        = RUNNING
  ACTIVE_RUN_ID = <RUN A>

ZNW_ACQ_RUN_LOG
  RUN A -> RUNNING
  RUN B -> no record
```

Session B did not reach:

```text
GET_PRODUCTS
```

No second run acquired the source.

#### What this test verifies

The test confirms that the one-active-run rule is protected by actual database
serialization rather than only by application-level checks.

The combination of:

```text
conditional admission
unique source-state row
database locking
transactional initial RUN_LOG creation
```

prevents two concurrent first runs from acquiring the same `SOURCE_NAME`.

The test used two real concurrent LUWs rather than manually simulating the
final table state.
