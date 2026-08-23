import json
import os
from pathlib import Path

import firebase_admin
from dotenv import load_dotenv
from firebase_admin import credentials, firestore, messaging


_BACKEND_DIR = Path(__file__).resolve().parent
load_dotenv(_BACKEND_DIR / ".env")


def _load_firebase_credentials():
    service_account_json = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON", "").strip()
    if service_account_json:
        try:
            return credentials.Certificate(json.loads(service_account_json))
        except json.JSONDecodeError as error:
            raise RuntimeError(
                "FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON"
            ) from error

    service_account_path = os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH", "").strip()
    if service_account_path:
        resolved_path = Path(service_account_path).expanduser()
        if not resolved_path.is_absolute():
            resolved_path = (_BACKEND_DIR / resolved_path).resolve()
        if not resolved_path.is_file():
            raise FileNotFoundError(
                f"Firebase service account file not found: {resolved_path}"
            )
        return credentials.Certificate(str(resolved_path))

    default_local_path = _BACKEND_DIR / "serviceAccountKey.json"
    if default_local_path.is_file():
        return credentials.Certificate(str(default_local_path))

    raise RuntimeError(
        "Firebase Admin credentials are not configured. "
        "Set FIREBASE_SERVICE_ACCOUNT_PATH or FIREBASE_SERVICE_ACCOUNT_JSON."
    )

# Initialize Firebase only once.
if not firebase_admin._apps:
    cred = _load_firebase_credentials()
    firebase_admin.initialize_app(cred)

db = firestore.client()


def _string_map(value):
    if not isinstance(value, dict):
        return {}

    normalized = {}
    for key, item in value.items():
        key_text = str(key).strip()
        item_text = str(item).strip()
        if key_text and item_text:
            normalized[key_text] = item_text

    return normalized


def send_push_notification_to_user(user_id, title, body, data=None):
    normalized_user_id = str(user_id or "").strip()
    normalized_title = str(title or "").strip()
    normalized_body = str(body or "").strip()

    if not normalized_user_id:
        return {"success": False, "error": "userId is required"}

    user_doc = db.collection("users").document(normalized_user_id).get()
    if not user_doc.exists:
        return {"success": False, "error": "User not found"}

    user_data = user_doc.to_dict() or {}
    fcm_token = str(user_data.get("fcmToken") or "").strip()
    if not fcm_token:
        return {"success": False, "error": "No FCM token for user"}

    payload = _string_map(data)

    message = messaging.Message(
        token=fcm_token,
        notification=messaging.Notification(
            title=normalized_title or "Saneea",
            body=normalized_body or "You have a new update.",
        ),
        data=payload,
        android=messaging.AndroidConfig(
            priority="high",
            notification=messaging.AndroidNotification(
                channel_id="request_notifications",
                sound="default",
            ),
        ),
        apns=messaging.APNSConfig(
            headers={"apns-priority": "10"},
            payload=messaging.APNSPayload(
                aps=messaging.Aps(sound="default"),
            ),
        ),
    )

    message_id = messaging.send(message)
    return {"success": True, "messageId": message_id}


def _as_dict(value):
    return value if isinstance(value, dict) else {}


def _safe_int(value):
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def _string_list(value):
    if not isinstance(value, list):
        return []

    normalized = []
    for item in value:
        text = str(item).strip()
        if text:
            normalized.append(text)

    return normalized


def get_request_by_id(request_id):
    doc = db.collection("requests").document(request_id).get()

    if not doc.exists:
        return None

    return doc.to_dict()


def get_announcement_proposal_by_id(proposal_id):
    normalized_proposal_id = str(proposal_id or "").strip()
    if not normalized_proposal_id:
        return None

    doc = db.collection("announcement_requests").document(
        normalized_proposal_id
    ).get()

    if not doc.exists:
        return None

    data = doc.to_dict() or {}
    data["proposalId"] = normalized_proposal_id
    return data


