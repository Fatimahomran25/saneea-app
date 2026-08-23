import os
import json
import traceback
from openai import OpenAI
from datetime import datetime, timedelta

from firebase_service import (
    create_approved_contract_chat_message,
    delete_announcement_contract_data,
    delete_announcement_proposal_contract_data,
    delete_request_contract_data,
    get_contract_source_by_id,
    get_termination_grace_period_minutes,
    update_announcement_contract_data,
    update_announcement_proposal_contract_data,
    update_request_contract_data,
)
from contract_service import render_contract_text


OPENAI_MODEL = "gpt-5.1"
DEFAULT_TERMINATION_GRACE_PERIOD_MINUTES = 720

CONTRACT_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "title": {"type": "string"},
        "contractText": {"type": "string"},
        "summary": {
            "type": "array",
            "items": {"type": "string"},
            "maxItems": 8
        },
        "clauses": {
            "type": "array",
            "maxItems": 12,
            "items": {
                "type": "object",
                "additionalProperties": False,
                "properties": {
                    "title": {"type": "string"},
                    "text": {"type": "string"},
                    "category": {
                        "type": "string",
                        "enum": [
                            "scope",
                            "payment",
                            "timeline",
                            "revisions",
                            "delivery",
                            "confidentiality",
                            "liability",
                            "termination",
                            "other"
                        ]
                    },
                    "optional": {"type": "boolean"}
                },
                "required": ["title", "text", "category", "optional"]
            }
        },
        "warnings": {
            "type": "array",
            "items": {"type": "string"},
            "maxItems": 6
        }
    },
    "required": ["title", "contractText", "summary", "clauses", "warnings"]
}


def _get_openai_client():
    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    if not api_key:
        raise ValueError(
            "OPENAI_API_KEY is not set. Configure it before generating contracts."
        )

    return OpenAI(api_key=api_key)


def _extract_refusal_text(response):
    for item in getattr(response, "output", []) or []:
        if getattr(item, "type", "") == "message":
            for content in getattr(item, "content", []) or []:
                if getattr(content, "type", "") == "refusal":
                    refusal = getattr(content, "refusal", "") or getattr(
                        content,
                        "text",
                        "",
                    )
                    if refusal:
                        return str(refusal).strip()

        if getattr(item, "type", "") == "refusal":
            refusal = getattr(item, "refusal", "") or getattr(item, "text", "")
            if refusal:
                return str(refusal).strip()

    return ""

def _parse_iso_datetime(value):
    if not value:
        return None

    text = str(value).strip()
    if not text:
        return None

    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None


def _get_contract_approved_at(contract_data, approval):
    approval_map = approval if isinstance(approval, dict) else {}
    meta = contract_data.get("meta")
    meta_map = meta if isinstance(meta, dict) else {}

    for candidate in (
        approval_map.get("approvedAt"),
        approval_map.get("contractApprovedAt"),
        meta_map.get("approvedAt"),
    ):
        parsed = _parse_iso_datetime(candidate)
        if parsed is not None:
            return parsed

    return None


def _parse_contract_created_at(value):
    parsed = _parse_iso_datetime(value)
    if parsed is not None:
        return parsed, True

    text = str(value or "").strip()
    if not text:
        return None, False

    try:
        return datetime.strptime(text, "%d/%m/%Y"), False
    except ValueError:
        return None, False


def _get_contract_created_at(contract_data, approval):
    meta = contract_data.get("meta")
    meta_map = meta if isinstance(meta, dict) else {}

    for candidate in (
        meta_map.get("createdAtIso"),
        meta_map.get("createdAt"),
    ):
        parsed, _ = _parse_contract_created_at(candidate)
        if parsed is not None:
            return parsed

    return _get_contract_approved_at(contract_data, approval)


def _get_contract_termination_deadline(contract_data, approval):
    grace_period_minutes = get_termination_grace_period_minutes(
        default_minutes=DEFAULT_TERMINATION_GRACE_PERIOD_MINUTES
    )
    meta = contract_data.get("meta")
    meta_map = meta if isinstance(meta, dict) else {}

    explicit_deadline = _parse_iso_datetime(meta_map.get("terminationEligibleUntil"))
    if explicit_deadline is not None:
        return explicit_deadline

    created_at_value = meta_map.get("createdAtIso")
    if created_at_value in (None, ""):
        created_at_value = meta_map.get("createdAt")

    created_at, has_exact_time = _parse_contract_created_at(created_at_value)
    if created_at is not None:
        if not has_exact_time:
            return created_at + timedelta(days=1)
        return created_at + timedelta(minutes=grace_period_minutes)

    approved_at = _get_contract_approved_at(contract_data, approval)
    if approved_at is not None:
        return approved_at + timedelta(minutes=grace_period_minutes)

    return None


def _safe_float(value):
    try:
        return float(str(value or "").strip())
    except (TypeError, ValueError):
        return 0.0
