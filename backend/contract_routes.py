from flask import Blueprint, jsonify, request, send_file
import os
import requests
import traceback
from datetime import datetime
from dotenv import load_dotenv
from firebase_admin import firestore
import firebase_service
from firebase_service import (
    get_contract_source_by_id,
    get_request_by_id,
    update_announcement_contract_data,
    update_announcement_proposal_contract_data,
    update_request_contract_data,
)
from pdf_service import generate_contract_pdf

from contract_controller import (
    approve_termination,
    approve_contract,
    cancel_contract,
    cancel_termination,
    cancel_approval,
    delete_contract,
    disapprove_contract,
    generate_contract_from_data,
    generate_contract_from_request_id,
    reject_termination,
    request_termination,
    update_contract,
)


# Keep all contract endpoints together so server.py only handles app setup.
contract_routes = Blueprint("contract_routes", __name__)
load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))


def _safe_notification_text(value, fallback):
    text = str(value or "").strip()
    return text or fallback


@contract_routes.route("/send-notification-push", methods=["POST"])
def send_notification_push_api():
    try:
        data = request.get_json(force=True) or {}
        receiver_id = str(data.get("receiverId", "")).strip()
        title = _safe_notification_text(data.get("title"), "Saneea")
        body = _safe_notification_text(
            data.get("body"),
            "You have a new update.",
        )
        payload = data.get("data") if isinstance(data.get("data"), dict) else {}

        if not receiver_id:
            return jsonify({
                "success": False,
                "error": "receiverId is required",
            }), 400

        result = firebase_service.send_push_notification_to_user(
            receiver_id,
            title,
            body,
            payload,
        )
        return jsonify(result), 200

    except Exception as error:
        return jsonify({
            "success": False,
            "error": str(error),
        }), 500


@contract_routes.route("/generate-contract", methods=["POST"])
def generate_contract():
    try:
        data = request.get_json(force=True)
        result = generate_contract_from_data(data)
        return jsonify(result), 200

    except Exception as error:
        return jsonify({
            "success": False,
            "error": str(error)
        }), 500


@contract_routes.route("/generate-contract-from-request-id", methods=["POST"])
def generate_contract_api():
    try:
        print("DEBUG ROUTE TRACEBACK VERSION ACTIVE")
        data = request.get_json(force=True)
        request_id = data.get("requestId", "")
        proposal_id = data.get("proposalId", "")

        if not request_id:
            return jsonify({
                "success": False,
                "error": "requestId is required"
            }), 400

        result = generate_contract_from_request_id(request_id, proposal_id)
        return jsonify(result), 200

    except Exception as error:
        print("ERROR in /generate-contract-from-request-id:", error)
        traceback.print_exc()
        return jsonify({
            "success": False,
            "error": str(error)
        }), 500


@contract_routes.route("/approve-contract", methods=["POST"])
def approve_contract_api():
    try:
        data = request.get_json(force=True)
        request_id = data.get("requestId", "")
        role = data.get("role", "")
        termination_mode = data.get("terminationMode", "")
        signature_data = data.get("signatureData", "")
        proposal_id = data.get("proposalId", "")

        if not request_id:
            return jsonify({
                "success": False,
                "error": "requestId is required"
            }), 400

        if not role:
            return jsonify({
                "success": False,
                "error": "role is required"
            }), 400

        result = approve_contract(request_id, role, signature_data, proposal_id)
        status_code = 200 if result.get("success") else 404
        return jsonify(result), status_code

    except ValueError as error:
        return jsonify({
            "success": False,
            "error": str(error)
        }), 400

    except Exception as error:
        return jsonify({
            "success": False,
            "error": str(error)
        }), 500