def get_announcement_by_client_and_id(client_id, announcement_id):
    normalized_client_id = str(client_id or "").strip()
    normalized_announcement_id = str(announcement_id or "").strip()
    if not normalized_client_id or not normalized_announcement_id:
        return None

    doc = db.collection("users").document(normalized_client_id).collection(
        "announcements"
    ).document(normalized_announcement_id).get()

    if not doc.exists:
        return None

    return doc


def _find_announcement_document_by_id(announcement_id):
    normalized_announcement_id = str(announcement_id or "").strip()
    if not normalized_announcement_id:
        return None

    for doc in db.collection_group("announcements").stream():
        if doc.id == normalized_announcement_id:
            return doc

    return None


def _normalize_announcement_request_data(announcement_doc, announcement_id):
    announcement_data = announcement_doc.to_dict() or {}
    parent_doc = announcement_doc.reference.parent.parent
    parent_client_id = parent_doc.id if parent_doc else ""

    client_id = str(
        announcement_data.get("clientId")
        or announcement_data.get("userId")
        or parent_client_id
        or ""
    ).strip()
    client_name = str(
        announcement_data.get("clientName")
        or announcement_data.get("userName")
        or ""
    ).strip()
    description = str(announcement_data.get("description") or "").strip()

    budget = announcement_data.get("budget")
    amount = announcement_data.get("amount")
    if amount in (None, ""):
        amount = budget
    if budget in (None, ""):
        budget = amount

    deadline = announcement_data.get("deadline")
    if deadline in (None, ""):
        deadline = announcement_data.get("duration")

    category = str(
        announcement_data.get("category")
        or announcement_data.get("serviceType")
        or ""
    ).strip()
    service_type = str(
        announcement_data.get("serviceType")
        or announcement_data.get("category")
        or ""
    ).strip()

    normalized_data = dict(announcement_data)
    normalized_data.update({
        "clientId": client_id,
        "clientName": client_name,
        "description": description,
        "budget": budget,
        "amount": amount,
        "deadline": deadline,
        "category": category,
        "serviceType": service_type,
        "announcementId": str(announcement_id or "").strip(),
        "source": "announcement",
    })

    return normalized_data


def _merge_proposal_context(base_data, proposal_data, expected_announcement_id=None):
    merged = dict(base_data) if isinstance(base_data, dict) else {}
    normalized_proposal = proposal_data if isinstance(proposal_data, dict) else {}
    if not normalized_proposal:
        return merged

    proposal_announcement_id = str(
        normalized_proposal.get("announcementId") or ""
    ).strip()
    normalized_expected_announcement_id = str(
        expected_announcement_id or ""
    ).strip()

    if (
        normalized_expected_announcement_id
        and proposal_announcement_id
        and proposal_announcement_id != normalized_expected_announcement_id
    ):
        return merged

    if normalized_proposal.get("proposalId"):
        merged["proposalId"] = normalized_proposal.get("proposalId")

    freelancer_id = str(normalized_proposal.get("freelancerId") or "").strip()
    if freelancer_id and not str(merged.get("freelancerId") or "").strip():
        merged["freelancerId"] = freelancer_id

    freelancer_name = str(
        normalized_proposal.get("freelancerName") or ""
    ).strip()
    if freelancer_name and not str(merged.get("freelancerName") or "").strip():
        merged["freelancerName"] = freelancer_name

    proposal_text = str(normalized_proposal.get("proposalText") or "").strip()
    if proposal_text:
        merged["proposalText"] = proposal_text

    return merged


