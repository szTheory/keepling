# Keepling for iPhone

**Planned phase:** Phase 4  
**Technology:** native SwiftUI with generated transport contracts and native local persistence

The iPhone client independently implements durable local projection/outbox behavior against shared golden vectors. It shares semantic tokens and wire contracts—not React components, Ecto schemas, or desktop persistence models. Exact iOS floor and persistence adapter are phase decisions.

