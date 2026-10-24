---- MODULE BackpressureOld ----
\* Protocol of CSVDecoder.decodeWithBackpressure as shipped (CSVDecoder+Backpressure.swift:234-295):
\* a producer Task batches rows, asks the controller (recordProduced) whether to park, parks in
\* waitForSpace, then yields to an AsyncThrowingStream with .bufferingNewest(CAP).
\* Nothing in the shipped code calls recordConsumed; only stream termination calls cancelAllWaiters.
EXTENDS Naturals
CONSTANTS N, B, CAP, HIGH   \* rows, batch size, stream capacity, high-water rows
VARIABLES produced, batch, buf, dropped, consumed, buffered, paused, parked, finished, done
vars == <<produced, batch, buf, dropped, consumed, buffered, paused, parked, finished, done>>

Init == /\ produced = 0 /\ batch = 0 /\ buf = 0 /\ dropped = 0 /\ consumed = 0
        /\ buffered = 0 /\ paused = FALSE /\ parked = FALSE /\ finished = FALSE /\ done = FALSE

Yield(n) == LET room == CAP - buf IN
              /\ buf' = IF n <= room THEN buf + n ELSE CAP
              /\ dropped' = dropped + (IF n <= room THEN 0 ELSE n - room)

Decode == /\ ~parked /\ ~finished /\ produced < N /\ batch < B
          /\ produced' = produced + 1 /\ batch' = batch + 1
          /\ UNCHANGED <<buf, dropped, consumed, buffered, paused, parked, finished, done>>

\* recordProduced(batch) then either waitForSpace (paused) or yield the batch.
Flush == /\ ~parked /\ batch = B
         /\ buffered' = buffered + B
         /\ IF buffered + B >= HIGH
              THEN /\ paused' = TRUE /\ parked' = TRUE /\ UNCHANGED <<buf, dropped, batch>>
              ELSE /\ Yield(B) /\ batch' = 0 /\ UNCHANGED <<paused, parked>>
         /\ UNCHANGED <<produced, consumed, finished, done>>

\* waitForSpace returns only when paused is cleared (recordConsumed or cancelAllWaiters).
Wake == /\ parked /\ ~paused
        /\ parked' = FALSE /\ Yield(batch) /\ batch' = 0
        /\ UNCHANGED <<produced, consumed, buffered, paused, finished, done>>

Finish == /\ ~parked /\ ~finished /\ produced = N /\ batch = 0
          /\ finished' = TRUE
          /\ UNCHANGED <<produced, batch, buf, dropped, consumed, buffered, paused, parked, done>>

Take == /\ buf > 0 /\ buf' = buf - 1 /\ consumed' = consumed + 1
        /\ UNCHANGED <<produced, batch, dropped, buffered, paused, parked, finished, done>>

\* The consumer sees the stream end, which triggers onTermination -> cancelAllWaiters.
End == /\ finished /\ buf = 0 /\ ~done
       /\ done' = TRUE /\ paused' = FALSE /\ buffered' = 0
       /\ UNCHANGED <<produced, batch, buf, dropped, consumed, parked, finished>>

Stutter == done /\ UNCHANGED vars

Next == Decode \/ Flush \/ Wake \/ Finish \/ Take \/ End \/ Stutter
Spec == Init /\ [][Next]_vars /\ WF_vars(Decode) /\ WF_vars(Flush) /\ WF_vars(Wake)
        /\ WF_vars(Finish) /\ WF_vars(Take) /\ WF_vars(End)

NoLoss == done => (dropped = 0 /\ consumed = N)
Terminates == <>done
====