def get_contract_source_by_id(request_id, proposal_id=None):
    normalized_request_id = str(request_id or "").strip()
    normalized_proposal_id = str(proposal_id or "").strip()

    if not normalized_request_id:
        return None

    request_data = get_request_by_id(normalized_request_id)
    if request_data:
        return {
            "source": "request",
            "requestId": normalized_request_id,
            "data": request_data,
        }

    if not normalized_proposal_id:
        return None

    proposal_data = get_announcement_proposal_by_id(normalized_proposal_id)
    print(f"proposal data loaded: {proposal_data}")
    if not proposal_data:
        return None

    announcement_id = str(
        proposal_data.get("announcementId") or normalized_request_id
    ).strip()
    client_id = str(proposal_data.get("clientId") or "").strip()
    print(f"announcementId resolved: {announcement_id}")

    announcement_doc = get_announcement_by_client_and_id(client_id, announcement_id)
    if not announcement_doc:
        return None

    announcement_data = announcement_doc.to_dict() or {}
    print(f"original announcement data loaded: {announcement_data}")

    normalized_announcement_data = _normalize_announcement_request_data(
        announcement_doc,
        announcement_id,
    )
    normalized_announcement_data.update({
        "clientId": str(
            normalized_announcement_data.get("clientId")
            or proposal_data.get("clientId")
            or ""
        ).strip(),
        "clientName": str(
            normalized_announcement_data.get("clientName") or ""
        ).strip(),
        "freelancerId": str(proposal_data.get("freelancerId") or "").strip(),
        "freelancerName": str(
            proposal_data.get("freelancerName") or ""
        ).strip(),
        "description": str(
            normalized_announcement_data.get("description") or ""
        ).strip(),
        "proposalText": str(proposal_data.get("proposalText") or "").strip(),
        "amount": normalized_announcement_data.get("amount")
        or normalized_announcement_data.get("budget"),
        "budget": normalized_announcement_data.get("budget")
        or normalized_announcement_data.get("amount"),
        "deadline": normalized_announcement_data.get("deadline"),
        "category": str(
            normalized_announcement_data.get("category") or ""
        ).strip(),
        "serviceType": str(
            normalized_announcement_data.get("serviceType") or ""
        ).strip(),
        "source": "announcement",
        "announcementId": announcement_id,
        "proposalId": normalized_proposal_id,
    })
    print(
        "final description used: "
        + str(normalized_announcement_data.get("description") or "")
    )

    return {
        "source": "announcement",
        "announcementId": announcement_id,
        "proposalId": normalized_proposal_id,
        "clientId": normalized_announcement_data.get("clientId", ""),
        "data": normalized_announcement_data,
    }


def update_request_contract_data(request_id, contract_data):
    # Save the updated contract inside the existing request document.
    db.collection("requests").document(request_id).update({
        "contractData": contract_data
    })


def update_announcement_contract_data(client_id, announcement_id, contract_data):
    normalized_client_id = str(client_id or "").strip()
    normalized_announcement_id = str(announcement_id or "").strip()

    if not normalized_client_id or not normalized_announcement_id:
        raise ValueError(
            "client_id and announcement_id are required to save announcement contract data"
        )

    db.collection("users").document(normalized_client_id).collection(
        "announcements"
    ).document(normalized_announcement_id).update({
        "contractData": contract_data
    })


def update_announcement_proposal_contract_data(proposal_id, contract_data):
    normalized_proposal_id = str(proposal_id or "").strip()
    if not normalized_proposal_id:
        raise ValueError(
            "proposal_id is required to save announcement proposal contract data"
        )

    db.collection("announcement_requests").document(normalized_proposal_id).update({
        "contractData": contract_data
    })


def delete_request_contract_data(request_id):
    db.collection("requests").document(request_id).update({
        "contractData": firestore.DELETE_FIELD
    })


def delete_announcement_proposal_contract_data(proposal_id):
    normalized_proposal_id = str(proposal_id or "").strip()
    if not normalized_proposal_id:
        raise ValueError(
            "proposal_id is required to delete announcement proposal contract data"
        )

    db.collection("announcement_requests").document(normalized_proposal_id).update({
        "contractData": firestore.DELETE_FIELD
    })


