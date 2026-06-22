import json
import os
import re
import threading
from collections import Counter, defaultdict
from urllib.parse import urlparse, unquote

from PySide6.QtCore import QObject, Signal, Slot

import time

try:
    from openai import OpenAI
    import httpx
    _HAS_OPENAI = True
except ImportError:
    _HAS_OPENAI = False


_MINDMAP_PROMPT = (
    "Analyze the following text and extract its key concepts and their relationships. "
    "Return a JSON tree structure. Each node must have: "
    "\"id\" (string), \"label\" (string, short concept name), "
    "\"children\" (array of child nodes). "
    "Return ONLY valid JSON, no markdown, no explanation. "
    "The root node should represent the main topic. "
    "Aim for 3-5 main branches with 2-4 levels of depth.\n\n"
    "Text:\n{text}"
)

_GROQ_API_KEY = os.environ.get("GROQ_API_KEY", "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")

_FREE_PROVIDERS = [
    {
        "name": "Groq",
        "base_url": "https://api.groq.com/openai/v1",
        "model": "llama-3.3-70b-versatile",
        "api_key": _GROQ_API_KEY,
    },
    {
        "name": "Cerebras",
        "base_url": "https://api.cerebras.ai/v1",
        "model": "llama-3.3-70b",
        "env_key": "CEREBRAS_API_KEY",
    },
    {
        "name": "OpenRouter",
        "base_url": "https://openrouter.ai/api/v1",
        "model": "meta-llama/llama-3.3-70b-instruct:free",
        "env_key": "OPENROUTER_API_KEY",
    },
    {
        "name": "Mistral",
        "base_url": "https://api.mistral.ai/v1",
        "model": "mistral-small-latest",
        "env_key": "MISTRAL_API_KEY",
    },
]


def _tokenize(text):
    return re.findall(r"[a-zA-Z\u0600-\u06FF]{3,}", text.lower())


def _sentences(text):
    raw = re.split(r'[.!?;:\n]+', text)
    return [s.strip() for s in raw if len(s.strip()) > 10]


def _tfidf_keywords(text, top_n=30):
    _STOP_WORDS = {
        "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did", "will", "would", "could",
        "should", "may", "might", "shall", "can", "to", "of", "in", "for",
        "on", "with", "at", "by", "from", "as", "into", "through", "during",
        "before", "after", "and", "but", "or", "if", "because", "that",
        "this", "these", "those", "it", "its", "they", "them", "their",
        "what", "which", "who", "he", "she", "him", "her", "his", "my",
        "your", "our", "we", "you", "me", "us", "about", "up", "not",
        "no", "nor", "only", "own", "same", "so", "than", "too", "very",
        "just", "now", "also", "all", "both", "each", "few", "more",
        "most", "other", "some", "such", "here", "there", "when", "where",
        "why", "how",
    }
    sentences = _sentences(text)
    if not sentences:
        return []

    doc_freq = Counter()
    word_freq = Counter()

    for sent in sentences:
        words = [w for w in _tokenize(sent) if w not in _STOP_WORDS]
        for w in set(words):
            doc_freq[w] += 1
        word_freq.update(words)

    total_docs = len(sentences)
    scores = {}
    for word, freq in word_freq.items():
        tf = freq / max(len(word_freq), 1)
        idf = 1.0 + (total_docs / max(doc_freq[word], 1))
        scores[word] = tf * idf

    ranked = sorted(scores.items(), key=lambda x: x[1], reverse=True)
    return [w for w, s in ranked[:top_n]]


def _build_tree(text, keywords):
    if not keywords:
        return {"id": "root", "label": "Document", "children": []}

    sentences = _sentences(text)
    keyword_set = set(keywords)

    sentence_keywords = []
    for sent in sentences:
        words = [w for w in _tokenize(sent) if w in keyword_set]
        sentence_keywords.append(words)

    groups = defaultdict(list)
    used = set()

    for i, kw in enumerate(keywords):
        if kw in used:
            continue
        groups[kw].append(kw)
        used.add(kw)

        for j in range(i + 1, len(keywords)):
            kw2 = keywords[j]
            if kw2 in used:
                continue
            co_occur = sum(1 for sw in sentence_keywords if kw in sw and kw2 in sw)
            if co_occur >= 1:
                groups[kw].append(kw2)
                used.add(kw2)
                if len(groups[kw]) >= 5:
                    break

    main_topics = keywords[:min(5, len(keywords))]
    children = []

    for topic in main_topics:
        branch_keywords = groups.get(topic, [topic])
        topic_children = []
        for kw in branch_keywords:
            if kw != topic:
                topic_children.append({
                    "id": f"leaf_{kw}",
                    "label": kw.title(),
                    "children": []
                })

        children.append({
            "id": f"branch_{topic}",
            "label": topic.title(),
            "children": topic_children
        })

    root_label = keywords[0].title() if keywords else "Document"

    return {
        "id": "root",
        "label": root_label,
        "children": children
    }


def _parse_ai_json(text):
    raw = text.strip()
    if raw.startswith("```"):
        lines = raw.split("\n")
        lines = [l for l in lines if not l.strip().startswith("```")]
        raw = "\n".join(lines)
    return json.loads(raw)