def generate_contract_ai(data):
    source = str(data.get("source", "")).strip().lower()
    description_label = "Project Description"
    description_text = data.get("description", "Not specified")
    announcement_context = ""

    if source == "announcement":
        description_label = "Original Public Announcement Description"
        announcement_context = f"""
Announcement ID: {data.get('announcementId', 'Not specified')}
Proposal ID: {data.get('proposalId', 'Not specified')}
Accepted Freelancer Proposal: {data.get('proposalText', 'Not provided')}

Announcement-specific instructions:
- The contract scope must be based mainly on the original announcement description.
- The freelancer proposal is supporting context only.
- Do not replace the original announcement description with the proposal text.
"""

    payment_schedule_instruction = "Payment Schedule: Not specified — describe payment terms in neutral, general wording."
    raw_amount = data.get("amount")
    if raw_amount not in (None, ""):
        milestone_preview = _build_milestones(raw_amount, data.get("currency"))
        currency_label = data.get("currency") or ""
        payment_schedule_instruction = (
            f"Payment Schedule: {milestone_preview[0]['percentage']}% ("
            f"{milestone_preview[0]['amount']} {currency_label}) due on contract "
            f"signing, {milestone_preview[1]['percentage']}% ("
            f"{milestone_preview[1]['amount']} {currency_label}) due on "
            f"mid-delivery approval, {milestone_preview[2]['percentage']}% ("
            f"{milestone_preview[2]['amount']} {currency_label}) due on final "
            "delivery approval. Describe exactly this schedule — do not invent "
            "a different split or ratio."
        )

    prompt = f"""
Create a professional freelance contract draft using these inputs:

Source: {data.get('source', 'request')}
Client: {data.get('client', 'Client')}
Freelancer: {data.get('freelancer', 'Freelancer')}
Service Type: {data.get('service_type', 'Not specified')}
{description_label}: {description_text}
Budget: {data.get('amount', 'Not specified')}
Currency: {data.get('currency', 'Not specified')}
Deadline: {data.get('deadline', 'Not specified')}
{payment_schedule_instruction}
Extra Requirements: {data.get('extra_requirements', 'None')}
{announcement_context}

Instructions:
- Write clearly and professionally.
- Keep the language readable for non-lawyers.
- Do not invent jurisdiction-specific legal claims.
- Use neutral wording when details are missing.
- Do not include a "Signatures" section or any manual signature/date blank
  lines (e.g. "Signature: ____") at the end of the contract. Signing is
  handled digitally elsewhere in the app, so a printable signature block
  would be misleading here. End the contract after the last substantive
  clause instead.
- Return output strictly matching the JSON schema.
"""

    client = _get_openai_client()

    try:
        response = client.responses.create(
            model=OPENAI_MODEL,
            input=[
                {
                    "role": "system",
                    "content": "You are a professional contract drafting assistant.",
                },
                {
                    "role": "user",
                    "content": prompt,
                },
            ],
            text={
                "format": {
                    "type": "json_schema",
                    "name": "generated_contract",
                    "strict": True,
                    "schema": CONTRACT_SCHEMA,
                }
            },
        )
    except Exception as error:
        raise ValueError(f"OpenAI contract generation failed: {str(error)}") from error

    raw_text = getattr(response, "output_text", "")
    if not isinstance(raw_text, str):
        raw_text = str(raw_text or "")
    raw_text = raw_text.strip()

    if not raw_text:
        refusal_text = _extract_refusal_text(response)
        if refusal_text:
            raise ValueError(
                f"OpenAI refused to generate the contract: {refusal_text}"
            )

        raise ValueError("OpenAI returned an empty contract response.")

    try:
        parsed = json.loads(raw_text)
    except json.JSONDecodeError as error:
        raise ValueError(f"Invalid AI JSON response: {str(error)}") from error

    if not isinstance(parsed, dict):
        raise ValueError("Invalid AI JSON response: expected a JSON object.")

    required_fields = ("title", "contractText", "summary", "clauses", "warnings")
    missing_fields = [field for field in required_fields if field not in parsed]
    if missing_fields:
        raise ValueError(
            "Invalid AI JSON response: missing fields: "
            + ", ".join(missing_fields)
        )

    return parsed


def _empty_delivery_data():
    """Fresh, unsubmitted deliverable state — shared by the legacy flat
    `deliveryData` field and by each milestone's own `deliveryData`, so the
    shape can never drift between the two."""
    return {
        "status": "not_submitted",
        "previewImageUrls": [],
        "imageUrls": [],
        "imageItems": [],
        "fileItems": [],
        "finalWorkUrls": [],
        "fileNames": [],
        "linkUrls": [],
        "notes": "",
        "submittedBy": "",
        "submittedAt": "",
        "changesRequestedBy": "",
        "changesRequestedAt": "",
        "approvedByClient": False,
        "approvedBy": "",
        "approvedAt": "",
    }


def _empty_payment_data():
    """Fresh, unpaid payment state — shared by the legacy flat `paymentData`
    field and by each milestone's own `paymentData`."""
    return {
        "paymentStatus": "pending",
        "paymentCompleted": False,
        "paymentCompletedAt": "",
        "transactionId": "",
        "paidAt": "",
        "paidBy": "",
        "amount": "",
    }


MILESTONE_1_PERCENTAGE = 10
MILESTONE_2_PERCENTAGE = 40
MILESTONE_3_PERCENTAGE = 50


