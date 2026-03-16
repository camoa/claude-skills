# Style Recommendation Engine

Intelligent style selection based on brand personality, presentation purpose, and audience. Replaces manual browsing of 18 styles with a scored recommendation.

---

## Section 1: Brand Personality Extraction

Extract brand personality from `brand-philosophy.md` voice traits, then map to Aaker's Brand Personality Dimensions.

### Voice Trait → Aaker Dimension Mapping

| Voice Adjectives | Aaker Dimension |
|-----------------|-----------------|
| precise, reliable, expert, professional, competent, efficient, systematic | **Competence** |
| warm, friendly, approachable, honest, genuine, down-to-earth, caring | **Sincerity** |
| bold, innovative, daring, creative, energetic, spirited, imaginative | **Excitement** |
| elegant, refined, luxurious, prestigious, polished, premium, exclusive | **Sophistication** |
| rugged, authentic, tough, outdoorsy, adventurous, raw, handcrafted | **Ruggedness** |

**Process**: Read `brand-philosophy.md` → extract voice descriptors → classify each into 1-2 Aaker dimensions → identify dominant dimension(s).

If brand-philosophy.md uses trait words not in this table, map by proximity to the closest dimension.

---

## Section 2: Aaker → Style Affinity Matrix

Each Aaker dimension has natural affinities with certain styles and conflicts with others.

| Aaker Dimension | High-Affinity Styles (score +3) | Medium-Affinity (score +1) | Avoid Styles (score -2) |
|----------------|-------------------------------|---------------------------|------------------------|
| **Sincerity** | Organic, Hygge, Lagom, Narrative-Clean | Wabi-Sabi, Feng Shui, Corporate-Confident | Dramatic, Pitch-Velocity, Memphis |
| **Excitement** | Dramatic, Memphis, Pitch-Velocity, Tech-Modern | Iki, Data-Forward, Organic | Shibui, Ma, Yeo-baek, Corporate-Confident |
| **Competence** | Swiss, Tech-Modern, Data-Forward, Corporate-Confident | Minimal, Lagom, Narrative-Clean | Wabi-Sabi, Memphis, Ma |
| **Sophistication** | Shibui, Iki, Minimal, Corporate-Confident | Narrative-Clean, Swiss, Yeo-baek | Memphis, Hygge, Pitch-Velocity |
| **Ruggedness** | Wabi-Sabi, Organic, Dramatic | Hygge, Pitch-Velocity, Narrative-Clean | Shibui, Ma, Yeo-baek, Minimal |

---

## Section 3: Purpose → Style Mapping

Map the stated purpose of the presentation to recommended styles.

| Purpose | Top Styles (score +4) | Good Fit (score +2) | Poor Fit (score -1) |
|---------|----------------------|---------------------|---------------------|
| **Sales pitch** | Pitch-Velocity, Dramatic, Tech-Modern | Iki, Memphis | Ma, Yeo-baek, Shibui |
| **Quarterly update** | Data-Forward, Corporate-Confident, Swiss | Minimal, Lagom | Memphis, Dramatic, Pitch-Velocity |
| **Investor deck** | Pitch-Velocity, Data-Forward, Corporate-Confident | Tech-Modern, Swiss | Wabi-Sabi, Ma, Hygge |
| **Product demo** | Tech-Modern, Dramatic, Narrative-Clean | Swiss, Pitch-Velocity | Yeo-baek, Ma, Shibui |
| **Thought leadership** | Narrative-Clean, Iki, Minimal | Shibui, Organic, Swiss | Memphis, Pitch-Velocity, Data-Forward |
| **Team training** | Organic, Lagom, Hygge | Swiss, Narrative-Clean, Tech-Modern | Ma, Shibui, Yeo-baek |
| **Company update** | Corporate-Confident, Lagom, Minimal | Swiss, Narrative-Clean | Memphis, Dramatic, Pitch-Velocity |
| **Brand story** | Narrative-Clean, Organic, Iki | Dramatic, Wabi-Sabi, Hygge | Swiss, Data-Forward, Corporate-Confident |
| **Tech overview** | Tech-Modern, Swiss, Data-Forward | Minimal, Corporate-Confident | Wabi-Sabi, Memphis, Hygge |
| **Creative pitch** | Memphis, Dramatic, Iki | Pitch-Velocity, Tech-Modern | Corporate-Confident, Lagom, Shibui |
| **Wellness/health** | Hygge, Organic, Feng Shui | Lagom, Narrative-Clean | Memphis, Pitch-Velocity, Swiss |
| **Luxury showcase** | Shibui, Minimal, Iki | Ma, Yeo-baek, Narrative-Clean | Memphis, Hygge, Data-Forward |