@contract_routes.route("/request-termination", methods=["POST"])
def request_termination_api():
    try:
        data = request.get_json(force=True)
        request_id = data.get("requestId", "")
        role = data.get("role", "")
        termination_mode = data.get("terminationMode", "")
        proposal_id = data.get("proposalId", "")

        if not request_id:
            return jsonify({
                "success": False,
                "error": "requestId is required"
            }), 400

        if not role:
            return jsonify({
                "success": False,
                "error": "role is required"
            }), 400

        result = request_termination(request_id, role, termination_mode, proposal_id)
        status_code = 200 if result.get("success") else 400
        return jsonify(result), status_code

    except ValueError as error:
        return jsonify({
            "success": False,
            "error": str(error)
        }), 400

    except Exception as error:
        return jsonify({
            "success": False,
            "error": str(error)
        }), 500


@contract_routes.route("/approve-termination", methods=["POST"])
def approve_termination_api():
    try:
        data = request.get_json(force=True)
        request_id = data.get("requestId", "")
        role = data.get("role", "")
        proposal_id = data.get("proposalId", "")

        if not request_id:
            return jsonify({
                "success": False,
                "error": "requestId is required"
            }), 400

        if not role:
            return jsonify({
                "success": False,
                "error": "role is required"
            }), 400

        result = approve_termination(request_id, role, proposal_id)
        status_code = 200 if result.get("success") else 400
        return jsonify(result), status_code

    except ValueError as error:
        return jsonify({
            "success": False,
            "error": str(error)
        }), 400

    except Exception as error:
        return jsonify({
            "success": False,
            "error": str(error)
        }), 500


@contract_routes.route("/reject-termination", methods=["POST"])
def reject_termination_api():
    try:
        data = request.get_json(force=True)
        request_id = data.get("requestId", "")
        role = data.get("role", "")
        proposal_id = data.get("proposalId", "")

        if not request_id:
            return jsonify({
                "success": False,
                "error": "requestId is required"
            }), 400

        if not role:
            return jsonify({
                "success": False,
                "error": "role is required"
            }), 400

        result = reject_termination(request_id, role, proposal_id)
        status_code = 200 if result.get("success") else 400
        return jsonify(result), status_code

    except ValueError as error:
        return jsonify({
            "success": False,
            "error": str(error)
        }), 400

    except Exception as error:
        return jsonify({
            "success": False,
            "error": str(error)
        }), 500


@contract_routes.route("/cancel-termination", methods=["POST"])
def cancel_termination_api():
    try:
        data = request.get_json(force=True)
        request_id = data.get("requestId", "")
        role = data.get("role", "")
        proposal_id = data.get("proposalId", "")

        if not request_id:
            return jsonify({
                "success": False,
                "error": "requestId is required"
            }), 400

        if not role:
            return jsonify({
                "success": False,
                "error": "role is required"
            }), 400

        result = cancel_termination(request_id, role, proposal_id)
        status_code = 200 if result.get("success") else 400
        return jsonify(result), status_code

    except ValueError as error:
        return jsonify({
            "success": False,
            "error": str(error)
        }), 400

    except Exception as error:
        return jsonify({
            "success": False,
            "error": str(error)
        }), 500


@contract_routes.route("/cancel-approval", methods=["POST"])
def cancel_approval_api():
    try:
        data = request.get_json(force=True)
        request_id = data.get("requestId", "")
        role = data.get("role", "")
        proposal_id = data.get("proposalId", "")

        if not request_id:
            return jsonify({
                "success": False,
                "error": "requestId is required"
            }), 400

        if not role:
            return jsonify({
                "success": False,
                "error": "role is required"
            }), 400

        result = cancel_approval(request_id, role, proposal_id)
        status_code = 200 if result.get("success") else 400
        return jsonify(result), status_code

    except Exception as error:
        return jsonify({
            "success": False,
            "error": str(error)
        }), 500