def _build_milestones(amount, currency):
    """Build the 10% / 40% / 50% milestone schedule for a contract's total
    amount: signing, mid-delivery, final delivery. The remainder of the
    10/40 split is absorbed into the last milestone so the three amounts
    always sum exactly to `amount`. Keeps `amount`'s original type (string
    vs number) since `payment.amount` is a passthrough value read elsewhere
    without type normalization.
    """
    def _to_float(value):
        try:
            return float(value)
        except (TypeError, ValueError):
            return None

    total = _to_float(amount)
    is_string_amount = isinstance(amount, str)

    def _format_amount(value):
        rounded = round(value, 2)
        if rounded == int(rounded):
            rounded = int(rounded)
        return str(rounded) if is_string_amount else rounded

    if total is None:
        # Amount couldn't be parsed (missing/invalid) — fall back to
        # leaving every milestone's amount as whatever was passed in
        # rather than guessing; the UI already treats an unparsable
        # amount as invalid (see _openMoyasarPayment's "Invalid payment
        # amount" guard on the frontend).
        milestone_amounts = (amount, amount, amount)
    else:
        m0 = round(total * (MILESTONE_1_PERCENTAGE / 100), 2)
        m1 = round(total * (MILESTONE_2_PERCENTAGE / 100), 2)
        m2 = round(total - m0 - m1, 2)
        milestone_amounts = (
            _format_amount(m0),
            _format_amount(m1),
            _format_amount(m2),
        )

    definitions = [
        {
            "index": 0,
            "key": "signing",
            "label": f"Milestone 1 — Contract Signing ({MILESTONE_1_PERCENTAGE}%)",
            "percentage": MILESTONE_1_PERCENTAGE,
            "trigger": "on_signing",
            "deliveryRequired": False,
        },
        {
            "index": 1,
            "key": "mid_delivery",
            "label": f"Milestone 2 — Mid-Delivery ({MILESTONE_2_PERCENTAGE}%)",
            "percentage": MILESTONE_2_PERCENTAGE,
            "trigger": "mid_delivery",
            "deliveryRequired": True,
        },
        {
            "index": 2,
            "key": "final_delivery",
            "label": f"Milestone 3 — Final Delivery ({MILESTONE_3_PERCENTAGE}%)",
            "percentage": MILESTONE_3_PERCENTAGE,
            "trigger": "final_delivery",
            "deliveryRequired": True,
        },
    ]

    milestones = []
    for definition, milestone_amount in zip(definitions, milestone_amounts):
        milestones.append({
            **definition,
            "amount": milestone_amount,
            "currency": currency,
            # Every milestone starts locked; milestone 0 unlocks (locked ->
            # pending) once both parties approve the contract (see
            # approve_contract), and milestones 1/2 unlock once the
            # previous milestone is paid (see the /verify-payment route).
            "status": "locked",
            "deliveryData": _empty_delivery_data(),
            "paymentData": _empty_payment_data(),
        })

    return milestones


def generate_contract_from_data(request_data):
    print("DEBUG CONTROLLER TRACEBACK VERSION ACTIVE")
    try:
        print("AI working")
        service_data = {
            "description": request_data.get("description"),
            "aiText": None,
        }
        proposal_text = request_data.get("proposalText")
        if isinstance(proposal_text, str) and proposal_text.strip():
            service_data["proposalText"] = proposal_text.strip()

        ai_result = generate_contract_ai({
            "source": request_data.get("source"),
            "announcementId": request_data.get("announcementId"),
            "proposalId": request_data.get("proposalId"),
            "proposalText": request_data.get("proposalText"),
            "client": request_data.get("clientName") or request_data.get("client"),
            "freelancer": request_data.get("freelancerName") or request_data.get("freelancer"),
            "service_type": request_data.get("serviceType") or request_data.get("category"),
            "description": request_data.get("description"),
            "amount": request_data.get("amount") or request_data.get("budget"),
            "currency": request_data.get("currency"),
            "deadline": request_data.get("deadline"),
            "extra_requirements": request_data.get("extraRequirements"),
        })

        print("AI RESULT =>", ai_result)

        created_at = datetime.now()

        contract_data = {
            "parties": {
                "clientName": request_data.get("clientName") or request_data.get("client", "Client"),
                "freelancerName": request_data.get("freelancerName") or request_data.get("freelancer", "Freelancer"),
            },
            "meta": {
                "title": ai_result["title"],
                "summary": ai_result.get("summary", []),
                "warnings": ai_result.get("warnings", []),
                "source": "ai",
                "model": OPENAI_MODEL,
                "createdAt": created_at.strftime("%d/%m/%Y"),
                "createdAtIso": created_at.isoformat(),
                "terminationEligibleUntil": (
                    created_at
                    + timedelta(
                        minutes=get_termination_grace_period_minutes(
                            default_minutes=DEFAULT_TERMINATION_GRACE_PERIOD_MINUTES
                        )
                    )
                ).isoformat(),
            },
            "approval": {
                "clientApproved": False,
                "freelancerApproved": False,
                "contractStatus": "draft",
                "edited": False,
            },
            "signatures": {
                "clientSignature": None,
                "freelancerSignature": None,
            },
            "service": service_data,
            "payment": {
                "amount": request_data.get("amount") or request_data.get("budget"),
                "currency": request_data.get("currency"),
            },
            "paymentData": _empty_payment_data(),
            "milestones": _build_milestones(
                request_data.get("amount") or request_data.get("budget"),
                request_data.get("currency"),
            ),
            "milestoneSchemaVersion": 2,
            "timeline": {
                "deadline": request_data.get("deadline"),
            },
            "progressData": {
                "stage": "started",
                "updatedAt": created_at.isoformat(),
                "updatedBy": "",
            },
            "deliveryData": _empty_delivery_data(),
            "adminReview": {
                "status": "none",
                "requestedBy": "",
                "requestedAt": "",
                "reasonType": "",
                "reasonText": "",
                "relatedArea": "",
            },
            "customClauses": [
                {
                    "title": clause.get("title", ""),
                    "content": clause.get("text", ""),
                    "category": clause.get("category", "other"),
                    "optional": clause.get("optional", False),
                    "source": "ai",
                }
                for clause in ai_result.get("clauses", [])
                if isinstance(clause, dict)
            ],
        }
        contract_data["service"]["aiText"] = ai_result["contractText"]

        return {
            "success": True,
            "contractData": contract_data,
            "contractText": ai_result["contractText"],
            "summary": ai_result.get("summary", []),
        }
    except Exception as error:
        print("ERROR in AI contract generation:", error)
        traceback.print_exc()
        raise