def delete_announcement_contract_data(client_id, announcement_id):
    normalized_client_id = str(client_id or "").strip()
    normalized_announcement_id = str(announcement_id or "").strip()

    if not normalized_client_id or not normalized_announcement_id:
        raise ValueError(
            "client_id and announcement_id are required to delete announcement contract data"
        )

    db.collection("users").document(normalized_client_id).collection(
        "announcements"
    ).document(normalized_announcement_id).update({
        "contractData": firestore.DELETE_FIELD
    })


def create_approved_contract_chat_message(
    request_id,
    request_data,
    contract_data,
    sender_role,
    contract_text="",
):
    normalized_request_id = str(request_id or "").strip()
    if not normalized_request_id:
        raise ValueError("request_id is required")

    normalized_request_data = _as_dict(request_data)
    normalized_contract_data = _as_dict(contract_data)
    normalized_sender_role = str(sender_role or "").strip().lower()

    chat_ref = db.collection("chat").document(normalized_request_id)
    chat_doc = chat_ref.get()
    chat_data = _as_dict(chat_doc.to_dict()) if chat_doc.exists else {}

    client_id = str(normalized_request_data.get("clientId", "")).strip()
    freelancer_id = str(normalized_request_data.get("freelancerId", "")).strip()

    if normalized_sender_role == "client":
        sender_id = client_id
        receiver_id = freelancer_id
    elif normalized_sender_role == "freelancer":
        sender_id = freelancer_id
        receiver_id = client_id
    else:
        raise ValueError("sender_role must be either 'client' or 'freelancer'")

    if not sender_id:
        raise ValueError("Approved contract chat message is missing senderId")

    meta = _as_dict(normalized_contract_data.get("meta"))
    approval = _as_dict(normalized_contract_data.get("approval"))
    contract_status = str(approval.get("contractStatus", "")).strip().lower()
    if contract_status != "approved":
        return

    contract_title = str(meta.get("title", "")).strip()
    summary = _string_list(meta.get("summary"))
    safe_contract_text = str(contract_text or "").strip()

    existing_messages = (
        chat_ref.collection("messages")
        .where("type", "==", "contract")
        .where("requestId", "==", normalized_request_id)
        .stream()
    )

    for existing_message in existing_messages:
        existing_data = _as_dict(existing_message.to_dict())
        existing_status = str(
            existing_data.get("contractStatus", existing_data.get("status", ""))
        ).strip().lower()
        existing_title = str(existing_data.get("contractTitle", "")).strip()
        existing_text = str(existing_data.get("contractText", "")).strip()

        if (
            existing_status == "approved"
            and existing_title == contract_title
            and existing_text == safe_contract_text
        ):
            return

    unread_count_client = _safe_int(chat_data.get("unreadCountClient", 0))
    unread_count_freelancer = _safe_int(
        chat_data.get("unreadCountFreelancer", 0)
    )

    if normalized_sender_role == "client" and receiver_id:
        unread_count_freelancer += 1
    elif normalized_sender_role == "freelancer" and receiver_id:
        unread_count_client += 1

    chat_ref.collection("messages").add({
        "senderId": sender_id,
        "text": "Approved Contract",
        "type": "contract",
        "requestId": normalized_request_id,
        "status": contract_status,
        "contractStatus": contract_status,
        "contractTitle": contract_title,
        "contractSummary": summary,
        "contractText": safe_contract_text,
        "timestamp": firestore.SERVER_TIMESTAMP,
        "isRead": False,
    })

    chat_ref.set({
        "clientId": client_id,
        "freelancerId": freelancer_id,
        "requestId": normalized_request_id,
        "lastMessage": "Approved Contract",
        "updatedAt": firestore.SERVER_TIMESTAMP,
        "unreadCountClient": unread_count_client,
        "unreadCountFreelancer": unread_count_freelancer,
    }, merge=True)

def get_termination_grace_period_minutes(data=None, default_minutes=30):
    if not data:
        return default_minutes

    minutes = data.get("terminationGraceMinutes")

    if minutes is None:
        return default_minutes

    return minutes