@contract_routes.route("/disapprove-contract", methods=["POST"])
def disapprove_contract_api():
    try:
        data = request.get_json(force=True)
        request_id = data.get("requestId", "")
        role = data.get("role", "")
        proposal_id = data.get("proposalId", "")

        if not request_id:
            return jsonify({
                "success": False,
                "error": "requestId is required"
            }), 400

        if not role:
            return jsonify({
                "success": False,
                "error": "role is required"
            }), 400

        result = disapprove_contract(request_id, role, proposal_id)
        status_code = 200 if result.get("success") else 404
        return jsonify(result), status_code

    except ValueError as error:
        return jsonify({
            "success": False,
            "error": str(error)
        }), 400

    except Exception as error:
        return jsonify({
            "success": False,
            "error": str(error)
        }), 500


@contract_routes.route("/cancel-contract", methods=["POST"])
def cancel_contract_api():
    try:
        data = request.get_json(force=True)
        request_id = data.get("requestId", "")
        role = data.get("role", "")
        proposal_id = data.get("proposalId", "")

        if not request_id:
            return jsonify({
                "success": False,
                "error": "requestId is required"
            }), 400

        result = cancel_contract(request_id, role, proposal_id)
        status_code = 200 if result.get("success") else 400
        return jsonify(result), status_code

    except Exception as error:
        return jsonify({
            "success": False,
            "error": str(error)
        }), 500


@contract_routes.route("/update-contract", methods=["POST"])
def update_contract_api():
    try:
        data = request.get_json(force=True)
        request_id = data.get("requestId", "")
        proposal_id = data.get("proposalId", "")
        contract_data = data.get("contractData")
        role = data.get("role", "")

        if not request_id:
            return jsonify({
                "success": False,
                "error": "requestId is required"
            }), 400

        if not isinstance(contract_data, dict):
            return jsonify({
                "success": False,
                "error": "contractData is required"
            }), 400

        result = update_contract(request_id, contract_data, role, proposal_id)
        status_code = 200 if result.get("success") else 404
        return jsonify(result), status_code

    except Exception as error:
        return jsonify({
            "success": False,
            "error": str(error)
        }), 500


@contract_routes.route("/delete-contract", methods=["POST"])
def delete_contract_api():
    try:
        data = request.get_json(force=True)
        request_id = data.get("requestId", "")
        proposal_id = data.get("proposalId", "")

        if not request_id:
            return jsonify({
                "success": False,
                "error": "requestId is required"
            }), 400

        result = delete_contract(request_id, proposal_id)
        status_code = 200 if result.get("success") else 404
        return jsonify(result), status_code

    except Exception as error:
        return jsonify({
            "success": False,
            "error": str(error)
        }), 500


@contract_routes.route("/download-contract-pdf", methods=["GET"])
def download_contract_pdf_api():
    try:
        request_id = request.args.get("requestId", "").strip()
        proposal_id = request.args.get("proposalId", "").strip()

        if not request_id:
            return jsonify({
                "success": False,
                "error": "requestId is required"
            }), 400

        source_context = get_contract_source_by_id(request_id, proposal_id or request_id)

        if not source_context:
            return jsonify({
                "success": False,
                "error": "Request not found"
            }), 404

        source_data = source_context.get("data") or {}
        contract_data = source_data.get("contractData")

        if not isinstance(contract_data, dict):
            return jsonify({
                "success": False,
                "error": "No contract found"
            }), 404

        approval = contract_data.get("approval", {})
        contract_status = str(approval.get("contractStatus", "")).strip().lower()
        client_approved = approval.get("clientApproved") is True
        freelancer_approved = approval.get("freelancerApproved") is True

        if (
            contract_status not in {"approved", "completed"}
            or not client_approved
            or not freelancer_approved
        ):
            return jsonify({
                "success": False,
                "error": "Final contract PDF is only available after both parties approve"
            }), 400

        pdf_buffer = generate_contract_pdf(contract_data)

        return send_file(
            pdf_buffer,
            as_attachment=True,
            download_name=f"contract_{request_id}.pdf",
            mimetype="application/pdf"
        )

    except Exception as error:
        return jsonify({
            "success": False,
            "error": str(error)
        }), 500

