# LLM vision prompt (fixed, so repeats are comparable)

Send front, side and back photos plus this text. Run 3 times per session, new chat each time.

> You are estimating body composition for a fitness app. The photos show one adult
> {sex}, {age} years, {height_cm} cm, {weight_kg} kg, standing in the capture pose.
> Estimate whole-body fat percentage as a DEXA scan would report it (not BIA or calipers).
> Reply with JSON only: {"bf_pct": number, "low": number, "high": number,
> "lean_mass_kg": number, "notes": "one sentence"}.