def generate_contract_from_request_id(request_id, proposal_id=None):
    normalized_request_id = str(request_id or "").strip()
    normalized_proposal_id = str(proposal_id or "").strip()
    print(f"received request_id: {normalized_request_id}")
    print(f"received proposal_id: {normalized_proposal_id}")

    contract_source = get_contract_source_by_id(request_id, proposal_id)

    if not contract_source:
        return {
            "success": False,
            "error": "Request not found"
        }

    request_data = contract_source.get("data") or {}
    result = generate_contract_from_data(request_data)

    if contract_source.get("source") == "announcement":
        update_announcement_proposal_contract_data(
            contract_source.get("proposalId") or normalized_proposal_id,
            result["contractData"],
        )
        print(
            "where contractData was saved: "
            + "announcement_requests/"
            + str(contract_source.get("proposalId") or normalized_proposal_id)
        )
    else:
        update_request_contract_data(request_id, result["contractData"])
        print(f"where contractData was saved: requests/{normalized_request_id}")

    result["requestData"] = request_data
    return result


def _load_contract_source(request_id, proposal_id=""):
    # Contracts can live in one of two places depending on how the
    # freelancer was hired: the direct "requests" collection, or (when the
    # chat came from a client's public announcement + accepted proposal)
    # the "announcement_requests" collection. get_contract_source_by_id
    # checks both, the same way generate_contract_from_request_id does, so
    # every action on an existing contract can find it regardless of which
    # hiring flow created it.
    return get_contract_source_by_id(request_id, proposal_id)


def _save_contract_source_data(contract_source, request_id, proposal_id, contract_data):
    # Mirrors update_contract()'s save logic so approve/reject/cancel/
    # termination actions write back to wherever the contract actually
    # came from instead of always assuming the "requests" collection.
    if contract_source.get("source") == "announcement":
        normalized_proposal_id = str(
            contract_source.get("proposalId") or proposal_id or ""
        ).strip()
        if not normalized_proposal_id:
            raise ValueError("proposalId is required for announcement contracts")

        update_announcement_proposal_contract_data(
            normalized_proposal_id,
            contract_data,
        )

        client_id = str(contract_source.get("clientId") or "").strip()
        announcement_id = str(
            contract_source.get("announcementId") or request_id or ""
        ).strip()
        if client_id and announcement_id:
            update_announcement_contract_data(
                client_id,
                announcement_id,
                contract_data,
            )
    else:
        update_request_contract_data(request_id, contract_data)


def _normalize_signatures(signatures):
    raw_signatures = dict(signatures) if isinstance(signatures, dict) else {}
    return {
        "clientSignature": raw_signatures.get("clientSignature"),
        "freelancerSignature": raw_signatures.get("freelancerSignature"),
    }


def _normalize_approval(approval):
    return dict(approval) if isinstance(approval, dict) else {}


def _empty_signatures():
    return {
        "clientSignature": None,
        "freelancerSignature": None,
    }


def _normalize_clause_identity(clause):
    if not isinstance(clause, dict):
        return None

    return (
        str(clause.get("title", "")).strip(),
        str(clause.get("content", clause.get("text", ""))).strip(),
        str(clause.get("category", "")).strip(),
        bool(clause.get("optional", False)),
    )


def _normalize_custom_clauses(raw_clauses, existing_clauses):
    existing_source_by_identity = {}

    for clause in existing_clauses if isinstance(existing_clauses, list) else []:
        if not isinstance(clause, dict):
            continue

        identity = _normalize_clause_identity(clause)
        if identity is None:
            continue

        source = str(clause.get("source", "")).strip().lower()
        if source not in ("ai", "user"):
            if "category" in clause or "optional" in clause:
                source = "ai"
            else:
                source = "user"

        existing_source_by_identity[identity] = source

    normalized_clauses = []

    for clause in raw_clauses if isinstance(raw_clauses, list) else []:
        if not isinstance(clause, dict):
            continue

        normalized_clause = dict(clause)
        source = str(normalized_clause.get("source", "")).strip().lower()

        if source not in ("ai", "user"):
            identity = _normalize_clause_identity(normalized_clause)
            source = existing_source_by_identity.get(identity)

            if source not in ("ai", "user"):
                if "category" in normalized_clause or "optional" in normalized_clause:
                    source = "ai"
                else:
                    source = "user"

        normalized_clause["source"] = source
        normalized_clauses.append(normalized_clause)

    return normalized_clauses