def _get_moyasar_secret_key():
    secret_key = os.getenv("MOYASAR_SECRET_KEY", "").strip()
    if not secret_key:
        raise RuntimeError("MOYASAR_SECRET_KEY is not configured")
    return secret_key


@contract_routes.route("/verify-payment", methods=["POST"])
def verify_payment_api():
    try:
        data = request.get_json(force=True)

        payment_id = str(data.get("paymentId", "")).strip()
        request_id = str(data.get("requestId", "")).strip()
        paid_by = str(data.get("paidBy", "")).strip()
        raw_milestone_index = data.get("milestoneIndex")

        if not payment_id:
            return jsonify({"success": False, "error": "paymentId is required"}), 400

        if not request_id:
            return jsonify({"success": False, "error": "requestId is required"}), 400

        response = requests.get(
            f"https://api.moyasar.com/v1/payments/{payment_id}",
            auth=(_get_moyasar_secret_key(), "")
        )

        payment = response.json()

        if response.status_code < 200 or response.status_code >= 300:
            return jsonify({"success": False, "error": payment}), 400

        if payment.get("status") != "paid":
            return jsonify({
                "success": False,
                "paymentStatus": payment.get("status", "failed"),
                "deliveryStatus": "approved"
            }), 400

        source_context = get_contract_source_by_id(request_id, request_id)
        if not source_context:
            return jsonify({
                "success": False,
                "error": "Contract source not found"
            }), 404

        source = source_context.get("source")
        source_data = source_context.get("data") or {}
        contract_data = source_data.get("contractData")

        if not isinstance(contract_data, dict):
            return jsonify({
                "success": False,
                "error": "contractData is missing"
            }), 400

        updated_contract_data = dict(contract_data)
        updated_progress_data = dict(updated_contract_data.get("progressData") or {})
        updated_approval_data = dict(updated_contract_data.get("approval") or {})
        now_iso = datetime.now().isoformat()

        existing_milestones = updated_contract_data.get("milestones")
        milestones = (
            [dict(m) if isinstance(m, dict) else {} for m in existing_milestones]
            if isinstance(existing_milestones, list)
            else []
        )

        if milestones:
            # Milestone-aware contract: this payment settles exactly one
            # milestone, not the whole contract.
            try:
                milestone_index = int(raw_milestone_index)
            except (TypeError, ValueError):
                return jsonify({
                    "success": False,
                    "error": "milestoneIndex is required for this contract"
                }), 400

            if not (0 <= milestone_index < len(milestones)):
                return jsonify({
                    "success": False,
                    "error": "milestoneIndex is invalid"
                }), 400

            target_milestone = milestones[milestone_index]
            target_status = str(target_milestone.get("status", "")).strip().lower()
            # Milestones with no deliverable (e.g. milestone 0, paid on
            # signing) become payable as soon as they are "pending" — they
            # never go through submit/approve, so they never reach
            # "approved". Only delivery-bearing milestones require that.
            delivery_required = target_milestone.get("deliveryRequired", True)
            expected_status = "pending" if delivery_required is False else "approved"
            if target_status != expected_status:
                return jsonify({
                    "success": False,
                    "error": "This milestone is not ready for payment"
                }), 400

            if milestone_index > 0:
                previous_status = str(
                    milestones[milestone_index - 1].get("status", "")
                ).strip().lower()
                if previous_status != "paid":
                    return jsonify({
                        "success": False,
                        "error": "A previous milestone has not been paid yet"
                    }), 400

            target_payment_data = dict(target_milestone.get("paymentData") or {})
            target_payment_data.update({
                "paymentStatus": "paid",
                "paymentCompleted": True,
                "paymentCompletedAt": now_iso,
                "transactionId": payment.get("id"),
                "paidAt": now_iso,
                "paidBy": paid_by,
                "amount": payment.get("amount"),
            })
            target_delivery_data = dict(target_milestone.get("deliveryData") or {})
            target_delivery_data["status"] = "paid_delivered"

            target_milestone["paymentData"] = target_payment_data
            target_milestone["deliveryData"] = target_delivery_data
            target_milestone["status"] = "paid"
            milestones[milestone_index] = target_milestone

            is_last_milestone = milestone_index == len(milestones) - 1
            if not is_last_milestone:
                next_milestone = dict(milestones[milestone_index + 1])
                if str(next_milestone.get("status", "")).strip().lower() == "locked":
                    next_milestone["status"] = "pending"
                milestones[milestone_index + 1] = next_milestone

            updated_contract_data["milestones"] = milestones

            # Mirror the flat legacy fields so any reader that hasn't been
            # migrated to the milestones array still sees "what's currently
            # actionable" instead of stale data. For the last milestone that
            # IS the just-paid milestone (the whole contract is now done).
            # For any earlier milestone, the newly-unlocked NEXT milestone
            # is what's now current — mirroring the just-paid milestone's
            # "paid"/"paid_delivered" state here would make legacy readers
            # (e.g. any completion badge still keyed off the flat fields)
            # think the whole contract is finished after just one payment.
            if is_last_milestone:
                updated_contract_data["paymentData"] = target_payment_data
                updated_contract_data["deliveryData"] = target_delivery_data
            else:
                updated_contract_data["paymentData"] = dict(
                    milestones[milestone_index + 1].get("paymentData") or {}
                )
                updated_contract_data["deliveryData"] = dict(
                    milestones[milestone_index + 1].get("deliveryData") or {}
                )
            updated_progress_data["stage"] = "completed" if is_last_milestone else "started"
            updated_progress_data["updatedAt"] = now_iso
            updated_progress_data["updatedBy"] = "system"
            updated_contract_data["progressData"] = updated_progress_data

            if is_last_milestone:
                updated_approval_data["contractStatus"] = "completed"
            updated_contract_data["approval"] = updated_approval_data

            response_payment_status = "paid"
            response_delivery_status = "paid_delivered"
        else:
            # Legacy contract with no milestone schedule — unchanged
            # single-payment, all-or-nothing behavior.
            updated_payment_data = dict(updated_contract_data.get("paymentData") or {})
            updated_delivery_data = dict(updated_contract_data.get("deliveryData") or {})

            updated_payment_data.update({
                "paymentStatus": "paid",
                "paymentCompleted": True,
                "paymentCompletedAt": now_iso,
                "transactionId": payment.get("id"),
                "paidAt": now_iso,
                "paidBy": paid_by,
                "amount": payment.get("amount"),
            })
            updated_delivery_data["status"] = "paid_delivered"
            updated_progress_data["stage"] = "completed"
            updated_progress_data["updatedAt"] = now_iso
            updated_progress_data["updatedBy"] = "system"
            updated_approval_data["contractStatus"] = "completed"

            updated_contract_data["paymentData"] = updated_payment_data
            updated_contract_data["deliveryData"] = updated_delivery_data
            updated_contract_data["progressData"] = updated_progress_data
            updated_contract_data["approval"] = updated_approval_data

            response_payment_status = "paid"
            response_delivery_status = "paid_delivered"

        if source == "request":
            update_request_contract_data(request_id, updated_contract_data)
        elif source == "announcement":
            proposal_id = source_context.get("proposalId") or request_id
            announcement_id = source_context.get("announcementId") or ""
            client_id = source_context.get("clientId") or ""

            update_announcement_proposal_contract_data(
                proposal_id,
                updated_contract_data,
            )

            if client_id and announcement_id:
                update_announcement_contract_data(
                    client_id,
                    announcement_id,
                    updated_contract_data,
                )
        else:
            return jsonify({
                "success": False,
                "error": "Unsupported contract source"
            }), 400

        return jsonify({
            "success": True,
            "paymentStatus": response_payment_status,
            "deliveryStatus": response_delivery_status,
            "contractData": updated_contract_data,
        }), 200

    except Exception as error:
        return jsonify({"success": False, "error": str(error)}), 500


