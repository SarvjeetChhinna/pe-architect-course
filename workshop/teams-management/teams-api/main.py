from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from typing import List, Dict, Optional
import uuid
from datetime import datetime
import re

app = FastAPI(
    title="Teams API",
    description="A simple API for team leads to create and manage teams",
    version="1.0.0"
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allows all origins
    allow_credentials=True,
    allow_methods=["*"],  # Allows all methods
    allow_headers=["*"],  # Allows all headers
)

# In-memory storage
teams_store: Dict[str, Dict] = {}

# Pydantic models
class TeamCreate(BaseModel):
    name: str
    namespace: Optional[str] = None
    owner: Optional[str] = None
    labels: Optional[Dict[str, str]] = None
    annotations: Optional[Dict[str, str]] = None

class Team(BaseModel):
    id: str
    name: str
    namespace: str
    owner: Optional[str] = None
    labels: Dict[str, str] = Field(default_factory=dict)
    annotations: Dict[str, str] = Field(default_factory=dict)
    created_at: datetime


def sanitize_namespace_name(team_name: str) -> str:
    namespace = team_name.lower()
    namespace = ''.join(c if c.isalnum() else '-' for c in namespace)
    namespace = '-'.join(filter(None, namespace.split('-')))
    namespace = namespace.strip('-')

    if len(namespace) > 63:
        namespace = namespace[:63].rstrip('-')

    namespace = f"team-{namespace}"
    return namespace


def validate_namespace_name(namespace: str) -> None:
    if len(namespace) == 0 or len(namespace) > 63:
        raise HTTPException(status_code=400, detail="Namespace must be 1-63 characters")

    if not re.fullmatch(r"[a-z0-9]([-a-z0-9]*[a-z0-9])?", namespace):
        raise HTTPException(
            status_code=400,
            detail="Namespace must be a valid DNS-1123 label (lowercase alphanumeric and '-')",
        )

@app.get("/")
async def root():
    return {"message": "Teams API is running"}

@app.post("/teams", response_model=Team)
async def create_team(team: TeamCreate):
    """Create a new team"""
    # Check if team name already exists
    for existing_team in teams_store.values():
        if existing_team["name"].lower() == team.name.lower():
            raise HTTPException(status_code=400, detail="Team name already exists")

    namespace = team.namespace or sanitize_namespace_name(team.name)
    validate_namespace_name(namespace)

    for existing_team in teams_store.values():
        if existing_team.get("namespace") == namespace:
            raise HTTPException(status_code=400, detail="Namespace already exists")

    # Generate unique ID and create team
    team_id = str(uuid.uuid4())
    new_team = {
        "id": team_id,
        "name": team.name,
        "namespace": namespace,
        "owner": team.owner,
        "labels": team.labels or {},
        "annotations": team.annotations or {},
        "created_at": datetime.now()
    }

    teams_store[team_id] = new_team
    return Team(**new_team)

@app.get("/teams", response_model=List[Team])
async def get_teams():
    """Get all teams"""
    return [Team(**team) for team in teams_store.values()]

@app.get("/teams/{team_id}", response_model=Team)
async def get_team(team_id: str):
    """Get a specific team by ID"""
    if team_id not in teams_store:
        raise HTTPException(status_code=404, detail="Team not found")

    return Team(**teams_store[team_id])

@app.delete("/teams/{team_id}")
async def delete_team(team_id: str):
    """Delete a team"""
    if team_id not in teams_store:
        raise HTTPException(status_code=404, detail="Team not found")

    deleted_team = teams_store.pop(team_id)
    return {"message": f"Team '{deleted_team['name']}' deleted successfully"}

@app.get("/health")
async def health_check():
    """Health check endpoint for Kubernetes"""
    return {"status": "healthy", "teams_count": len(teams_store)}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