def approve_contract(request_id, role, signature_data, proposal_id=""):
    normalized_role = (role or "").strip().lower()
    normalized_signature_data = (
        signature_data.strip() if isinstance(signature_data, str) else ""
    )

    if normalized_role not in ("client", "freelancer"):
        raise ValueError("role must be either 'client' or 'freelancer'")

    if not normalized_signature_data:
        raise ValueError("signatureData is required")

    print("🔥 APPROVE HIT", request_id, normalized_role)

    contract_source = _load_contract_source(request_id, proposal_id)

    if not contract_source:
        return {
            "success": False,
            "error": "Request not found"
        }

    request_data = contract_source.get("data") or {}
    contract_data = request_data.get("contractData")
    if not isinstance(contract_data, dict):
        generated = generate_contract_from_data(request_data)
        contract_data = generated["contractData"]

    approval = _normalize_approval(contract_data.get("approval"))
    current_contract_status = str(
        approval.get("contractStatus", "draft")
    ).strip().lower()
    if current_contract_status in (
        "rejected",
        "cancelled",
        "canceled",
        "terminated",
        "termination_pending",
    ):
        return {
            "success": False,
            "error": "This contract cannot be approved in its current state"
        }

    previous_contract_status = str(
        approval.get("contractStatus", "")
    ).strip().lower()
    signatures = _normalize_signatures(contract_data.get("signatures"))

    if normalized_role == "client":
        signatures["clientSignature"] = normalized_signature_data
    else:
        signatures["freelancerSignature"] = normalized_signature_data

    approval["clientApproved"] = bool(signatures.get("clientSignature"))
    approval["freelancerApproved"] = bool(signatures.get("freelancerSignature"))

    if approval.get("clientApproved") and approval.get("freelancerApproved"):
        approval["contractStatus"] = "approved"
        approved_at = datetime.now().isoformat()
        approval["contractApprovedAt"] = approved_at

        meta = contract_data.get("meta")
        if not isinstance(meta, dict):
            meta = {}
        meta["approvedAt"] = approved_at
        contract_data["meta"] = meta

        # Milestone 1 ("on signing") becomes payable the moment both
        # parties approve — everything else stays locked until the
        # previous milestone is paid (see the /verify-payment route).
        milestones = contract_data.get("milestones")
        if isinstance(milestones, list) and milestones:
            first_milestone = dict(milestones[0])
            if str(first_milestone.get("status", "")).strip().lower() == "locked":
                first_milestone["status"] = "pending"
                milestones = list(milestones)
                milestones[0] = first_milestone
                contract_data["milestones"] = milestones
    else:
        approval["contractStatus"] = "pending_approval"

    contract_data["approval"] = approval
    contract_data["signatures"] = signatures
    _save_contract_source_data(contract_source, request_id, proposal_id, contract_data)

    contract_text = render_contract_text(contract_data)

    if (
        approval.get("contractStatus") == "approved" and
        previous_contract_status != "approved"
    ):
        create_approved_contract_chat_message(
            request_id=request_id,
            request_data=request_data,
            contract_data=contract_data,
            sender_role=normalized_role,
            contract_text=contract_text,
        )

    return {
        "success": True,
        "contractData": contract_data,
        "contractStatus": approval["contractStatus"],
        "contractText": contract_text,
    }


def cancel_approval(request_id, role, proposal_id=""):
    normalized_role = (role or "").strip().lower()

    contract_source = _load_contract_source(request_id, proposal_id)

    if not contract_source:
        return {
            "success": False,
            "error": "Request not found"
        }

    request_data = contract_source.get("data") or {}
    contract_data = request_data.get("contractData")
    if not isinstance(contract_data, dict):
        return {
            "success": False,
            "error": "No contract found"
        }

    approval = _normalize_approval(contract_data.get("approval"))
    contract_status = str(approval.get("contractStatus", "draft")).strip().lower()
    if contract_status in (
        "rejected",
        "cancelled",
        "canceled",
        "terminated",
        "termination_pending",
    ):
        return {
            "success": False,
            "error": "Approval cannot be cancelled in the current contract state"
        }

    signatures = _normalize_signatures(contract_data.get("signatures"))

    if normalized_role == "client":
        signatures["clientSignature"] = None
    elif normalized_role == "freelancer":
        signatures["freelancerSignature"] = None
    else:
        return {
            "success": False,
            "error": "Invalid role"
        }

    approval["clientApproved"] = bool(signatures.get("clientSignature"))
    approval["freelancerApproved"] = bool(signatures.get("freelancerSignature"))

    if approval.get("clientApproved") and approval.get("freelancerApproved"):
        approval["contractStatus"] = "approved"
    elif approval.get("clientApproved") or approval.get("freelancerApproved"):
        approval["contractStatus"] = "pending_approval"
    else:
        approval["contractStatus"] = "draft"

    contract_data["approval"] = approval
    contract_data["signatures"] = signatures
    _save_contract_source_data(contract_source, request_id, proposal_id, contract_data)

    return {
        "success": True,
        "contractData": contract_data,
        "contractStatus": approval["contractStatus"]
    }


def disapprove_contract(request_id, role, proposal_id=""):
    normalized_role = (role or "").strip().lower()

    if normalized_role not in ("client", "freelancer"):
        raise ValueError("role must be either 'client' or 'freelancer'")

    print("🔥 REJECT HIT", request_id, normalized_role)

    contract_source = _load_contract_source(request_id, proposal_id)

    if not contract_source:
        return {
            "success": False,
            "error": "Request not found"
        }

    request_data = contract_source.get("data") or {}
    contract_data = request_data.get("contractData")
    if not isinstance(contract_data, dict):
        generated = generate_contract_from_data(request_data)
        contract_data = generated["contractData"]

    approval = _normalize_approval(contract_data.get("approval"))
    contract_status = str(approval.get("contractStatus", "draft")).strip().lower()
    if contract_status in (
        "approved",
        "rejected",
        "cancelled",
        "canceled",
        "termination_pending",
        "terminated",
    ):
        return {
            "success": False,
            "error": "This contract cannot be rejected in its current state"
        }

    approval["clientApproved"] = False
    approval["freelancerApproved"] = False
    approval["contractStatus"] = "rejected"
    approval["edited"] = False

    contract_data["approval"] = approval
    contract_data["signatures"] = _empty_signatures()
    _save_contract_source_data(contract_source, request_id, proposal_id, contract_data)

    return {
        "success": True,
        "contractData": contract_data,
        "contractStatus": "rejected",
        "contractText": render_contract_text(contract_data),
    }


