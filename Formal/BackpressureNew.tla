---- MODULE BackpressureNew ----
\* Proposed protocol: AsyncThrowingStream(unfolding:). The consumer's next() runs the producer
\* inline, one row at a time, so there is no producer task, no queue, no controller and no wait.
\* The consumer may cancel between any two pulls; a cancelled stream decodes nothing more.
EXTENDS Naturals
CONSTANTS N
VARIABLES produced, consumed, cancelled, done
vars == <<produced, consumed, cancelled, done>>

Init == produced = 0 /\ consumed = 0 /\ cancelled = FALSE /\ done = FALSE

\* next(): decode one row and hand it to the consumer in the same step.
Pull == /\ ~done /\ ~cancelled /\ produced < N
        /\ produced' = produced + 1 /\ consumed' = consumed + 1
        /\ UNCHANGED <<cancelled, done>>
EndOfInput == /\ ~done /\ ~cancelled /\ produced = N /\ done' = TRUE /\ UNCHANGED <<produced, consumed, cancelled>>
Cancel == /\ ~done /\ ~cancelled /\ cancelled' = TRUE /\ done' = TRUE /\ UNCHANGED <<produced, consumed>>
Stutter == done /\ UNCHANGED vars

Next == Pull \/ EndOfInput \/ Cancel \/ Stutter
Spec == Init /\ [][Next]_vars /\ WF_vars(Pull) /\ WF_vars(EndOfInput)

NoLoss == (done /\ ~cancelled) => consumed = N
NothingExtra == produced = consumed          \* unbounded read-ahead is impossible: held rows = 0
NoWorkAfterCancel == cancelled => produced <= N
Terminates == <>done
====