@contract_routes.route("/verify-termination-payment", methods=["POST"])
def verify_termination_payment_api():
    try:
        data = request.get_json(force=True)

        payment_id = str(data.get("paymentId", "")).strip()
        request_id = str(data.get("requestId", "")).strip()
        paid_by = str(data.get("paidBy", "")).strip().lower()

        if not payment_id:
            return jsonify({"success": False, "error": "paymentId is required"}), 400

        if not request_id:
            return jsonify({"success": False, "error": "requestId is required"}), 400

        if paid_by not in ("client", "freelancer"):
            return jsonify({"success": False, "error": "paidBy must be client or freelancer"}), 400

        response = requests.get(
            f"https://api.moyasar.com/v1/payments/{payment_id}",
            auth=(_get_moyasar_secret_key(), "")
        )
        payment = response.json()

        if response.status_code < 200 or response.status_code >= 300:
            return jsonify({"success": False, "error": payment}), 400

        if payment.get("status") != "paid":
            return jsonify({
                "success": False,
                "paymentStatus": payment.get("status", "failed"),
            }), 400

        source_context = get_contract_source_by_id(request_id, request_id)
        if not source_context:
            return jsonify({
                "success": False,
                "error": "Contract source not found"
            }), 404

        source = source_context.get("source")
        source_data = source_context.get("data") or {}
        contract_data = source_data.get("contractData")

        if not isinstance(contract_data, dict):
            return jsonify({
                "success": False,
                "error": "contractData is missing"
            }), 400

        updated_contract_data = dict(contract_data)
        updated_approval_data = dict(updated_contract_data.get("approval") or {})
        updated_termination = dict(updated_approval_data.get("termination") or {})
        payment_map = dict(updated_contract_data.get("payment") or {})
        amount_value = 0.0
        try:
            amount_value = float(str(payment_map.get("amount") or "").strip())
        except (TypeError, ValueError):
            amount_value = 0.0
        compensation_amount = round(amount_value * 0.20, 2) if amount_value > 0 else 0.0
        now_iso = datetime.now().isoformat()

        updated_termination.update({
            "requested": True,
            "requestedBy": paid_by,
            "requestedAt": now_iso,
            "approved": True,
            "approvedBy": paid_by,
            "approvedAt": now_iso,
            "mode": "paid_compensation",
            "requiresCompensation": True,
            "compensationPercentage": 20,
            "compensationAmount": compensation_amount,
            "compensationCurrency": payment_map.get("currency") or "SAR",
            "paymentStatus": "paid",
            "paymentTransactionId": payment.get("id"),
            "paymentAmount": payment.get("amount"),
            "paymentVerifiedAt": now_iso,
            "rejected": False,
            "rejectedBy": "",
            "rejectedAt": "",
        })
        updated_approval_data["termination"] = updated_termination
        updated_approval_data["contractStatus"] = "terminated"
        updated_contract_data["approval"] = updated_approval_data

        if source == "request":
            update_request_contract_data(request_id, updated_contract_data)
        elif source == "announcement":
            proposal_id = source_context.get("proposalId") or request_id
            announcement_id = source_context.get("announcementId") or ""
            client_id = source_context.get("clientId") or ""

            update_announcement_proposal_contract_data(
                proposal_id,
                updated_contract_data,
            )

            if client_id and announcement_id:
                update_announcement_contract_data(
                    client_id,
                    announcement_id,
                    updated_contract_data,
                )
        else:
            return jsonify({
                "success": False,
                "error": "Unsupported contract source"
            }), 400

        return jsonify({
            "success": True,
            "paymentStatus": "paid",
            "contractStatus": "terminated",
            "contractData": updated_contract_data,
        }), 200

    except Exception as error:
        return jsonify({"success": False, "error": str(error)}), 500