def cancel_contract(request_id, role="", proposal_id=""):
    normalized_role = (role or "").strip().lower()

    contract_source = _load_contract_source(request_id, proposal_id)

    if not contract_source:
        return {
            "success": False,
            "error": "Request not found"
        }

    request_data = contract_source.get("data") or {}
    contract_data = request_data.get("contractData")
    if not isinstance(contract_data, dict):
        return {
            "success": False,
            "error": "No contract found"
        }

    approval = contract_data.get("approval")
    if not isinstance(approval, dict):
        approval = {}

    contract_status = str(approval.get("contractStatus", "")).strip().lower()
    if contract_status in (
        "approved",
        "terminated",
        "termination_pending",
        "rejected",
        "cancelled",
        "canceled",
    ):
        return {
            "success": False,
            "error": "This contract can no longer be cancelled"
        }

    if approval.get("clientApproved") is True and approval.get("freelancerApproved") is True:
        return {
            "success": False,
            "error": "Approved contracts cannot be cancelled"
        }

    approval["clientApproved"] = False
    approval["freelancerApproved"] = False
    approval["contractStatus"] = "cancelled"
    approval["cancelled"] = True
    approval["cancelledBy"] = normalized_role
    approval["cancelledAt"] = datetime.now().isoformat()
    approval["edited"] = False

    contract_data["approval"] = approval
    contract_data["signatures"] = _empty_signatures()

    _save_contract_source_data(contract_source, request_id, proposal_id, contract_data)

    return {
        "success": True,
        "contractData": contract_data,
        "contractStatus": approval["contractStatus"],
        "contractText": render_contract_text(contract_data),
    }


def request_termination(request_id, role, termination_mode="", proposal_id=""):
    normalized_role = (role or "").strip().lower()
    normalized_mode = (termination_mode or "").strip().lower()

    if normalized_role not in ("client", "freelancer"):
        raise ValueError("role must be either 'client' or 'freelancer'")

    contract_source = _load_contract_source(request_id, proposal_id)

    if not contract_source:
        return {
            "success": False,
            "error": "Request not found"
        }

    request_data = contract_source.get("data") or {}
    contract_data = request_data.get("contractData")
    if not isinstance(contract_data, dict):
        return {
            "success": False,
            "error": "No contract found"
        }

    approval = _normalize_approval(contract_data.get("approval"))

    contract_status = str(approval.get("contractStatus", "")).strip().lower()
    if contract_status != "approved":
        return {
            "success": False,
            "error": "Only approved contracts can be terminated"
        }

    termination_deadline = _get_contract_termination_deadline(
        contract_data,
        approval,
    )
    can_self_terminate = False

    if termination_deadline is not None:
        can_self_terminate = datetime.now() <= termination_deadline

    if normalized_mode not in ("", "mutual", "paid"):
        return {
            "success": False,
            "error": "Invalid termination mode"
        }

    termination = approval.get("termination")
    if not isinstance(termination, dict):
        termination = {}

    requested_at = datetime.now().isoformat()
    payment = contract_data.get("payment")
    payment_map = payment if isinstance(payment, dict) else {}
    amount_value = _safe_float(payment_map.get("amount"))
    compensation_amount = round(amount_value * 0.20, 2) if amount_value > 0 else 0.0
    direct_paid_termination = (not can_self_terminate) and normalized_mode == "paid"
    requires_mutual_approval = (not can_self_terminate) and not direct_paid_termination

    approval["termination"] = {
        **termination,
        "requested": True,
        "requestedBy": normalized_role,
        "requestedAt": requested_at,
        "approved": can_self_terminate or direct_paid_termination,
        "approvedBy": normalized_role if (can_self_terminate or direct_paid_termination) else "",
        "approvedAt": requested_at if (can_self_terminate or direct_paid_termination) else "",
        "mode": (
            "grace_period"
            if can_self_terminate
            else "paid_compensation"
            if direct_paid_termination
            else "mutual_agreement"
        ),
        "requiresCompensation": direct_paid_termination,
        "compensationPercentage": 20 if direct_paid_termination else 0,
        "compensationAmount": compensation_amount if direct_paid_termination else 0,
        "compensationCurrency": payment_map.get("currency") or "SAR"
    }
    approval["contractStatus"] = (
        "termination_pending" if requires_mutual_approval else "terminated"
    )

    contract_data["approval"] = approval
    _save_contract_source_data(contract_source, request_id, proposal_id, contract_data)

    return {
        "success": True,
        "contractData": contract_data,
        "contractStatus": approval["contractStatus"],
        "contractText": render_contract_text(contract_data),
        "selfTerminated": can_self_terminate or direct_paid_termination,
        "terminationMode": approval["termination"].get("mode", ""),
    }


def approve_termination(request_id, role, proposal_id=""):
    normalized_role = (role or "").strip().lower()

    if normalized_role not in ("client", "freelancer"):
        raise ValueError("role must be either 'client' or 'freelancer'")

    contract_source = _load_contract_source(request_id, proposal_id)

    if not contract_source:
        return {
            "success": False,
            "error": "Request not found"
        }

    request_data = contract_source.get("data") or {}
    contract_data = request_data.get("contractData")
    if not isinstance(contract_data, dict):
        return {
            "success": False,
            "error": "No contract found"
        }

    approval = _normalize_approval(contract_data.get("approval"))

    contract_status = str(approval.get("contractStatus", "")).strip().lower()
    if contract_status != "termination_pending":
        return {
            "success": False,
            "error": "No termination request is pending"
        }

    termination = approval.get("termination")
    if not isinstance(termination, dict) or termination.get("requested") is not True:
        return {
            "success": False,
            "error": "No termination request found"
        }

    requested_by = str(termination.get("requestedBy", "")).strip().lower()
    if requested_by not in ("client", "freelancer"):
        return {
            "success": False,
            "error": "Invalid termination requester"
        }

    if requested_by == normalized_role:
        return {
            "success": False,
            "error": "The requester cannot approve their own termination request"
        }

    approval["termination"] = {
        **termination,
        "approved": True,
        "approvedBy": normalized_role,
        "approvedAt": datetime.now().isoformat(),
    }
    approval["contractStatus"] = "terminated"

    contract_data["approval"] = approval
    _save_contract_source_data(contract_source, request_id, proposal_id, contract_data)

    return {
        "success": True,
        "contractData": contract_data,
        "contractStatus": approval["contractStatus"],
        "contractText": render_contract_text(contract_data),
    }


