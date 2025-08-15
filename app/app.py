from flask import Flask, render_template, request, redirect, session, flash
import boto3
import os
from functools import wraps


app = Flask(__name__)
app.secret_key = os.environ["FLASK_SECRET_KEY"]

bucket_name = os.environ["S3_BUCKET"]
s3 = boto3.client("s3")


def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get("authenticated"):
            return redirect("/login")
        return f(*args, **kwargs)

    return decorated


@app.route("/")
@login_required
def index():
    try:
        response = s3.list_objects_v2(Bucket=bucket_name)
        files = response.get("Contents", [])
    except Exception as e:
        files = []
        flash(f"Error fetching files: {str(e)}", "error")

    return render_template("index.html", files=files)


@app.route("/delete", methods=["POST"])
@login_required
def delete_file():
    key = request.form.get("key", "").strip()

    if not key:
        flash("No file selected for deletion.", "error")
        return redirect("/")

    try:
        s3.delete_object(Bucket=bucket_name, Key=key)
        flash(f"{key} deleted successfully.", "success")
    except Exception as e:
        flash(f"Error deleting {key}: {str(e)}", "error")

    return redirect("/")


@app.route("/upload", methods=["POST"])
@login_required
def upload():
    file = request.files["file"]
    if file:
        try:
            s3.upload_fileobj(file, bucket_name, file.filename)
            flash(f"{file.filename} uploaded successfully!", "success")
        except Exception as e:
            flash(f"Upload failed: {str(e)}", "error")
    return redirect("/")



@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        password = request.form.get("password")
        if password == os.environ["DASHBOARD_PASSWORD"]:
            session["authenticated"] = True
            return redirect("/")
        flash("Invalid password.", "error")
    return render_template("login.html")


@app.route("/logout")
def logout():
    session.clear()
    return redirect("/login")
