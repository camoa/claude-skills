"""Checks for Claude Code plugins.

The rule every module here obeys: a check must not encode a fact Anthropic can
change. Hook event names, model tiers, reserved marketplace names, manifest key
allowlists, character caps and enum members all have an owner who can move them,
and a check that writes one down is wrong the day they do. What is left is
structure (does a path resolve, does a file parse) and self-consistency (does a
file contradict itself). Neither goes stale.
"""
