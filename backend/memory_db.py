"""In-memory database for local development without Supabase."""

import uuid
from typing import Optional, List, Dict, Any
from datetime import datetime

# In-memory storage
_sessions = {}
_messages = {}
_presets = {}
_predictions = {}


# =============================================================================
# SESSION OPERATIONS
# =============================================================================

def create_session(
    session_id: str,
    council_type: str = "general",
    mode: str = "synthesized",
    models: Optional[List[str]] = None,
    chairman_model: Optional[str] = None,
    roles_enabled: bool = False,
    enhancements: Optional[List[str]] = None,
    user_id: Optional[str] = None
) -> Dict[str, Any]:
    """Create a new session."""
    session = {
        "id": session_id,
        "council_type": council_type,
        "council_mode": mode,
        "models": models,
        "chairman_model": chairman_model,
        "roles_enabled": roles_enabled,
        "enhancements": enhancements,
        "user_id": user_id,
        "created_at": datetime.utcnow().isoformat(),
        "is_archived": False,
        "message_count": 0,
        "title": None,
    }
    _sessions[session_id] = session
    _messages[session_id] = []
    return session


def get_session(session_id: str, user_id: Optional[str] = None) -> Optional[Dict[str, Any]]:
    """Get a session by ID."""
    return _sessions.get(session_id)


def list_sessions(user_id: Optional[str] = None, include_archived: bool = False) -> List[Dict[str, Any]]:
    """List all sessions."""
    sessions = list(_sessions.values())
    if not include_archived:
        sessions = [s for s in sessions if not s.get("is_archived", False)]
    return sorted(sessions, key=lambda x: x["created_at"], reverse=True)


def update_session_title(session_id: str, title: str, user_id: Optional[str] = None) -> bool:
    """Update session title."""
    if session_id in _sessions:
        _sessions[session_id]["title"] = title
        return True
    return False


def archive_session(session_id: str, is_archived: bool, user_id: Optional[str] = None) -> bool:
    """Archive or unarchive a session."""
    if session_id in _sessions:
        _sessions[session_id]["is_archived"] = is_archived
        return True
    return False


def delete_session(session_id: str, user_id: Optional[str] = None) -> bool:
    """Delete a session."""
    if session_id in _sessions:
        del _sessions[session_id]
        if session_id in _messages:
            del _messages[session_id]
        return True
    return False


# =============================================================================
# MESSAGE OPERATIONS
# =============================================================================

def add_message(
    session_id: str,
    role: str,
    content: Optional[str] = None,
    stage_data: Optional[Dict[str, Any]] = None,
    user_id: Optional[str] = None
) -> Dict[str, Any]:
    """Add a message to a session."""
    if session_id not in _messages:
        _messages[session_id] = []

    message = {
        "id": str(uuid.uuid4()),
        "session_id": session_id,
        "role": role,
        "content": content,
        "stage_data": stage_data,
        "created_at": datetime.utcnow().isoformat(),
    }
    _messages[session_id].append(message)

    # Update message count
    if session_id in _sessions:
        _sessions[session_id]["message_count"] = len(_messages[session_id])

    return message


def get_messages(session_id: str, user_id: Optional[str] = None) -> List[Dict[str, Any]]:
    """Get all messages for a session."""
    return _messages.get(session_id, [])


# =============================================================================
# PRESET OPERATIONS
# =============================================================================

def create_preset(
    name: str,
    models: List[str],
    chairman_model: Optional[str] = None,
    description: Optional[str] = None,
    user_id: Optional[str] = None
) -> Dict[str, Any]:
    """Create a model preset."""
    preset_id = str(uuid.uuid4())
    preset = {
        "id": preset_id,
        "name": name,
        "models": models,
        "chairman_model": chairman_model,
        "description": description,
        "user_id": user_id,
        "created_at": datetime.utcnow().isoformat(),
    }
    _presets[preset_id] = preset
    return preset


def list_presets(user_id: Optional[str] = None) -> List[Dict[str, Any]]:
    """List all presets."""
    return list(_presets.values())


def get_preset(preset_id: str, user_id: Optional[str] = None) -> Optional[Dict[str, Any]]:
    """Get a preset by ID."""
    return _presets.get(preset_id)


def delete_preset(preset_id: str, user_id: Optional[str] = None) -> bool:
    """Delete a preset."""
    if preset_id in _presets:
        del _presets[preset_id]
        return True
    return False


# =============================================================================
# PREDICTION OPERATIONS
# =============================================================================

def create_prediction(
    session_id: str,
    prediction_text: str,
    model_name: Optional[str] = None,
    category: Optional[str] = None,
    user_id: Optional[str] = None
) -> Dict[str, Any]:
    """Create a prediction."""
    prediction_id = str(uuid.uuid4())
    prediction = {
        "id": prediction_id,
        "session_id": session_id,
        "prediction_text": prediction_text,
        "model_name": model_name,
        "category": category,
        "user_id": user_id,
        "created_at": datetime.utcnow().isoformat(),
        "outcome": None,
        "accuracy_score": None,
        "notes": None,
    }
    _predictions[prediction_id] = prediction
    return prediction


def get_prediction(prediction_id: str, user_id: Optional[str] = None) -> Optional[Dict[str, Any]]:
    """Get a prediction by ID."""
    return _predictions.get(prediction_id)


def update_prediction_outcome(
    prediction_id: str,
    outcome: str,
    accuracy_score: Optional[float] = None,
    notes: Optional[str] = None,
    user_id: Optional[str] = None
) -> Optional[Dict[str, Any]]:
    """Update prediction outcome."""
    if prediction_id in _predictions:
        _predictions[prediction_id].update({
            "outcome": outcome,
            "accuracy_score": accuracy_score,
            "notes": notes,
        })
        return _predictions[prediction_id]
    return None


def get_prediction_stats(user_id: Optional[str] = None) -> Dict[str, Any]:
    """Get prediction statistics."""
    preds = list(_predictions.values())
    total = len(preds)
    resolved = len([p for p in preds if p.get("outcome")])

    return {
        "total_predictions": total,
        "resolved_predictions": resolved,
        "by_model": {},
        "by_category": {},
    }


# =============================================================================
# SEARCH OPERATIONS
# =============================================================================

def search_messages(query: str, limit: int = 20, user_id: Optional[str] = None) -> List[Dict[str, Any]]:
    """Search messages."""
    results = []
    query_lower = query.lower()

    for session_id, messages in _messages.items():
        for msg in messages:
            if msg.get("content") and query_lower in msg["content"].lower():
                results.append({
                    "session_id": session_id,
                    "message": msg,
                    "session": _sessions.get(session_id),
                })
                if len(results) >= limit:
                    return results

    return results