---

## Section 4: Audience → Style Adjustments

Adjust scores based on who will receive the presentation.

| Audience | Style Boost (score +2) | Style Penalty (score -2) | Notes |
|----------|----------------------|-------------------------|-------|
| **C-suite / Board** | Minimal, Corporate-Confident, Shibui, Swiss | Memphis, Pitch-Velocity | Reduce colors, increase whitespace, premium feel |
| **Technical** | Swiss, Tech-Modern, Data-Forward | Organic, Hygge, Wabi-Sabi | Data density OK, precision valued |
| **General / All-hands** | Hygge, Lagom, Narrative-Clean, Organic | Ma, Yeo-baek, Shibui | Warmth + clarity, approachable |
| **Creative** | Dramatic, Iki, Memphis, Pitch-Velocity | Corporate-Confident, Lagom | Risk-taking appreciated |
| **Investors** | Data-Forward, Pitch-Velocity, Corporate-Confident | Wabi-Sabi, Ma, Hygge | Numbers + momentum |
| **Customers / External** | Narrative-Clean, Tech-Modern, Organic | Ma, Yeo-baek, Memphis | Story + clarity |

---

## Section 5: Scoring Algorithm

For each of the 18 styles, calculate a total score:

```
Total Score = Brand Match + Purpose Match + Audience Adjustment
```

### Scoring Steps

1. **Brand Match**: For each Aaker dimension identified in the brand:
   - Style in "High-Affinity": +3
   - Style in "Medium-Affinity": +1
   - Style in "Avoid": -2
   - If brand has multiple dimensions, sum across all

2. **Purpose Match**: Look up the stated purpose:
   - Style in "Top Styles": +4
   - Style in "Good Fit": +2
   - Style in "Poor Fit": -1

3. **Audience Adjustment**: Look up the target audience:
   - Style in "Style Boost": +2
   - Style in "Style Penalty": -2

4. **Sort styles by total score**, descending

5. **Return top 3** with reasoning sentence each

### Output Format

Present recommendations as:

```markdown
## Style Recommendations

Based on your brand personality (Competence + Excitement), product demo purpose, and technical audience:

1. **Tech-Modern** (score: 9) — Your brand's competence traits + product demo purpose for a technical audience make this the strongest match. Clean grid, systematic, data-aware.

2. **Swiss** (score: 7) — Mathematical precision aligns with your competence dimension. Grid-based clarity works well for technical audiences.

3. **Dramatic** (score: 6) — Your excitement traits support bold asymmetric design. High-impact for product reveals, but temper for technical precision.

---

**Browse all 18 styles?** Select "Browse all" to see the full catalog with descriptions.
```

---

## Section 6: Override Protocol

The recommendation engine **recommends, never decides**. Users always have the final choice.

### User Override Rules

1. **User can always override** — If user picks a style not in top 3, respect their choice
2. **Contrast note for low-score picks** — If user selects a style with negative score, show a brief note:
   > "Note: Memphis scores low for your Competence brand + quarterly update purpose. This can work if you want deliberate contrast — playful energy for what's typically serious. Proceed?"
3. **Browse all** — User can always request the full 18-style catalog
4. **Skip recommendation** — If user already knows their style, skip directly to selection

### When to Skip Recommendation

- User says "I want [specific style]" → go directly to that style
- User is editing an existing template → keep current style unless they ask to change
- Quick commands (`/presentation-quick`) → use template's existing style

---

*Style recommendation engine for brand-content-design plugin*
*Covers 18 styles across 5 aesthetic families*