def reject_termination(request_id, role, proposal_id=""):
    normalized_role = (role or "").strip().lower()

    if normalized_role not in ("client", "freelancer"):
        raise ValueError("role must be either 'client' or 'freelancer'")

    contract_source = _load_contract_source(request_id, proposal_id)

    if not contract_source:
        return {
            "success": False,
            "error": "Request not found"
        }

    request_data = contract_source.get("data") or {}
    contract_data = request_data.get("contractData")
    if not isinstance(contract_data, dict):
        return {
            "success": False,
            "error": "No contract found"
        }

    approval = _normalize_approval(contract_data.get("approval"))

    contract_status = str(approval.get("contractStatus", "")).strip().lower()
    if contract_status != "termination_pending":
        return {
            "success": False,
            "error": "No termination request is pending"
        }

    termination = approval.get("termination")
    if not isinstance(termination, dict) or termination.get("requested") is not True:
        return {
            "success": False,
            "error": "No termination request found"
        }

    requested_by = str(termination.get("requestedBy", "")).strip().lower()
    if requested_by not in ("client", "freelancer"):
        return {
            "success": False,
            "error": "Invalid termination requester"
        }

    if requested_by == normalized_role:
        return {
            "success": False,
            "error": "The requester cannot reject their own termination request"
        }

    approval["termination"] = {
        **termination,
        "requested": False,
        "approved": False,
        "approvedBy": "",
        "approvedAt": "",
        "rejected": True,
        "rejectedBy": normalized_role,
        "rejectedAt": datetime.now().isoformat(),
        "mode": "mutual_rejected",
    }
    approval["contractStatus"] = "approved"

    contract_data["approval"] = approval
    _save_contract_source_data(contract_source, request_id, proposal_id, contract_data)

    return {
        "success": True,
        "contractData": contract_data,
        "contractStatus": approval["contractStatus"],
        "contractText": render_contract_text(contract_data),
    }


def cancel_termination(request_id, role, proposal_id=""):
    normalized_role = (role or "").strip().lower()

    if normalized_role not in ("client", "freelancer"):
        raise ValueError("role must be either 'client' or 'freelancer'")

    contract_source = _load_contract_source(request_id, proposal_id)

    if not contract_source:
        return {
            "success": False,
            "error": "Request not found"
        }

    request_data = contract_source.get("data") or {}
    contract_data = request_data.get("contractData")
    if not isinstance(contract_data, dict):
        return {
            "success": False,
            "error": "No contract found"
        }

    approval = _normalize_approval(contract_data.get("approval"))

    contract_status = str(approval.get("contractStatus", "")).strip().lower()
    if contract_status != "termination_pending":
        return {
            "success": False,
            "error": "No termination request is pending"
        }

    termination = approval.get("termination")
    if not isinstance(termination, dict) or termination.get("requested") is not True:
        return {
            "success": False,
            "error": "No termination request found"
        }

    approval["termination"] = {
        "requested": False,
        "requestedBy": "",
        "requestedAt": "",
        "approved": False,
        "approvedBy": "",
        "approvedAt": "",
        "cancelledBy": normalized_role,
        "cancelledAt": datetime.now().isoformat(),
    }
    approval["contractStatus"] = "approved"

    contract_data["approval"] = approval
    _save_contract_source_data(contract_source, request_id, proposal_id, contract_data)

    return {
        "success": True,
        "contractData": contract_data,
        "contractStatus": approval["contractStatus"],
        "contractText": render_contract_text(contract_data),
    }


