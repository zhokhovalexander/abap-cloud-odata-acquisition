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
