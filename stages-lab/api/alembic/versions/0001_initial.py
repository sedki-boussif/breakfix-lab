"""Initial schema, plus the grants that make audit_log append-only for the
application's role.

Revision ID: 0001_initial
"""
import os

import sqlalchemy as sa
from alembic import op

revision = "0001_initial"
down_revision = None
branch_labels = None
depends_on = None

APP_ROLE = os.environ.get("APP_DB_ROLE", "stages_app")


def upgrade():
    op.create_table(
        "trainees",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("ref", sa.String(16), nullable=False, unique=True),
        sa.Column("full_name", sa.String(120), nullable=False),
        sa.Column("cohort", sa.String(16), nullable=False),
        sa.Column("email", sa.String(160), nullable=False),
    )
    op.create_table(
        "placements",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("trainee_id", sa.Integer, sa.ForeignKey("trainees.id"), nullable=False),
        sa.Column("ward", sa.String(40), nullable=False),
        sa.Column("started_on", sa.Date, nullable=False),
        sa.Column("ended_on", sa.Date, nullable=True),
        sa.Column("status", sa.String(16), nullable=False, server_default="planned"),
    )
    op.create_index("ix_placements_ward_started", "placements", ["ward", "started_on"])
    op.create_table(
        "audit_log",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("actor", sa.String(80), nullable=False),
        sa.Column("action", sa.String(40), nullable=False),
        sa.Column("detail", sa.Text, nullable=False, server_default=""),
    )

    # The application's role: full rights where it needs them, append-only on
    # the audit log. No UPDATE, no DELETE, no TRUNCATE there, ever.
    op.execute(f"GRANT USAGE ON SCHEMA public TO {APP_ROLE}")
    op.execute(f"GRANT SELECT, INSERT, UPDATE, DELETE ON trainees, placements TO {APP_ROLE}")
    op.execute(f"GRANT SELECT, INSERT ON audit_log TO {APP_ROLE}")
    op.execute(f"GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO {APP_ROLE}")


def downgrade():
    op.drop_table("audit_log")
    op.drop_index("ix_placements_ward_started", table_name="placements")
    op.drop_table("placements")
    op.drop_table("trainees")
