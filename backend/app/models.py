from datetime import date, datetime, timezone
from decimal import Decimal

from sqlalchemy import Date, DateTime, ForeignKey, Index, Integer, Numeric, String
from sqlalchemy.orm import Mapped, mapped_column

from .extensions import db

CATEGORIES = (
    "food",
    "groceries",
    "transport",
    "shopping",
    "bills",
    "entertainment",
    "health",
    "travel",
    "education",
    "other",
)


def _now() -> datetime:
    return datetime.now(timezone.utc)


class User(db.Model):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(128), primary_key=True)  # Firebase uid
    email: Mapped[str | None] = mapped_column(String(320))
    monthly_budget: Mapped[Decimal | None] = mapped_column(Numeric(12, 2))
    currency: Mapped[str] = mapped_column(String(3), default="INR", nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, nullable=False)

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "email": self.email,
            "monthly_budget": float(self.monthly_budget) if self.monthly_budget is not None else None,
            "currency": self.currency,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }


class Expense(db.Model):
    __tablename__ = "expenses"
    __table_args__ = (Index("ix_expenses_user_spent_on", "user_id", "spent_on"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[str] = mapped_column(
        String(128), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    category: Mapped[str] = mapped_column(String(32), nullable=False)
    note: Mapped[str] = mapped_column(String(200), default="", nullable=False)
    spent_on: Mapped[date] = mapped_column(Date, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_now, onupdate=_now, nullable=False
    )

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "amount": float(self.amount),
            "category": self.category,
            "note": self.note,
            "spent_on": self.spent_on.isoformat(),
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }


class ChatUsage(db.Model):
    __tablename__ = "chat_usage"

    user_id: Mapped[str] = mapped_column(
        String(128), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    day: Mapped[date] = mapped_column(Date, primary_key=True)
    count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
