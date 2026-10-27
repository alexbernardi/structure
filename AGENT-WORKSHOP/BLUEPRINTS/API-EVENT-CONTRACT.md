# Contract: <message, event or API name>

Owner: <system>     Version: <protocol vX / system x.y>     Status: draft | stable

| Field | Type | Range / validation | Meaning |
|---|---|---|---|
| | | | |

- Direction / caller: client -> server | server -> clients | module -> module
- Transport: RPC name, channel, reliability (see `net/session.gd`) or function signature
- Authority: who may send it; what the receiver must validate; what happens on invalid input (reject reason / violation)
- Ordering and frequency: e.g. reliable ordered, <= 20 Hz
- Persistence impact: none | changes saved data (schema version!)
- Compatibility: bump protocol/schema version? migration?
- Tests: which tests prove the contract
