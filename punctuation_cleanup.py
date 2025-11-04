import sys
import re
from text_cleanup import cleanup_text

text = sys.stdin.read()

# Basic punctuation normalization (you can expand this)
text = re.sub(r'\s*([.,!?])\s*', r'\1 ', text)
text = re.sub(r'\s+', ' ', text)
text = text.strip()

# Remove all newlines
text = text.replace('\n', ' ')

# handle cleanup like gonna->going to and sentences starting with And

text = cleanup_text(text)

print(text)
