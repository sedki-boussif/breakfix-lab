"""Three invented tables. The stand-in carries the topology, not the real
schema: trainees are placed on wards, and anything that matters is written to
an append-only audit log.
"""
from datetime import date, datetime

from sqlalchemy import Date, DateTime, ForeignKey, Index, String, Text, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


class Base(DeclarativeBase):
    pass


class Trainee(Base):
    __tablename__ = "trainees"

    id: Mapped[int] = mapped_column(primary_key=True)
    ref: Mapped[str] = mapped_column(String(16), unique=True)
    full_name: Mapped[str] = mapped_column(String(120))
    cohort: Mapped[str] = mapped_column(String(16))
    email: Mapped[str] = mapped_column(String(160))

    placements: Mapped[list["Placement"]] = relationship(back_populates="trainee")


class Placement(Base):
    """The big table. Queries filter on (ward, started_on), which is why that
    index exists and why dropping it is measurable rather than theoretical.
    """
    __tablename__ = "placements"

    id: Mapped[int] = mapped_column(primary_key=True)
    trainee_id: Mapped[int] = mapped_column(ForeignKey("trainees.id"))
    ward: Mapped[str] = mapped_column(String(40))
    started_on: Mapped[date] = mapped_column(Date)
    ended_on: Mapped[date | None] = mapped_column(Date, nullable=True)
    status: Mapped[str] = mapped_column(String(16), default="planned")

    trainee: Mapped[Trainee] = relationship(back_populates="placements")

    __table_args__ = (Index("ix_placements_ward_started", "ward", "started_on"),)


class AuditLog(Base):
    """Append-only by permission, not by convention: the role the app connects
    with has SELECT and INSERT here and nothing else.
    """
    __tablename__ = "audit_log"

    id: Mapped[int] = mapped_column(primary_key=True)
    at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    actor: Mapped[str] = mapped_column(String(80))
    action: Mapped[str] = mapped_column(String(40))
    detail: Mapped[str] = mapped_column(Text, default="")
