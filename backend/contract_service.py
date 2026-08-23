from datetime import datetime


def build_contract_data(request):
    return {
        "parties": {
            "clientName": request.get("clientName", ""),
            "freelancerName": request.get("freelancerName", "")
        },
        "service": {
            "description": request.get("description", "")
        },
        "payment": {
            "amount": request.get("budget", 0),
            "currency": "SAR",
            "paidAt": None
        },
        "paymentData": {
            "paymentStatus": "pending",
            "paymentCompleted": False,
            "paymentCompletedAt": "",
            "transactionId": "",
            "paidAt": "",
            "paidBy": "",
            "amount": ""
        },

        "progressData": {
            "stage": "started",
            "updatedAt": None,
            "updatedBy": ""
        },
        "deliveryData": {
            "status": "not_submitted",
            "previewImageUrls": [],
            "imageUrls": [],
            "imageItems": [],
            "fileItems": [],
            "finalWorkUrls": [],
            "fileNames": [],
            "linkUrls": [],
            "notes": "",
            "submittedAt": "",
            "submittedBy": "",
            "approvedByClient": False,
            "changesRequestedBy": "",
            "changesRequestedAt": "",
            "approvedBy": "",
            "approvedAt": "",
            "paidAt": ""
        },
        "timeline": {
            "deadline": request.get("deadline", "")
        },
        "meta": {
            "createdAt": datetime.now().strftime("%d/%m/%Y")
        },
        "approval": {
            "clientApproved": False,
            "freelancerApproved": False,
            "contractStatus": "draft"
        },
        "signatures": {
            "clientSignature": None,
            "freelancerSignature": None
        }
    }


def _render_payment_schedule_section(contract_data):
    """Renders a "2b. Payment Schedule" section listing each milestone's
    amount/percentage/trigger/status. Returns "" for contracts generated
    before the milestone schema shipped (no milestones array), so the
    contract text falls back to the plain single lump-sum wording above."""
    milestones = contract_data.get("milestones") or []
    if not isinstance(milestones, list) or not milestones:
        return ""

    currency = contract_data.get("payment", {}).get("currency") or ""
    lines = []
    for position, milestone in enumerate(milestones):
        if not isinstance(milestone, dict):
            continue
        label = milestone.get("label") or f"Milestone {position + 1}"
        amount = milestone.get("amount", "")
        percentage = milestone.get("percentage", "")
        trigger = str(milestone.get("trigger", "")).replace("_", " ").strip()
        status = milestone.get("status", "")
        lines.append(
            f"- {label}: {amount} {currency} ({percentage}%) — due {trigger}, "
            f"status: {status}"
        )

    if not lines:
        return ""

    return "\n\n2b. Payment Schedule\n" + "\n".join(lines)


def render_contract_text(contract_data):
    return f"""
CONTRACT AGREEMENT

Contract Date: {contract_data["meta"]["createdAt"]}
Contract Status: {contract_data["approval"]["contractStatus"]}
Progress: {contract_data.get("progressData", {}).get("stage", "started")}
Delivery: {contract_data.get("deliveryData", {}).get("status", "not_submitted")}
This agreement is made between:

First Party (Client): {contract_data["parties"]["clientName"]}
Second Party (Freelancer): {contract_data["parties"]["freelancerName"]}

1. Service Description
The second party agrees to provide the following service:
{contract_data["service"]["description"]}

2. Payment
The first party agrees to pay a total amount of:
{contract_data["payment"]["amount"]} {contract_data["payment"]["currency"]}
{_render_payment_schedule_section(contract_data)}

3. Deadline
The service must be completed before:
{contract_data["timeline"]["deadline"]}

4. Agreement Basis
This contract is based on the accepted request details agreed upon by both parties.

5. Amendments
Any future changes to this agreement must be accepted by both parties.

6. Approval Status
Client Approved: {contract_data["approval"]["clientApproved"]}
Freelancer Approved: {contract_data["approval"]["freelancerApproved"]}

7. Agreement
Both parties agree to the terms stated above.
""".strip()