def update_contract(request_id, contract_data, role="", proposal_id=""):
    contract_source = get_contract_source_by_id(request_id, proposal_id)

    if not contract_source:
        return {
            "success": False,
            "error": "Request not found"
        }

    source = contract_source.get("source")
    source_data = contract_source.get("data") or {}

    existing_contract_data = source_data.get("contractData")
    if not isinstance(existing_contract_data, dict):
        generated = generate_contract_from_data(source_data)
        existing_contract_data = generated["contractData"]

    existing_parties = existing_contract_data.get("parties")
    existing_meta = existing_contract_data.get("meta")
    existing_approval = existing_contract_data.get("approval")
    existing_signatures = existing_contract_data.get("signatures")
    existing_service = existing_contract_data.get("service")
    existing_payment = existing_contract_data.get("payment")
    existing_timeline = existing_contract_data.get("timeline")
    existing_progress = existing_contract_data.get("progressData")
    existing_delivery = existing_contract_data.get("deliveryData")
    existing_admin_review = existing_contract_data.get("adminReview")
    existing_custom_clauses = existing_contract_data.get("customClauses")
    existing_payment_data = existing_contract_data.get("paymentData")
    existing_milestones = existing_contract_data.get("milestones")

    updated_contract_data = {
        "parties": dict(existing_parties) if isinstance(existing_parties, dict) else {},
        "meta": dict(existing_meta) if isinstance(existing_meta, dict) else {},
        "approval": dict(existing_approval) if isinstance(existing_approval, dict) else {},
        "signatures": _normalize_signatures(existing_signatures),
        "service": dict(existing_service) if isinstance(existing_service, dict) else {},
        "payment": dict(existing_payment) if isinstance(existing_payment, dict) else {},
        "timeline": dict(existing_timeline) if isinstance(existing_timeline, dict) else {},
        "progressData": dict(existing_progress) if isinstance(existing_progress, dict) else {},
        "deliveryData": dict(existing_delivery) if isinstance(existing_delivery, dict) else {},
        "adminReview": dict(existing_admin_review) if isinstance(existing_admin_review, dict) else {},
        "customClauses": list(existing_custom_clauses) if isinstance(existing_custom_clauses, list) else [],
        "paymentData": dict(existing_payment_data) if isinstance(existing_payment_data, dict) else {},
        "milestones": list(existing_milestones) if isinstance(existing_milestones, list) else [],
    }

    if isinstance(contract_data.get("service"), dict):
        updated_contract_data["service"] = dict(contract_data["service"])

    if isinstance(contract_data.get("payment"), dict):
        updated_contract_data["payment"] = dict(contract_data["payment"])

    if isinstance(contract_data.get("timeline"), dict):
        updated_contract_data["timeline"] = dict(contract_data["timeline"])

    if isinstance(contract_data.get("progressData"), dict):
        updated_contract_data["progressData"] = dict(contract_data["progressData"])

    if isinstance(contract_data.get("deliveryData"), dict):
        updated_contract_data["deliveryData"] = dict(contract_data["deliveryData"])

    if isinstance(contract_data.get("adminReview"), dict):
        updated_contract_data["adminReview"] = dict(contract_data["adminReview"])

    if isinstance(contract_data.get("paymentData"), dict):
        updated_contract_data["paymentData"] = dict(contract_data["paymentData"])

    if isinstance(contract_data.get("milestones"), list):
        updated_contract_data["milestones"] = contract_data["milestones"]

    if isinstance(contract_data.get("meta"), dict):
        updated_contract_data["meta"].update(contract_data["meta"])

    if "customClauses" in contract_data:
        raw_clauses = contract_data.get("customClauses")
        if isinstance(raw_clauses, list):
            updated_contract_data["customClauses"] = _normalize_custom_clauses(
                raw_clauses,
                existing_custom_clauses,
            )
        else:
            updated_contract_data["customClauses"] = []

    normalized_role = (role or "").strip().lower()
    updated_approval = updated_contract_data["approval"]
    normalized_existing_meta = (
        dict(existing_meta) if isinstance(existing_meta, dict) else {}
    )
    normalized_existing_service = (
        dict(existing_service) if isinstance(existing_service, dict) else {}
    )
    normalized_existing_payment = (
        dict(existing_payment) if isinstance(existing_payment, dict) else {}
    )
    normalized_existing_timeline = (
        dict(existing_timeline) if isinstance(existing_timeline, dict) else {}
    )
    normalized_existing_custom_clauses = (
        list(existing_custom_clauses) if isinstance(existing_custom_clauses, list) else []
    )
    workflow_only_update = (
        (
            isinstance(contract_data.get("progressData"), dict)
            or isinstance(contract_data.get("deliveryData"), dict)
            or isinstance(contract_data.get("adminReview"), dict)
            or isinstance(contract_data.get("paymentData"), dict)
            or isinstance(contract_data.get("milestones"), list)
        )
        and updated_contract_data["meta"] == normalized_existing_meta
        and updated_contract_data["service"] == normalized_existing_service
        and updated_contract_data["payment"] == normalized_existing_payment
        and updated_contract_data["timeline"] == normalized_existing_timeline
        and updated_contract_data["customClauses"] == normalized_existing_custom_clauses
    )
    had_previous_approval = bool(updated_approval.get("clientApproved")) or bool(
        updated_approval.get("freelancerApproved")
    )
    was_edited = updated_approval.get("contractStatus") == "edited" or bool(
        updated_approval.get("edited")
    )

    if workflow_only_update:
        updated_contract_data["signatures"] = _normalize_signatures(existing_signatures)
    elif had_previous_approval or was_edited:
        updated_approval["clientApproved"] = False
        updated_approval["freelancerApproved"] = False
        updated_approval["contractStatus"] = "edited"
        updated_approval["edited"] = True
        updated_approval["lastEditedBy"] = normalized_role
        updated_approval["lastEditedAt"] = datetime.now().isoformat()
        updated_contract_data["signatures"] = _empty_signatures()
    else:
        updated_approval["contractStatus"] = (
            updated_approval.get("contractStatus") or "draft"
        )
        updated_approval["edited"] = False

    if source == "request":
        update_request_contract_data(request_id, updated_contract_data)
    elif source == "announcement":
        normalized_proposal_id = str(
            contract_source.get("proposalId") or proposal_id or ""
        ).strip()
        announcement_id = str(
            contract_source.get("announcementId") or request_id or ""
        ).strip()
        client_id = str(contract_source.get("clientId") or "").strip()

        if not normalized_proposal_id:
            return {
                "success": False,
                "error": "proposalId is required for announcement contracts"
            }

        update_announcement_proposal_contract_data(
            normalized_proposal_id,
            updated_contract_data,
        )

        if client_id and announcement_id:
            update_announcement_contract_data(
                client_id,
                announcement_id,
                updated_contract_data,
            )
    else:
        return {
            "success": False,
            "error": "Unsupported contract source"
        }

    return {
        "success": True,
        "contractData": updated_contract_data,
        "contractText": render_contract_text(updated_contract_data)
    }


def delete_contract(request_id, proposal_id=""):
    contract_source = _load_contract_source(request_id, proposal_id)

    if not contract_source:
        return {
            "success": False,
            "error": "Request not found"
        }

    if contract_source.get("source") == "announcement":
        normalized_proposal_id = str(
            contract_source.get("proposalId") or proposal_id or ""
        ).strip()
        if not normalized_proposal_id:
            return {
                "success": False,
                "error": "proposalId is required for announcement contracts"
            }
        delete_announcement_proposal_contract_data(normalized_proposal_id)

        client_id = str(contract_source.get("clientId") or "").strip()
        announcement_id = str(
            contract_source.get("announcementId") or request_id or ""
        ).strip()
        if client_id and announcement_id:
            delete_announcement_contract_data(client_id, announcement_id)
    else:
        delete_request_contract_data(request_id)

    return {
        "success": True
    }