class MindMapBackend(QObject):
    mindMapReady = Signal(str)
    errorOccurred = Signal(str)
    statusChanged = Signal(str)

    def __init__(self, key_rotation=None, parent=None):
        super().__init__(parent)
        self._key_rotation = key_rotation
        self._api_key = self._resolve_key()
        self._gemini_client = None
        self._selected_provider = "auto"
        self._generation_done = False
        if self._api_key:
            self._init_gemini()

    @Slot(str)
    def setProvider(self, provider):
        self._selected_provider = provider.lower()

    def _resolve_key(self) -> str:
        if self._key_rotation and self._key_rotation.has_keys:
            return self._key_rotation.current
        return ""

    def _init_gemini(self):
        try:
            from google import genai
            from google.genai import types
            self._gemini_client = genai.Client(
                api_key=self._api_key,
                http_options=types.HttpOptions(timeout=30)
            )
        except Exception:
            self._gemini_client = None

    def _resolve_path(self, file_path):
        if file_path.startswith("file:///"):
            parsed = urlparse(file_path)
            path = unquote(parsed.path)
            if os.name == "nt" and path.startswith("/"):
                path = path[1:]
            return path
        return file_path

    @Slot(str)
    def generateFromText(self, text):
        if not text or not text.strip():
            self.errorOccurred.emit("No text provided")
            return

        self._generation_done = False
        self.statusChanged.emit("generating")
        thread = threading.Thread(target=self._generate_thread, args=(text,), daemon=True)
        thread.start()

        timer = threading.Timer(60.0, self._force_timeout)
        timer.daemon = True
        timer.start()

    def _force_timeout(self):
        if self._generation_done:
            return
        self.errorOccurred.emit("Generation timed out — try again or use local mode")
        self.statusChanged.emit("idle")

    @Slot(str)
    def generateFromPdf(self, file_path):
        file_path = self._resolve_path(file_path)
        try:
            import PyPDF2
            if not os.path.isfile(file_path):
                self.errorOccurred.emit(f"File not found: {os.path.basename(file_path)}")
                return
            with open(file_path, 'rb') as f:
                reader = PyPDF2.PdfReader(f)
                text = ""
                for page in reader.pages:
                    text += page.extract_text() or ""
            if not text.strip():
                self.errorOccurred.emit("Could not extract text from PDF")
                return
            self.generateFromText(text)
        except ImportError:
            self.errorOccurred.emit("PyPDF2 not installed. Run: pip install PyPDF2")
        except Exception as e:
            self.errorOccurred.emit(f"Failed to read PDF: {str(e)}")

    @Slot(str)
    def generateFromFile(self, file_path):
        file_path = self._resolve_path(file_path)
        try:
            if not os.path.isfile(file_path):
                self.errorOccurred.emit(f"File not found: {os.path.basename(file_path)}")
                return
            with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
                text = f.read()
            if not text.strip():
                self.errorOccurred.emit("File is empty")
                return
            self.generateFromText(text)
        except Exception as e:
            self.errorOccurred.emit(f"Failed to read file: {str(e)}")

    def _generate_thread(self, text):
        try:
            prompt = _MINDMAP_PROMPT.format(text=text[:8000])

            if self._selected_provider == "gemini":
                result = self._try_gemini(prompt)
                if result:
                    self.mindMapReady.emit(json.dumps(result))
                    return

            elif self._selected_provider == "groq":
                result = self._try_openai_provider(_FREE_PROVIDERS[0], prompt)
                if result:
                    self.mindMapReady.emit(json.dumps(result))
                    return

            else:
                for provider in _FREE_PROVIDERS:
                    self.statusChanged.emit(f"Trying {provider['name']}...")
                    result = self._try_openai_provider(provider, prompt)
                    if result:
                        self.mindMapReady.emit(json.dumps(result))
                        return

                self.statusChanged.emit("Trying Gemini...")
                result = self._try_gemini(prompt)
                if result:
                    self.mindMapReady.emit(json.dumps(result))
                    return

            self.statusChanged.emit("Generating locally...")
            result = self._local_extract(text)
            self.mindMapReady.emit(json.dumps(result))

        except Exception as e:
            self.errorOccurred.emit(f"Error: {str(e)}")
        finally:
            self._generation_done = True
            self.statusChanged.emit("idle")

    def _try_gemini(self, prompt):
        if not self._gemini_client:
            return None

        self.statusChanged.emit("Trying Gemini AI...")
        try:
            from google.api_core.exceptions import ResourceExhausted

            for attempt in range(3):
                try:
                    response = self._gemini_client.models.generate_content(
                        model="gemini-2.0-flash",
                        contents=prompt
                    )
                    if response and response.text:
                        return _parse_ai_json(response.text)
                    return None
                except ResourceExhausted:
                    if self._key_rotation and self._key_rotation.has_keys:
                        self._key_rotation.mark_failure()
                        self._key_rotation.rotate()
                        self._api_key = self._key_rotation.current
                        self._init_gemini()
                    time.sleep(1 * (2 ** attempt))
                except Exception:
                    break
        except Exception:
            pass
        return None

    def _try_openai_provider(self, provider, prompt):
        api_key = provider.get("api_key", "") or os.environ.get(provider.get("env_key", ""), "")
        if not api_key or not _HAS_OPENAI:
            return None

        try:
            client = OpenAI(
                api_key=api_key,
                base_url=provider["base_url"],
                timeout=httpx.Timeout(15.0, connect=5.0),
            )
            response = client.chat.completions.create(
                model=provider["model"],
                messages=[{"role": "user", "content": prompt}],
                temperature=0.3,
            )

            if response and response.choices:
                content = response.choices[0].message.content
                if content:
                    return _parse_ai_json(content)
        except Exception:
            pass
        return None

    def _local_extract(self, text):
        keywords = _tfidf_keywords(text, top_n=25)
        return _build_tree(text, keywords)
