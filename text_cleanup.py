#!/usr/bin/env python3
# text_cleanup.py
# Lightweight post-processor for Whisper transcriptions

import re

def cleanup_text(text: str) -> str:
    """
    Cleans up Whisper transcription text.
    - Removes newlines
    - Expands common colloquialisms ("gonna" → "going to")
    - Removes leading conjunctions/fillers like "And", "But", "So" at sentence starts
    - Normalizes spacing
    - Capitalizes sentence starts
    """
    if not text:
        return ""

    # 1. Flatten newlines into single spaces
    text = text.replace("\n", " ")

    # 2. Expand common colloquialisms
    replacements = {
        r"\bgonna\b": "going to",
        r"\bwanna\b": "want to",
        r"\bgotta\b": "got to",
        r"\bkinda\b": "kind of",
        r"\bsorta\b": "sort of",
        r"\blemme\b": "let me",
        r"\bgimme\b": "give me",
        r"\bcuz\b": "because",
    }
    for pat, repl in replacements.items():
        text = re.sub(pat, repl, text, flags=re.IGNORECASE)

    # 3. Trim redundant spaces and punctuation spacing
    text = re.sub(r"\s*([.,!?])\s*", r"\1 ", text)
    text = re.sub(r"\s+", " ", text).strip()

    # 4. Remove leading conjunctions/fillers at the start of sentences
    text = re.sub(
        r"(^|[.!?]\s+)(and|but|so)\b[\s,]*",
        r"\1",
        text,
        flags=re.IGNORECASE
    )

    # 5. Capitalize the first letter of each sentence
    def cap_sentences(s):
        return re.sub(
            r"(^|[.!?]\s+)([a-z])",
            lambda m: m.group(1) + m.group(2).upper(),
            s.strip()
        )

    text = cap_sentences(text)

    return text


# Optional: quick test if you run this module directly
if __name__ == "__main__":
    sample = ("So, I think we should start now. And then, check the logs. "
              "But maybe later. I'm gonna finish this today.")
    print(cleanup_text(sample))
