print("FILE STARTED")

import os
from dotenv import load_dotenv

os.environ["HF_HOME"] = "D:/huggingface"
os.environ["TRANSFORMERS_CACHE"] = "D:/huggingface"

load_dotenv()
load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))

from flask import Flask, request, jsonify
from contract_routes import contract_routes

app = Flask(__name__)
app.register_blueprint(contract_routes)


@app.after_request
def add_cors_headers(response):
    # يسمح لتطبيق الويب (Flutter web على localhost) يتواصل مع هذا
    # السيرفر — بدونه المتصفح يرفض الطلب بصمت بسبب سياسة CORS حتى لو
    # السيرفر رد فعلياً.
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
    return response


# =========================
# Temporary analyze endpoint
# Shows freelancers while AI model is disabled
# =========================
@app.route("/analyze", methods=["POST"])
def analyze():
    try:
        data = request.get_json(force=True) or {}

        description = data.get("description", "")
        images = data.get("images", [])

        print("Analyze request received")
        print("Description:", description)
        print("Images count:", len(images) if isinstance(images, list) else 0)

        return jsonify({
            "matchedWorks": 1,
            "matchPercentage": 85,
            "message": "Temporary match result while AI analysis is disabled."
        }), 200

    except Exception as e:
        print("Analyze endpoint error:", e)

        return jsonify({
            "matchedWorks": 0,
            "matchPercentage": 0,
            "error": str(e)
        }), 500


# =========================
# AI imports temporarily disabled
# =========================
# import torch
# torch.set_num_threads(1)
#
# import open_clip
# from PIL import Image
# import requests
# from io import BytesIO


# =========================
# AI model loading temporarily disabled
# =========================
# print("BEFORE MODEL")
#
# model, _, preprocess = open_clip.create_model_and_transforms(
#     "RN50",
#     pretrained="openai"
# )
#
# print("AFTER MODEL")
#
# tokenizer = open_clip.get_tokenizer("RN50")
#
# device = "cpu"
# model = model.to(device)
# model.eval()


# =========================
# AI analysis function temporarily disabled
# =========================
# def analyze_match(description, image_urls):
#     if not image_urls:
#         return 0, 0
#
#     stop_words = {
#         "i", "want", "need", "a", "an", "the",
#         "please", "to", "for", "looking", "look",
#         "my", "me", "and"
#     }
#
#     words = [
#         w.strip(".,!?").lower()
#         for w in description.split()
#         if w.strip(".,!?").lower() not in stop_words
#     ]
#
#     if not words:
#         return 0, 0
#
#     main_word = words[-1]
#     attribute_words = words[:-1]
#     single_word_mode = len(words) == 1
#
#     text_list = [main_word] + attribute_words
#     text_tokens = tokenizer(text_list).to(device)
#
#     with torch.no_grad():
#         text_features = model.encode_text(text_tokens)
#         text_features /= text_features.norm(dim=-1, keepdim=True)
#
#     best_percentage = 0
#
#     for url in image_urls:
#         try:
#             response = requests.get(url, timeout=15)
#             response.raise_for_status()
#
#             image = Image.open(BytesIO(response.content)).convert("RGB")
#             image_tensor = preprocess(image).unsqueeze(0).to(device)
#
#             with torch.no_grad():
#                 image_features = model.encode_image(image_tensor)
#                 image_features /= image_features.norm(dim=-1, keepdim=True)
#
#             similarities = (image_features @ text_features.T).squeeze().tolist()
#
#             if isinstance(similarities, (int, float)):
#                 similarities = [similarities]
#
#             main_score = similarities[0] if len(similarities) > 0 else 0
#             percentage = 0
#
#             if single_word_mode:
#                 percentage = 100 if main_score > 0.20 else 0
#             else:
#                 if main_score > 0.20:
#                     percentage = 90
#
#                     if len(attribute_words) > 0:
#                         attribute_weight = 10 / len(attribute_words)
#
#                         for i in range(1, len(text_list)):
#                             if i >= len(similarities):
#                                 continue
#
#                             score = similarities[i]
#
#                             if score > 0.30:
#                                 percentage += attribute_weight
#                             elif score > 0.20:
#                                 percentage += attribute_weight * 0.5
#
#             if percentage > best_percentage:
#                 best_percentage = percentage
#
#         except Exception as e:
#             print(f"Failed image: {url} | {e}")
#
#     return 0, round(best_percentage)


# =========================
# Real AI endpoint temporarily disabled
# =========================
# @app.route("/analyze", methods=["POST"])
# def analyze_ai():
#     data = request.get_json(force=True)
#
#     description = data.get("description", "")
#     images = data.get("images", [])
#
#     matched, percentage = analyze_match(description, images)
#
#     return jsonify({
#         "matchedWorks": matched,
#         "matchPercentage": percentage
#     })


if __name__ == "__main__":
    # threaded=True matters here: Flask's dev server handles one request at
    # a time by default, so with two test accounts hitting the backend
    # around the same moment, a slow request could hold up an unrelated one
    # until it hit the client's 25s timeout ("Check your internet or
    # server") even though nothing was actually wrong.
    app.run(host="0.0.0.0", port=5001, debug=True, threaded=True)
