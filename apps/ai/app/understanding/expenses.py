"""Expense detection — a second, small LLM call (mejoras-v2 §E).

The v8 extraction prompt and its gate (ADR-018) stay untouched: a cheap regex
(:func:`has_money_cue`) decides whether a capture talks about money, and only
then :func:`detect_expenses` asks the model for the expenses ALREADY MADE.
Future payments ("tengo que pagar la luz") are tasks, never expenses.

The model returns the currency only when the note makes it explicit; an
ambiguous one ("$", "pesos") is resolved to the user's currency by the caller.
Amounts and categories are normalised here, so the graph never stores a
negative amount, an unknown category or a malformed currency code.
"""

import json
import logging
import re
import time
from dataclasses import dataclass

from pydantic import BaseModel, Field, ValidationError, field_validator

from app.providers.base import AIProvider, Usage
from app.understanding.extract import CAPTURE_CLOSE, CAPTURE_OPEN
from app.understanding.text_utils import normalize_label

logger = logging.getLogger(__name__)

EXPENSE_PROMPT_VERSION = "expenses-v1"

#: Canonical categories (the API and the app use the same keys).
EXPENSE_CATEGORIES: tuple[str, ...] = (
    "food",
    "transport",
    "home",
    "health",
    "leisure",
    "shopping",
    "bills",
    "education",
    "other",
)

MAX_AMOUNT = 100_000_000.0
MAX_DESCRIPTION = 120

# --- money cues --------------------------------------------------------------
# Generous on purpose: a false positive only costs one small call, a false
# negative loses an expense. Checked against the lowercased raw text (symbols)
# and the accent-folded text (words and verbs).
_SYMBOL_NUMBER = re.compile(
    r"(?:r\$|us\$|s/\.?|\$|€|£|¥|₡|₲|₱|₹)\s?\d|\d\s?(?:€|\$|£)"
)
_CODES = (
    "usd|eur|brl|mxn|cop|ars|clp|pen|uyu|pyg|bob|gbp|cad|dop|gtq|crc|hnl|nio"
    "|pab|ves|jpy|chf|aud"
)
_NUMBER_CODE = re.compile(
    rf"\d[\d.,]*\s?(?:{_CODES})\b|\b(?:{_CODES})\s?\d", re.IGNORECASE
)
# Words that only name money. Ambiguous ones ("real", "soles", "Lucas") are
# left out on purpose; with a digit they are still caught by the verbs below.
_CURRENCY_WORD = re.compile(
    r"\b(?:pesos?|reais|dolares|dolar|dollars?|bucks|euros?|"
    r"quetzales|bolivares|colones|centavos|cents)\b"
)
_SPEND_VERB = re.compile(
    r"\b(?:gaste|gasto|gastamos|gastaron|gastei|gastou|gastamos|spent|spend|"
    r"pague|pago|pagamos|pagaron|paguei|pagou|paid|"
    r"compre|compro|compramos|compraron|comprei|comprou|bought|"
    r"costo|costaron|custou|custaram|cost|costs|charged|me salio|sairam|saiu)\b"
)
_DIGIT = re.compile(r"\d")


def has_money_cue(text: str) -> bool:
    """True when the capture probably mentions money (cheap pre-filter)."""
    if not text:
        return False
    raw = text.lower()
    if _SYMBOL_NUMBER.search(raw) or _NUMBER_CODE.search(raw):
        return True
    folded = normalize_label(text)
    if _CURRENCY_WORD.search(folded):
        return True
    return bool(_SPEND_VERB.search(folded) and _DIGIT.search(folded))


# --- prompt ------------------------------------------------------------------
EXPENSE_PROMPT_V1 = (
    "You extract the EXPENSES from one personal note (Spanish, Portuguese or "
    "English).\n"
    "Rules:\n"
    "1. Only money the user ALREADY spent or paid (past tense, or a "
    "receipt-like line such as \"almuerzo 25 reais\" or \"taxi $12\"). Future "
    "or pending payments (\"tengo que pagar la luz\", \"vou pagar\", \"pay "
    "rent tomorrow\"), budgets, prices seen, income, money received or lent "
    "are NOT expenses: return nothing for them.\n"
    "2. amount: positive number, dot as decimal separator (1.234,50 -> "
    "1234.5; \"veinte\" -> 20). One entry per distinct expense; never merge "
    "different expenses; if the note gives a total and its parts, return the "
    "parts. No amount in the note -> no expense. Never invent.\n"
    "3. currency: ISO-4217 code ONLY when the note makes it explicit: "
    "R$/reais -> BRL, euro/€ -> EUR, US$/USD/dólares -> USD, £ -> GBP, "
    "soles/S/ -> PEN, or an explicit code (MXN, COP, ARS, CLP...). A bare "
    "\"$\" or \"pesos\" is ambiguous -> null.\n"
    "4. category: exactly one of food (groceries, restaurants, coffee, "
    "delivery), transport (taxi, Uber, bus, fuel, parking), home (rent, "
    "repairs, furniture, cleaning), health (pharmacy, doctor, dentist, "
    "therapy), leisure (cinema, bars, trips, games, streaming), shopping "
    "(clothes, electronics, gifts), bills (electricity, water, gas, internet, "
    "phone, insurance, taxes), education (courses, school, study books), "
    "other.\n"
    "5. description: 1 to 6 words in the note's language saying what it was "
    "for (\"almuerzo con Ana\", \"Uber al aeropuerto\").\n"
    "Return JSON only, exactly this shape: "
    "{\"expenses\":[{\"amount\":25,\"currency\":\"BRL\",\"category\":\"food\","
    "\"description\":\"almuerzo\"}]} or {\"expenses\":[]}."
)

