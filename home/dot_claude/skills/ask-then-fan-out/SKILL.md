---
name: ask-then-fan-out
description: Ask the owner clarifying questions about a list of requests, then start one separate session per request, each with a self-contained brief. Use for "ask me questions, then create a session for each request", "ask me questions to resolve any issues, then fork a session for each", "fan these out", "one session per request", "create new sessions for these tasks".
argument-hint: [the requests, or which of the listed ones to take]
---

# Ask, then fan out

The requests are the list in `$ARGUMENTS`, or the one already in this conversation (often the
output of `asked-of-me`). Number them and keep the numbers throughout.

1. Read enough to ask well: the sources each request cites and the repository or documents it
   touches. Do not start the work.
2. Ask the owner every question whose answer would change what a session does: which requests
   to take, drop or join, the intended outcome, who the output is for, what may be changed and
   what must only be drafted, and anything two requests disagree on. Ask them together, in one
   round where possible, with your recommended answer first. Skip what the sources already
   settle.
3. Wait for the answers. An unanswered question is not a yes. A request still unclear stays
   here, named in the report, rather than going out half-specified.
4. Start one separate session per request, with the session-starting tool this app offers. With
   none, write the briefs out for the owner to start by hand. A subagent is not a session.
5. Report one line per request: its number, the session started, or why it was held back.

## The brief

A session knows only what its brief says. Each one states: which request it is and the goal in
a sentence; the background needed, with links and paths rather than "as discussed"; the owner's
answers that bear on it; the steps; what done looks like; and the limits, namely what the other
sessions own and it must not touch, and what is drafted for the owner rather than sent or posted.

## Limits

- This session asks and delegates. It does none of the requests itself unless told to.
- A brief grants nothing the owner did not grant here: no sending, merging or deleting by default.
- No secret values and no private content beyond what the request needs go into a brief.
