import json
import re
from PySide6.QtCore import QObject, Slot

from core.database import DatabaseManager


def _safe_session_name(name: str) -> str:
    return re.sub(r"[^a-zA-Z0-9_\-]", "_", name)[:128]


class SourceAnalyzer(QObject):
    def __init__(self, db: DatabaseManager = None, parent=None):
        super().__init__(parent)
        self._db = db

    @Slot(str, str, result=bool)
    def saveSession(self, name: str, jsonData: str) -> bool:
        safe = _safe_session_name(name)
        if self._db:
            self._db.save_session(safe, jsonData)
            return True
        return False

    @Slot(str, result=str)
    def loadSession(self, name: str) -> str:
        safe = _safe_session_name(name)
        if self._db:
            return self._db.load_session(safe)
        return json.dumps({"error": "not found"})

    @Slot(result=str)
    def listSessions(self) -> str:
        if self._db:
            return json.dumps(self._db.list_sessions())
        return json.dumps([])

    @Slot(str, result=bool)
    def deleteSession(self, name: str) -> bool:
        safe = _safe_session_name(name)
        if self._db:
            self._db.delete_session(safe)
            return True
        return False

    @Slot(str, str, result=bool)
    def exportHtml(self, name: str, filepath: str) -> bool:
        raw = self.loadSession(name)
        try:
            d = json.loads(raw)
            if d.get("error"):
                return False
            html = f"""<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>{d.get('title', 'Source Analysis')}</title>
<style>body{{font-family:sans-serif;max-width:800px;margin:40px auto;padding:0 20px;color:#333;}}
h1{{color:#B48250;}}table{{width:100%;border-collapse:collapse;}}
td{{padding:8px;border-bottom:1px solid #ddd;font-size:14px;}}
td:first-child{{font-weight:bold;width:120px;color:#666;}}
.note{{background:#f9f5f0;padding:16px;border-radius:8px;margin-top:16px;}}</style>
</head><body>
<h1>{d.get('title', 'Untitled')}</h1>
<table>
<tr><td>Type</td><td>{d.get('type', '')}</td></tr>
<tr><td>Author</td><td>{d.get('author', '')}</td></tr>
<tr><td>Date</td><td>{d.get('date', '')}</td></tr>
<tr><td>Context</td><td>{d.get('context', '')}</td></tr>
<tr><td>Purpose</td><td>{d.get('purpose', '')}</td></tr>
<tr><td>Audience</td><td>{d.get('audience', '')}</td></tr>
<tr><td>Bias</td><td>{d.get('bias', '')}</td></tr>
<tr><td>Reliability</td><td>{d.get('reliability', '')}</td></tr>
</table>
<div class="note"><strong>Notes:</strong><br>{d.get('notes', '')}</div>
</body></html>"""
            with open(filepath, "w", encoding="utf-8") as f:
                f.write(html)
            return True
        except (OSError, json.JSONDecodeError):
            return False

    @Slot(str, result=str)
    def generateAiPrompt(self, jsonData):
        data = json.loads(jsonData)
        prompt = (
            f"Analyze the following {'primary' if data.get('type') == 'Primary' else 'secondary'} source "
            f"as a history student would.\n\n"
            f"Title: {data.get('title', 'Untitled')}\n"
            f"Author: {data.get('author', 'Unknown')}\n"
            f"Date: {data.get('date', 'Unknown')}\n"
            f"Context: {data.get('context', 'N/A')}\n\n"
            f"Please analyze:\n"
            f"1. Purpose: What was the author's goal?\n"
            f"2. Audience: Who was it written for?\n"
            f"3. Bias: What perspectives or limitations exist?\n"
            f"4. Reliability: How trustworthy is this source?\n"
            f"5. Key historical insights from this source."
        )
        return prompt
