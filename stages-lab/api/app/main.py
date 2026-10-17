"""The stand-in API. Enough endpoints for the challenges that touch App A:
a health check, a listing whose query depends on an index, an upload that
writes to the uploads volume, and an append-only audit trail.
"""
import os
from pathlib import Path

from fastapi import Depends, FastAPI, File, HTTPException, UploadFile
from sqlalchemy import func, select, text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from .config import load
from .db import session
from .models import AuditLog, Placement, Trainee

settings = load()
app = FastAPI(title="stages-lab (stand-in)", debug=settings.debug)
UPLOADS = Path(settings.uploads_dir)


@app.get("/api/health/")
def health(db: Session = Depends(session)):
    """Healthy means the database answers, not merely that the process is up."""
    try:
        db.execute(text("SELECT 1"))
    except SQLAlchemyError as exc:
        raise HTTPException(status_code=503, detail=f"database unreachable: {exc.__class__.__name__}")
    return {"status": "ok", "env": settings.app_env}


@app.get("/api/trainees/")
def trainees(db: Session = Depends(session), limit: int = 50):
    rows = db.execute(select(Trainee).order_by(Trainee.ref).limit(limit)).scalars().all()
    return [{"ref": t.ref, "full_name": t.full_name, "cohort": t.cohort} for t in rows]


@app.get("/api/placements/")
def placements(ward: str | None = None, db: Session = Depends(session), limit: int = 100):
    """Filters on (ward, started_on). This is the query the index serves, and
    the one that falls off a cliff without it.
    """
    stmt = select(Placement)
    if ward:
        stmt = stmt.where(Placement.ward == ward)
    stmt = stmt.order_by(Placement.started_on.desc()).limit(limit)
    rows = db.execute(stmt).scalars().all()
    return [
        {"id": p.id, "ward": p.ward, "started_on": str(p.started_on), "status": p.status}
        for p in rows
    ]


@app.get("/api/placements/count/")
def placement_count(db: Session = Depends(session)):
    return {"placements": db.execute(select(func.count()).select_from(Placement)).scalar_one()}


@app.post("/api/uploads/")
def upload(file: UploadFile = File(...), db: Session = Depends(session)):
    """Writes to the uploads volume. Fails loudly, with the errno, when the
    volume is not writable by the user this container runs as.
    """
    name = os.path.basename(file.filename or "unnamed")
    if not name or name.startswith("."):
        raise HTTPException(status_code=400, detail="unusable filename")
    target = UPLOADS / name
    try:
        UPLOADS.mkdir(parents=True, exist_ok=True)
        target.write_bytes(file.file.read())
    except OSError as exc:
        raise HTTPException(status_code=500, detail=f"cannot write {target}: {exc.strerror}")
    db.add(AuditLog(actor="api", action="upload", detail=name))
    db.commit()
    return {"stored": name, "bytes": target.stat().st_size}


@app.get("/api/uploads/{name}/")
def read_upload(name: str):
    target = UPLOADS / os.path.basename(name)
    if not target.is_file():
        raise HTTPException(status_code=404, detail="no such upload")
    try:
        return {"name": target.name, "bytes": len(target.read_bytes())}
    except OSError as exc:
        raise HTTPException(status_code=500, detail=f"cannot read {target}: {exc.strerror}")


@app.get("/api/audit/")
def audit(db: Session = Depends(session), limit: int = 20):
    rows = db.execute(select(AuditLog).order_by(AuditLog.id.desc()).limit(limit)).scalars().all()
    return [{"id": r.id, "at": str(r.at), "actor": r.actor, "action": r.action} for r in rows]
