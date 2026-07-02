"""Comprehension evaluation harness (design §13).

De-risks R-001 (comprehension quality) with a versioned eval set, pure metric
functions, and a runner that compares aggregate quality against an acceptance
gate — all runnable offline with the deterministic ``FakeProvider``.
"""