EXPENSE_SCHEMA: dict = {
    "type": "object",
    "properties": {
        "expenses": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "amount": {"type": "number"},
                    "currency": {"type": ["string", "null"]},
                    "category": {"type": "string", "enum": list(EXPENSE_CATEGORIES)},
                    "description": {"type": "string"},
                },
                "required": ["amount", "category"],
            },
        }
    },
    "required": ["expenses"],
}


def build_expense_prompt(text: str) -> str:
    return f"{EXPENSE_PROMPT_V1}\n\nNote:\n{CAPTURE_OPEN}\n{text}\n{CAPTURE_CLOSE}\n"


# --- parsing -----------------------------------------------------------------
_AMOUNT_JUNK = re.compile(r"[^\d.,\-]")


def parse_amount(value: object) -> float | None:
    """Parse a model amount, tolerating "1.234,50", "12,5" or "$ 20"."""
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if not isinstance(value, str):
        return None
    text = _AMOUNT_JUNK.sub("", value.strip())
    if not text or text.count("-") > 0:
        return None
    if "," in text and "." in text:
        # The last separator is the decimal one.
        if text.rfind(",") > text.rfind("."):
            text = text.replace(".", "").replace(",", ".")
        else:
            text = text.replace(",", "")
    elif "," in text or "." in text:
        sep = "," if "," in text else "."
        head, _, tail = text.rpartition(sep)
        if len(tail) == 3 and head:
            text = text.replace(sep, "")  # thousands: 1.500 / 1,500
        else:
            text = head.replace(sep, "") + "." + tail
    try:
        return float(text)
    except ValueError:
        return None


class ExpenseItem(BaseModel):
    """One expense, already normalised."""

    amount: float = Field(gt=0, le=MAX_AMOUNT)
    currency: str | None = None
    category: str = "other"
    description: str = ""

    @field_validator("amount", mode="before")
    @classmethod
    def _amount(cls, value: object) -> object:
        parsed = parse_amount(value)
        return round(parsed, 2) if parsed is not None else value

    @field_validator("currency", mode="before")
    @classmethod
    def _currency(cls, value: object) -> str | None:
        if not isinstance(value, str):
            return None
        code = value.strip().upper()
        return code if re.fullmatch(r"[A-Z]{3}", code) else None

    @field_validator("category", mode="before")
    @classmethod
    def _category(cls, value: object) -> str:
        key = value.strip().lower() if isinstance(value, str) else ""
        return key if key in EXPENSE_CATEGORIES else "other"

    @field_validator("description", mode="before")
    @classmethod
    def _description(cls, value: object) -> str:
        if not isinstance(value, str):
            return ""
        return re.sub(r"\s+", " ", value).strip()[:MAX_DESCRIPTION]


def parse_expenses(raw_json: str) -> list[ExpenseItem]:
    """Parse the model output; invalid items are dropped, not guessed.

    Raises ``ValueError`` only when the output is not the expected JSON shape.
    """
    try:
        data = json.loads(raw_json)
    except json.JSONDecodeError as exc:
        raise ValueError(f"provider returned malformed JSON: {exc}") from exc
    items = data.get("expenses") if isinstance(data, dict) else None
    if not isinstance(items, list):
        raise ValueError("provider output has no 'expenses' list")
    expenses: list[ExpenseItem] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        try:
            expenses.append(ExpenseItem.model_validate(item))
        except ValidationError:
            continue  # e.g. a zero/negative amount: never stored
    return expenses


@dataclass(frozen=True)
class ExpenseResult:
    expenses: list[ExpenseItem]
    usage: Usage | None
    latency_ms: float


async def detect_expenses(text: str, provider: AIProvider) -> ExpenseResult:
    """Expenses already made in ``text``; no model call without a money cue.

    Invalid model output yields no expenses (logged) rather than an error: the
    expense detector must never fail the comprehension of the capture.
    """
    if not has_money_cue(text):
        return ExpenseResult(expenses=[], usage=None, latency_ms=0.0)
    started = time.perf_counter()
    completion = await provider.complete(
        build_expense_prompt(text), schema=EXPENSE_SCHEMA
    )
    latency_ms = (time.perf_counter() - started) * 1000.0
    try:
        expenses = parse_expenses(completion.text)
    except ValueError as exc:
        logger.warning("expense detection returned invalid output: %s", exc)
        expenses = []
    return ExpenseResult(
        expenses=expenses, usage=completion.usage, latency_ms=latency_ms
    )
