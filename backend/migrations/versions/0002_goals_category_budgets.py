"""goals and category budgets (for the monthly coach)

Revision ID: 0002
Revises: 0001
Create Date: 2026-10-19
"""
import sqlalchemy as sa
from alembic import op

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "goals",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("user_id", sa.String(128), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("name", sa.String(80), nullable=False),
        sa.Column("target_amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("saved_amount", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("target_date", sa.Date),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_goals_user_id", "goals", ["user_id"])
    op.create_table(
        "category_budgets",
        sa.Column("user_id", sa.String(128), sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("category", sa.String(32), primary_key=True),
        sa.Column("amount", sa.Numeric(12, 2), nullable=False),
    )


def downgrade() -> None:
    op.drop_table("category_budgets")
    op.drop_index("ix_goals_user_id", table_name="goals")
    op.drop_table("goals")
